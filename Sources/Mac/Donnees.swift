import Observation
import OSLog
import SwiftUI

/// Ce que l'annuaire a rendu, tenu une fois pour le widget ET la fenêtre.
///
/// # Pourquoi hors des vues
///
/// Le widget est un popover qui meurt à chaque fermeture, la fenêtre s'ouvre
/// et se ferme : ni l'un ni l'autre ne peut porter la liste des machines.
/// Elle vit ici, dans l'application, et les deux la regardent — un
/// rechargement lancé de l'un se voit dans l'autre. Rien n'est écrit sur
/// disque ici : le carnet local reste celui de l'annuaire réel.
@MainActor
@Observable
final class Donnees {
    private static let journal = Logger(subsystem: "org.airdesktop.servicelocator", category: "donnees")

    private(set) var machines: [Machine] = []
    private(set) var appareils: [Appareil] = []
    private(set) var autorisations: [Autorisation] = []
    /// `nil` tant qu'on n'a pas demandé ; `.some(nil)` si l'annuaire ne
    /// sait pas la dire.
    private(set) var versionAnnuaire: VersionAnnuaire??
    private(set) var erreur: String?
    private(set) var enCours = false
    /// Quand la dernière relecture a conclu — l'écran le dit, pour qu'on
    /// sache de quand datent les états.
    private(set) var reluA: Date?
    /// Les notifications locales : la permission, et l'annonce.
    let notifications = NotificationsMac()
    /// Ce qui tient l'application éveillée tant qu'une écoute tourne
    /// (``ActiviteTenue``) — une seule, celle de l'écoute en cours.
    private var eveil: ActiviteTenue?

    /// Relit tout ce que la fenêtre montre. Une liste qui échoue n'efface
    /// pas les autres : ce qu'on savait reste, et l'erreur se dit.
    func recharger(_ session: Session) async {
        enCours = true
        defer { enCours = false }
        await session.rafraichirCompte()
        guard session.compte != nil else {
            machines = []
            appareils = []
            autorisations = []
            return
        }
        versionAnnuaire = .some(try? await session.annuaire.version())
        var fautes: [String] = []
        do { machines = try await session.annuaire.machines() } catch { fautes.append(error.messageAnnuaire) }
        do { appareils = try await session.annuaire.appareils() } catch { fautes.append(error.messageAnnuaire) }
        do {
            autorisations = try await session.annuaire.autorisations()
            session.constater(autorisations)
        } catch {
            fautes.append(error.messageAnnuaire)
        }
        erreur = fautes.isEmpty ? nil : fautes.joined(separator: " · ")
        reluA = .now
        if let erreur { Self.journal.notice("relecture partielle : \(erreur, privacy: .public)") }
        await ecouter(session)
    }

    /// Écoute les nouvelles sur la connexion que la relecture vient de
    /// prouver — si elle n'écoute pas déjà.
    ///
    /// # ELLE S'ARRÊTE AVEC LA CONNEXION, ET NE LA REFAIT PAS
    ///
    /// Reconnecter, c'est Touch ID : une écoute qui le demanderait d'elle-même
    /// surprendrait l'utilisateur. Quand la connexion tombe, le flux se
    /// termine ; la prochaine relecture — ouvrir la fenêtre, ⌘R — reprouve la
    /// clé, et rouvre l'écoute ici. Entre les deux, rien n'est perdu :
    /// l'annuaire ne garde pas les nouvelles, mais la relecture avec
    /// différence retrouve ce qui a été accordé.
    ///
    /// Une seule écoute à la fois, et c'est l'annuaire qui le tient : il rend
    /// `nil` quand une tourne déjà. Garder ici une trace de la tâche en
    /// doublerait la règle — et la tâche d'une écoute tombée, pas encore
    /// terminée, empêcherait la suivante de s'ouvrir.
    ///
    /// **Éveillée tant qu'elle écoute.** Sans quoi App Nap l'endort une
    /// minute après le passage de la fenêtre à l'arrière-plan, et la
    /// connexion meurt de silence (``ActiviteTenue`` dit la mesure). L'activité
    /// naît avec l'écoute et finit avec elle, quelle qu'en soit la cause : le
    /// flux se termine toujours — connexion tombée, écoute arrêtée avant une
    /// reconnexion, handle libéré.
    func ecouter(_ session: Session) async {
        guard let flux = await session.annuaire.nouvelles() else { return }
        Self.journal.notice("écoute des nouvelles ouverte")
        // Une seule activité : celle d'une écoute précédente qui n'aurait pas
        // encore constaté sa fin est close ici, avant d'en ouvrir une autre.
        eveil?.terminer()
        let activite = ActiviteTenue(raison: "écoute des nouvelles")
        eveil = activite
        Task { [weak self] in
            for await _ in flux {
                await self?.relireLesAcces(session)
            }
            activite.terminer()
            if self?.eveil === activite { self?.eveil = nil }
            Self.journal.notice("écoute des nouvelles terminée")
            // L'écoute sort quand la connexion tombe : « Non connecté » doit
            // se voir tout de suite, pas à la prochaine relecture.
            await session.relireRacineTenue()
        }
    }

    /// Une nouvelle est arrivée : relire les accès — sur la connexion tenue,
    /// sans geste —, et annoncer s'il y a vraiment du neuf. Une nouvelle
    /// peut ne rien apporter à cet appareil : un accès révoqué, ou déjà
    /// montré par une relecture plus rapide qu'elle.
    private func relireLesAcces(_ session: Session) async {
        guard let lues = try? await session.annuaire.autorisations() else { return }
        autorisations = lues
        if let lecture = session.constater(lues), !lecture.nouvelles.isEmpty {
            await notifications.annoncer()
        }
    }

    func machine(_ id: Identifiant) -> Machine? { machines.first { $0.id == id } }

    /// Les appareils qui tiennent le compte — les révoqués restent dans
    /// l'annuaire, marqués, mais ne comptent pas.
    var appareilsVivants: [Appareil] { appareils.filter { !$0.estRevoque } }
}

/// Où la fenêtre en est : la page ouverte. Portée par l'application, pour
/// que le widget puisse l'ouvrir SUR une machine.
@MainActor
@Observable
final class EtatFenetre {
    enum Page: Hashable {
        case compte
        case machine(Identifiant)
        case appareils
        case acces
    }

    var page: Page? = .compte

    /// Le geste ouvert en feuille, depuis la barre d'outils ou le menu de
    /// l'application : un seul à la fois.
    enum Feuille: Hashable, Identifiable {
        case declarerMachine
        case ceMacMachine
        var id: Self { self }
    }

    var feuille: Feuille?
}
