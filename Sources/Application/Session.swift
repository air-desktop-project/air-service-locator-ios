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
    private let ouverture: @Sendable (any Signataire) async throws -> Compte
    /// D'où vient la clé : la Secure Enclave sur un appareil, une clé
    /// logicielle dans un essai.
    private let signataire: @Sendable () throws -> any Signataire

    init(
        annuaire: any Annuaire,
        signataire: @escaping @Sendable () throws -> any Signataire = { try CleAppareil.ouOuvrir() },
        ouverture: @escaping @Sendable (any Signataire) async throws -> Compte
    ) {
        self.annuaire = annuaire
        self.signataire = signataire
        self.ouverture = ouverture
    }

    /// Relit le compte que l'annuaire connaît pour cet appareil.
    func rafraichirCompte() async {
        compte = try? await annuaire.compte()
    }

    /// Ouvre le compte : la clé de l'appareil prouve qu'elle est détenue, sur
    /// le défi de l'annuaire et la liaison du canal.
    ///
    /// **C'est là que la biométrie est demandée**, par la Secure Enclave, au
    /// moment de signer — et nulle part avant. Sans confirmation, la clé ne
    /// signe pas, et rien ne part.
    func ouvrirCompte() async throws {
        compte = try await ouverture(try signataire())
    }

    func definirAlias(_ alias: String?) async throws {
        try await annuaire.definirAlias(alias)
        await rafraichirCompte()
    }
}
