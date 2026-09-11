import Observation
import SwiftUI

/// Ce que tous les écrans partagent : l'annuaire à qui parler, et le compte
/// de cet appareil.
@MainActor
@Observable
final class Session {
    let annuaire: any Annuaire
    private(set) var compte: Compte?
    let identite = IdentiteLocale()

    /// Comment on ouvre un compte — séparé de l'annuaire parce qu'en
    /// démonstration, l'ouverture peuple aussi l'annuaire.
    private let ouverture: @Sendable () async throws -> Compte

    init(annuaire: any Annuaire, ouverture: @escaping @Sendable () async throws -> Compte) {
        self.annuaire = annuaire
        self.ouverture = ouverture
    }

    /// Relit le compte que l'annuaire connaît pour cet appareil.
    func rafraichirCompte() async {
        compte = try? await annuaire.compte()
    }

    /// Ouvre le compte, après confirmation biométrique. Sans confirmation, rien
    /// ne part.
    func ouvrirCompte() async throws {
        guard await identite.confirmer(raison: "Ouvrir votre compte sur cet appareil") else {
            throw ErreurAnnuaire.nonConfirme
        }
        compte = try await ouverture()
    }

    func definirAlias(_ alias: String?) async throws {
        try await annuaire.definirAlias(alias)
        await rafraichirCompte()
    }
}
