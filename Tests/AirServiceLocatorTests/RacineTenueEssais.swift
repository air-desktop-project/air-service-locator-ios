import Foundation
import Testing
@testable import AirServiceLocator

/// « Connecté à … » / « Non connecté » : ce que la session dit de la
/// connexion tenue, et comment elle le suit — à la relecture, à la bascule,
/// à la perte.
@MainActor
struct RacineTenueEssais {
    private static let deux = ChoixDAnnuaire.lire(json: Data("""
    {"annuaires": [{"adresse": "n:6630", "nom": "n"}, {"adresse": "a:6630", "nom": "a"}]}
    """.utf8), racinesPEM: Data())

    final class Fabrique: @unchecked Sendable {
        private let verrou = NSLock()
        private var faits: [String: AnnuaireSimule] = [:]
        func fabriquer(_ reglages: AnnuaireReel.Reglages) -> any Annuaire {
            verrou.withLock {
                let banc = AnnuaireSimule()
                faits[reglages.nom] = banc
                return banc
            }
        }
        func banc(_ nom: String) -> AnnuaireSimule? { verrou.withLock { faits[nom] } }
    }

    private func nouvelleSession(_ fabrique: Fabrique) throws -> Session {
        let preference = PreferenceDAnnuaire(defauts: UserDefaults(suiteName: "essais.tenue.\(UUID().uuidString)")!)
        let reelle = Session.reelle(annuaires: Self.deux, preference: preference,
                                    fabrique: { fabrique.fabriquer($0) }, signataire: { CleLogicielle() })
        return try #require(reelle)
    }

    /// Les mots, à la lettre : Android dit les mêmes.
    @Test func lesLibelles() {
        #expect(TextesRacine.connecteA("nitrogen.air-desktop.org") == "Connecté à nitrogen.air-desktop.org")
        #expect(TextesRacine.nonConnecte == "Non connecté")
        #expect(RacineTenue(adresse: "192.0.2.7:6630", nom: nil).affiche == "192.0.2.7:6630")
    }

    @Test func connecteApresLaRelecture() async throws {
        let session = try nouvelleSession(Fabrique())
        #expect(session.racineTenue == nil)
        try await session.ouvrirCompte()
        await session.relireRacineTenue()
        #expect(session.racineTenue?.nom == "banc en mémoire")
    }

    /// Dès qu'on quitte une racine, plus rien n'est tenu — avant même que la
    /// nouvelle ait été jointe.
    @Test func laBasculeDitNonConnecteJusquALaRelecture() async throws {
        let fabrique = Fabrique()
        let session = try nouvelleSession(fabrique)
        try await session.ouvrirCompte()
        await session.relireRacineTenue()
        #expect(session.racineTenue != nil)
        await session.choisirAnnuaire(Self.deux[1])
        #expect(session.racineTenue == nil)
        // La nouvelle racine jointe (ici, un compte y est ouvert), la
        // relecture la dit.
        try await session.ouvrirCompte()
        await session.relireRacineTenue()
        #expect(session.racineTenue != nil)
    }

    /// La connexion tombe — App Nap, une racine qui redémarre : l'écoute
    /// sort, la relecture dit « Non connecté » ; l'écoute rouverte, de
    /// nouveau connecté.
    @Test func laPerteSeVoitEtLeRetourAussi() async throws {
        let fabrique = Fabrique()
        let session = try nouvelleSession(fabrique)
        try await session.ouvrirCompte()
        let banc = try #require(fabrique.banc("n"))
        _ = await banc.nouvelles()
        await banc.couperLesNouvelles()
        await session.relireRacineTenue()
        #expect(session.racineTenue == nil)
        _ = await banc.nouvelles()
        await session.relireRacineTenue()
        #expect(session.racineTenue != nil)
    }
}
