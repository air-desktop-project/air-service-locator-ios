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
    private(set) var versionAnnuaire: String??
    private(set) var erreur: String?
    private(set) var enCours = false
    /// Quand la dernière relecture a conclu — l'écran le dit, pour qu'on
    /// sache de quand datent les états.
    private(set) var reluA: Date?

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
        do { autorisations = try await session.annuaire.autorisations() } catch { fautes.append(error.messageAnnuaire) }
        erreur = fautes.isEmpty ? nil : fautes.joined(separator: " · ")
        reluA = .now
        if let erreur { Self.journal.notice("relecture partielle : \(erreur, privacy: .public)") }
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
