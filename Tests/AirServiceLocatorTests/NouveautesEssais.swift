import Foundation
import Testing
@testable import AirServiceLocator

/// Les notifications sans tiers, côté application (`protocole.md` §2) : la
/// différence avec le déjà-vu, ce que l'appareil en retient, et le flux.
/// Les règles de la différence sont celles d'Android (`NotificationsEssais.kt`),
/// essai pour essai : les deux plates-formes doivent compter pareil.
struct NouveautesEssais {
    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static func id(_ genre: Genre, _ octet: UInt8) -> Identifiant {
        Identifiant(genre: genre, octets: [UInt8](repeating: octet, count: 16))
    }

    private let moi = id(.utilisateur, 1)
    private let alice = id(.utilisateur, 2)

    private func recue(_ octet: UInt8, revoquee: Bool = false) -> Autorisation {
        Autorisation(id: Self.id(.autorisation, octet), accordeePar: alice, accordeeA: moi, portee: .tout,
                     etiquette: "", accordeeLe: Self.instant, revoqueeLe: revoquee ? Self.instant : nil)
    }

    private func donnee(_ octet: UInt8) -> Autorisation {
        Autorisation(id: Self.id(.autorisation, octet), accordeePar: moi, accordeeA: alice, portee: .tout,
                     etiquette: "", accordeeLe: Self.instant, revoqueeLe: nil)
    }

    // MARK: - La différence

    @Test func uneAutorisationNeuveEstSignaleeEtRetenue() {
        let vieille = recue(10)
        let neuve = recue(11)
        let lecture = Nouveautes.lire([vieille, neuve, donnee(12)], moi: moi, dejaVues: [vieille.id])
        #expect(lecture.nouvelles == [neuve])
        #expect(lecture.aRetenir == [vieille.id, neuve.id])
    }

    @Test func ceQuiADejaEteVuNEstPasNeuf() {
        let a = recue(10)
        let b = recue(11)
        #expect(Nouveautes.lire([a, b], moi: moi, dejaVues: [a.id, b.id]).nouvelles.isEmpty)
    }

    @Test func rienDeNeufSansAutorisationEtCeQueJAiDonneNeComptePas() {
        #expect(Nouveautes.lire([], moi: moi, dejaVues: []).nouvelles.isEmpty)
        #expect(Nouveautes.lire([donnee(12)], moi: moi, dejaVues: []).nouvelles.isEmpty)
    }

    @Test func uneRevoqueeAvantDAvoirEteVueNEstPasAnnonceeMaisEstRetenue() {
        let retiree = recue(10, revoquee: true)
        let lecture = Nouveautes.lire([retiree], moi: moi, dejaVues: [])
        #expect(lecture.nouvelles.isEmpty)
        #expect(lecture.aRetenir == [retiree.id])
    }

    /// Un ensemble jamais tenu n'est pas un ensemble vide : des accès de six
    /// mois ne deviennent pas « nouveaux » parce que l'application a été
    /// mise à jour.
    @Test func laPremiereLecturePoseLaReferenceSansRienSignaler() {
        let a = recue(10)
        let lecture = Nouveautes.lire([a], moi: moi, dejaVues: nil)
        #expect(lecture.nouvelles.isEmpty)
        #expect(lecture.aRetenir == [a.id])
    }

    // MARK: - Ce que l'appareil retient

    private static func carnetVierge() -> CarnetNouveautes {
        let suite = "essais.nouveautes.\(UUID().uuidString)"
        return CarnetNouveautes(defauts: UserDefaults(suiteName: suite)!)
    }

    /// Un autre compte sur le même appareil, c'est une première lecture : ce
    /// qu'on a vu de l'ancien ne dit rien du nouveau.
    @Test func leDejaVuSeRangeSousLeCompte() {
        let carnet = Self.carnetVierge()
        #expect(carnet.dejaVues(moi) == nil)
        carnet.retenirVues(moi, [recue(10).id])
        #expect(carnet.dejaVues(moi) == [recue(10).id])
        #expect(carnet.dejaVues(alice) == nil)
    }

    // MARK: - La session : la pastille

    @MainActor
    private func sessionOuverte(_ annuaire: AnnuaireSimule, carnet: CarnetNouveautes) async throws -> Session {
        let session = Session(annuaire: annuaire, signataire: { CleLogicielle() }, carnetNouveautes: carnet) { signataire, invitation in
            try await annuaire.ouvrirCompte(avec: signataire, invitation: invitation)
        }
        try await session.ouvrirCompte()
        return session
    }

    /// La pastille de l'onglet « Accès » : rien à la première lecture, un de
    /// plus pour un accès reçu, zéro une fois montré — et ce qui a été montré
    /// ne revient pas.
    @MainActor
    @Test func laPastilleCompteLesRecuesJamaisMontrees() async throws {
        let session = try await sessionOuverte(AnnuaireSimule(), carnet: Self.carnetVierge())
        let moi = try #require(session.compte?.identifiant)
        func recue(_ octet: UInt8) -> Autorisation {
            Autorisation(id: Self.id(.autorisation, octet), accordeePar: alice, accordeeA: moi, portee: .tout,
                         etiquette: "", accordeeLe: Self.instant, revoqueeLe: nil)
        }
        session.constater([recue(10)])
        #expect(session.nouveautes == 0)
        let lecture = try #require(session.constater([recue(10), recue(11)]))
        #expect(session.nouveautes == 1)
        #expect(lecture.nouvelles.map(\.id) == [recue(11).id])
        session.montrees(lecture)
        #expect(session.nouveautes == 0)
        session.constater([recue(10), recue(11)])
        #expect(session.nouveautes == 0)
    }

    // MARK: - Le flux

    /// Une nouvelle ne porte rien : elle arrive, et c'est tout. Une seule
    /// écoute à la fois ; quand la connexion tombe, le flux se termine, et
    /// seule une nouvelle demande le rouvre.
    @Test func leFluxDitQuIlYADuNeufEtSeTermineAvecLaConnexion() async throws {
        let annuaire = AnnuaireSimule()
        #expect(await annuaire.nouvelles() == nil, "sans compte, rien à écouter")
        _ = try await annuaire.ouvrirCompte(avec: CleLogicielle(), invitation: nil)
        let flux = try #require(await annuaire.nouvelles())
        #expect(await annuaire.nouvelles() == nil, "une seule écoute")
        await annuaire.annoncerUneNouvelle()
        var iterateur = flux.makeAsyncIterator()
        let premiere: Void? = await iterateur.next()
        #expect(premiere != nil)
        await annuaire.couperLesNouvelles()
        let apres: Void? = await iterateur.next()
        #expect(apres == nil)
        #expect(await annuaire.nouvelles() != nil, "la relecture suivante rouvre l'écoute")
    }
}
