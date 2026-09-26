import Foundation
import Testing
@testable import AirServiceLocator

/// « nouveau » = pas encore montré. Ce que fait l'écran des accès, lecture
/// après lecture, en passant par la session comme lui.
@MainActor
struct MarquesNouveauEssais {
    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let alice = Identifiant(genre: .utilisateur, octets: [UInt8](repeating: 2, count: 16))

    private func sessionOuverte() async throws -> Session {
        let annuaire = AnnuaireSimule()
        let carnet = CarnetNouveautes(defauts: UserDefaults(suiteName: "essais.marques.\(UUID().uuidString)")!)
        let session = Session(annuaire: annuaire, signataire: { CleLogicielle() }, carnetNouveautes: carnet) { signataire, invitation in
            try await annuaire.ouvrirCompte(avec: signataire, invitation: invitation)
        }
        try await session.ouvrirCompte()
        return session
    }

    private func recue(_ octet: UInt8, par moi: Identifiant) -> Autorisation {
        Autorisation(id: Identifiant(genre: .autorisation, octets: [UInt8](repeating: octet, count: 16)),
                     accordeePar: Self.alice, accordeeA: moi, portee: .tout,
                     etiquette: "", accordeeLe: Self.instant, revoqueeLe: nil)
    }

    /// L'écran lit, marque, et la session retient comme vu — ce que fait
    /// `AccesVue.charger`.
    private func lire(_ autorisations: [Autorisation], _ session: Session, _ marques: inout MarquesNouveau) {
        if let lecture = session.constater(autorisations) {
            marques.ajouter(lecture)
            session.montrees(lecture)
        }
    }

    /// Le défaut du 26/09 : une ligne vue gardait « nouveau » tant que la vue
    /// vivait. Montrée, puis l'écran quitté : elle ne l'est plus.
    @Test func montreePuisQuitteeNEstPlusMarquee() async throws {
        let session = try await sessionOuverte()
        let moi = try #require(session.compte?.identifiant)
        var marques = MarquesNouveau()
        lire([], session, &marques)                       // première lecture : la référence
        lire([recue(10, par: moi)], session, &marques)
        #expect(marques.contient(recue(10, par: moi).id))
        // Tant que l'écran est affiché, une relecture ne la démarque pas.
        lire([recue(10, par: moi)], session, &marques)
        #expect(marques.contient(recue(10, par: moi).id))
        marques.quitter()
        // De retour sur l'écran : elle a été vue, elle n'est plus neuve.
        lire([recue(10, par: moi)], session, &marques)
        #expect(!marques.contient(recue(10, par: moi).id))
    }

    /// Une nouvelle arrivée pendant l'affichage est marquée, sans démarquer
    /// celle qui l'était déjà.
    @Test func uneNouvelleArriveePendantLAffichageEstMarquee() async throws {
        let session = try await sessionOuverte()
        let moi = try #require(session.compte?.identifiant)
        var marques = MarquesNouveau()
        lire([], session, &marques)
        lire([recue(10, par: moi)], session, &marques)
        lire([recue(10, par: moi), recue(11, par: moi)], session, &marques)
        #expect(marques.contient(recue(10, par: moi).id))
        #expect(marques.contient(recue(11, par: moi).id))
        #expect(session.nouveautes == 0, "la pastille tombe dès que l'écran les a montrées")
    }

    /// Quitter après une arrivée la démarque aussi : il n'y a pas de
    /// « nouveau » qui survive à l'écran qui l'a montré.
    @Test func quitterDemarqueTout() {
        let moi = Identifiant(genre: .utilisateur, octets: [UInt8](repeating: 1, count: 16))
        let lecture = Nouveautes.lire([recue(10, par: moi), recue(11, par: moi)], moi: moi, dejaVues: [])
        var marques = MarquesNouveau()
        marques.ajouter(lecture)
        #expect(marques.marquees.count == 2)
        marques.quitter()
        #expect(marques.marquees.isEmpty)
    }
}
