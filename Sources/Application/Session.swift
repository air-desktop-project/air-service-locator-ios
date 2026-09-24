import Observation
import OSLog
import SwiftUI

/// Ce que tous les écrans partagent : l'annuaire à qui parler, et le compte
/// de cet appareil.
@MainActor
@Observable
final class Session {
    let annuaire: any Annuaire
    private(set) var compte: Compte?
    let identite = IdentiteLocale()
    private static let journal = Logger(subsystem: "org.airdesktop.servicelocator", category: "session")

    /// Comment on ouvre un compte — séparé de l'annuaire parce qu'en
    /// démonstration, l'ouverture peuple aussi l'annuaire.
    private let ouverture: @Sendable (any Signataire, CodeInvitation?) async throws -> Compte
    /// D'où vient la clé : la Secure Enclave sur un appareil, une clé
    /// logicielle dans un essai.
    private let signataire: @Sendable () throws -> any Signataire

    init(
        annuaire: any Annuaire,
        signataire: @escaping @Sendable () throws -> any Signataire = { try CleAppareil.ouOuvrir() },
        ouverture: @escaping @Sendable (any Signataire, CodeInvitation?) async throws -> Compte
    ) {
        self.annuaire = annuaire
        self.signataire = signataire
        self.ouverture = ouverture
    }

    /// Ce que la dernière relecture n'a pas pu faire, dit à l'écran : hors
    /// ligne, geste annulé. Un compte connu reste affiché ; seule une preuve
    /// refusée par l'annuaire le retire.
    private(set) var erreurDeRelecture: String?
    /// Vrai tant que la première relecture n'a pas conclu : l'écran ne doit
    /// dire ni « aucun compte » ni « compte » avant de savoir.
    private(set) var premiereRelectureEnCours = true

    /// Relit le compte que l'annuaire connaît pour cet appareil.
    func rafraichirCompte() async {
        defer { premiereRelectureEnCours = false }
        do {
            compte = try await annuaire.compte()
            erreurDeRelecture = nil
            if compte != nil { await seDecrire() }
        } catch ErreurAnnuaire.preuveInvalide {
            compte = nil
            erreurDeRelecture = ErreurAnnuaire.preuveInvalide.message
        } catch {
            // Le compte qu'on connaît reste ; l'annuaire n'a juste pas répondu.
            erreurDeRelecture = error.messageAnnuaire
        }
    }

    /// Ouvre le compte : la clé de l'appareil prouve qu'elle est détenue, sur
    /// le défi de l'annuaire et la liaison du canal.
    ///
    /// **C'est là que la biométrie est demandée**, par la Secure Enclave, au
    /// moment de signer — et nulle part avant. Sans confirmation, la clé ne
    /// signe pas, et rien ne part.
    /// ``invitation`` n'est attendue que d'une racine en posture
    /// ``PostureAnnuaire/invitation`` ; ailleurs, `nil`.
    func ouvrirCompte(invitation: CodeInvitation? = nil) async throws {
        compte = try await ouverture(try signataire(), invitation)
        await seDecrire()
    }

    /// Dit à l'annuaire ce que cet appareil est — plate-forme et modèle,
    /// jamais le nom que l'utilisateur lui a donné (`docs/modele.md` §2.2).
    /// Juste après chaque preuve : c'est le moment où l'appareil parle de
    /// lui sur sa propre connexion.
    ///
    /// **Une étiquette qui n'a pas pu se poser n'est pas une panne.** Un
    /// annuaire qui ne sert pas encore ce verbe rend `404` ; le compte, lui,
    /// est là. On ne le dit pas à l'écran, et l'annuaire réel n'en garde pas
    /// trace comme posée — elle repartira à la prochaine preuve.
    private func seDecrire() async {
        do {
            try await annuaire.decrire(Appareil.Description.deCetAppareil())
        } catch {
            Self.journal.notice("la description de cet appareil n'a pas été posée : \(error.messageAnnuaire, privacy: .public)")
        }
    }

    /// La clé publique de cet appareil — ce que le nouveau téléphone montre à
    /// l'ancien. La lire ne demande aucun geste : seule la signature en
    /// demande un.
    func clePublique() throws -> [UInt8] {
        try signataire().clePublique
    }

    /// Rejoint un compte, depuis ce téléphone-ci, avec l'invitation que
    /// l'autre a rendue. Le geste est demandé au moment de prouver la clé.
    func rejoindre(compte: Identifiant, appareil: Identifiant) async throws {
        self.compte = try await annuaire.rejoindre(compte: compte, appareil: appareil, avec: try signataire())
        await seDecrire()
    }

    func definirAlias(_ alias: String?) async throws {
        try await annuaire.definirAlias(alias)
        await rafraichirCompte()
    }

    /// Efface le compte — le dernier acte de la clé de cet appareil
    /// (`modele.md` §2.1). L'annuaire d'abord ; puis, ici, la clé est
    /// détruite (elle est révoquée là-bas, la garder ne prouverait plus
    /// rien), le carnet est vidé, et `compte` revient à `nil` : l'écran
    /// d'accueil reprend, comme au premier lancement. `apresLAnnuaire` est
    /// ce que la plate-forme a de plus à oublier — sur le Mac, l'identité de
    /// machine, dont la clé est révoquée avec le compte.
    func effacerCompte(apresLAnnuaire: @MainActor () throws -> Void = {}) async throws {
        try await annuaire.effacerCompte()
        do { try CleAppareil.effacer() } catch { Self.journal.error("la clé n'a pas pu être détruite : \(error.localizedDescription, privacy: .public)") }
        do { try apresLAnnuaire() } catch { Self.journal.error("ce qui suit l'effacement n'a pas pu se faire : \(error.localizedDescription, privacy: .public)") }
        compte = nil
        erreurDeRelecture = nil
    }
}
