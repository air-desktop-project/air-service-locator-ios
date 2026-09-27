import Foundation
import Testing
@testable import AirServiceLocator

/// Les domaines et les annuaires locaux : ce que l'application lit des
/// réponses de l'annuaire (formes de `protocole.md`, serveur 0.28.0), quand
/// elle s'offre à les montrer, et les refus qu'elle traduit.
struct DomainesEssais {
    private static func id(_ genre: Genre, _ octet: UInt8) -> Identifiant {
        Identifiant(genre: genre, octets: [UInt8](repeating: octet, count: 16))
    }
    private static let d1 = id(.domaine, 1), d2 = id(.domaine, 2)
    private static let moi = id(.utilisateur, 3), autre = id(.utilisateur, 4)
    private static let n1 = id(.annuaire, 5), n2 = id(.annuaire, 6)
    private static let m1 = id(.machine, 7)

    private static func json(_ texte: String) -> Data { Data(texte.utf8) }

    // MARK: - Lire

    @Test func laListeDesDomaines() {
        let corps = Self.json("""
        [{"domaine":"\(Self.d1.texte)","proprietaire":"\(Self.moi.texte)","alias":"Maison","heberge_par":"racines","droits":["administrer","rattacher","voir","localiser"]},
         {"domaine":"\(Self.d2.texte)","proprietaire":"\(Self.autre.texte)","heberge_par":"\(Self.n1.texte)","droits":["rattacher"]}]
        """)
        let domaines = ReponsesDomaines.domaines(corps)
        #expect(domaines.count == 2)
        #expect(domaines[0].titre == "Maison")
        #expect(domaines[0].hebergePar == .racines)
        #expect(domaines[0].peut("administrer"))
        // Sans alias, le titre est l'identifiant abrégé ; l'hébergeur est l'annuaire local.
        #expect(domaines[1].alias == nil)
        #expect(domaines[1].hebergePar == .annuaire(Self.n1))
        #expect(!domaines[1].peut("administrer"))
        #expect(ReponsesDomaines.domaines(Self.json("[]")).isEmpty)
    }

    @Test func leDetailPorteSesMachines() {
        let corps = Self.json("""
        {"domaine":"\(Self.d1.texte)","proprietaire":"\(Self.moi.texte)","heberge_par":"racines","droits":["voir"],"groupes":[],
         "machines":[{"machine":"\(Self.m1.texte)","proprietaire":"\(Self.moi.texte)","nom":"grenier","alias":"Le grenier"}]}
        """)
        let domaine = ReponsesDomaines.detail(corps)
        #expect(domaine?.machines.count == 1)
        #expect(domaine?.machines.first?.titre == "Le grenier")
        #expect(domaine?.machines.first?.nom == "grenier")
    }

    /// Les cinq états, à la lettre — accents et espace compris.
    @Test func lesAnnuairesEtLeursEtats() {
        let corps = Self.json("""
        [{"etat":"attendue","adresse":"nas.example.org:6630","expire_a":1700000000000},
         {"annuaire":"\(Self.n1.texte)","etat":"attendue","adresse":"nas2.example.org:6630","expire_a":1700000000000},
         {"membre":"\(Self.n1.texte)","annuaire":"\(Self.n1.texte)","etat":"acceptée","adresse":"nas.example.org:6630"},
         {"membre":"\(Self.n2.texte)","annuaire":"\(Self.n1.texte)","etat":"en attente","adresse":"nas2.example.org:6630"},
         {"membre":"\(Self.n2.texte)","annuaire":"\(Self.n2.texte)","etat":"refusée","adresse":"x:1"},
         {"membre":"\(Self.n2.texte)","annuaire":"\(Self.n2.texte)","etat":"retirée","adresse":"x:1"},
         {"etat":"inventée","adresse":"x:1"}]
        """)
        let annuaires = ReponsesDomaines.annuaires(corps)
        #expect(annuaires.map(\.etat) == [.attendue, .attendue, .acceptee, .enAttente, .refusee, .retiree, .inconnu("inventée")])
        #expect(annuaires[0].expireLe == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(annuaires[1].annuaire == Self.n1 && annuaires[1].membre == nil)
        #expect(annuaires[2].estTitulaire)
        #expect(!annuaires[3].estTitulaire)
    }

    @Test func leCodeEtLesInscriptions() {
        let code = ReponsesDomaines.code(Self.json(#"{"code":"4K9M2-P7R1T","expire_a":1700086400000}"#))
        #expect(code?.code == "4K9M2-P7R1T")
        #expect(code?.expireLe == Date(timeIntervalSince1970: 1_700_086_400))
        let inscriptions = ReponsesDomaines.inscriptions(Self.json("""
        [{"membre":"\(Self.n2.texte)","annuaire":"\(Self.n1.texte)","proprietaire":"\(Self.autre.texte)","etat":"en attente","adresse":"nas2.example.org:6630"}]
        """))
        #expect(inscriptions.count == 1)
        #expect(inscriptions.first?.proprietaire == Self.autre)
    }

    // MARK: - Selon la version de la racine

    @Test func cequiSOffreSelonLaVersion() {
        #expect(!VersionAnnuaire(version: "0.22.9", posture: nil).porteLesDomaines)
        #expect(VersionAnnuaire(version: "0.23.0", posture: nil).porteLesDomaines)
        #expect(!VersionAnnuaire(version: "0.26.0", posture: nil).porteLesAnnuairesLocaux)
        #expect(VersionAnnuaire(version: "0.27.0", posture: nil).porteLesAnnuairesLocaux)
        #expect(VersionAnnuaire(version: "0.28.0", posture: nil).porteLesAnnuairesLocaux)
        #expect(!VersionAnnuaire(version: "banc en mémoire", posture: nil).porteLesDomaines)
    }

    @Test func uneAdresseDAnnuaire() {
        #expect(NomsEtAlias.adresseValide("nas.example.org:6630"))
        #expect(NomsEtAlias.adresseValide("[2001:db8::1]:6630"))
        #expect(!NomsEtAlias.adresseValide("nas.example.org"))
        #expect(!NomsEtAlias.adresseValide("nas.example.org:0"))
        #expect(!NomsEtAlias.adresseValide("nas.example.org:65536"))
        #expect(!NomsEtAlias.adresseValide(":6630"))
        #expect(!NomsEtAlias.adresseValide("nas example:6630"))
    }

    // MARK: - Le banc suit l'annuaire

    private func bancOuvert() async throws -> AnnuaireSimule {
        let banc = AnnuaireSimule()
        _ = try await banc.ouvrirCompte(avec: CleLogicielle(), invitation: nil)
        return banc
    }

    /// Le dernier domaine ne se supprime pas : `409`, dit comme tel.
    @Test func leDernierDomaineResteEtLeMessageLeDit() async throws {
        let banc = try await bancOuvert()
        let premier = try #require(try await banc.domaines().first)
        await #expect(throws: ErreurAnnuaire.dernierDomaine) { try await banc.supprimerDomaine(premier.id) }
        #expect(ErreurAnnuaire.dernierDomaine.message == TextesDomaines.dernierDomaine)
        let second = try await banc.creerDomaine(alias: "Maison")
        try await banc.supprimerDomaine(premier.id)
        #expect(try await banc.domaines().map(\.id) == [second])
    }

    @Test func rangerUneMachineSeVoitDansLeDetail() async throws {
        let banc = try await bancOuvert()
        let domaine = try #require(try await banc.domaines().first)
        let machine = try await banc.declarerMachine(nom: "grenier", capacites: [])
        try await banc.ranger(machine: machine.id, dans: domaine.id)
        #expect(try await banc.domaine(domaine.id).machines.map(\.id) == [machine.id])
        try await banc.ranger(machine: machine.id, dans: nil)
        #expect(try await banc.domaine(domaine.id).machines.isEmpty)
    }

    /// Un second membre à la fois ; et un domaine ne se confie qu'à un
    /// annuaire accepté, puis revient aux racines au retrait.
    @Test func laPaireEtLHebergeur() async throws {
        let banc = try await bancOuvert()
        let domaine = try #require(try await banc.domaines().first)
        _ = try await banc.declarerAnnuaire(adresse: "nas.example.org:6630")
        let titulaire = try #require(await banc.accepterAnnuaire(adresse: "nas.example.org:6630"))
        try await banc.confier(domaine: domaine.id, a: titulaire)
        #expect(try await banc.domaine(domaine.id).hebergePar == .annuaire(titulaire))
        _ = try await banc.declarerSecondMembre(de: titulaire, adresse: "nas2.example.org:6630")
        await #expect(throws: ErreurAnnuaire.secondMembreDejaDeclare) {
            _ = try await banc.declarerSecondMembre(de: titulaire, adresse: "nas3.example.org:6630")
        }
        try await banc.retirerAnnuaire(titulaire)
        #expect(try await banc.domaine(domaine.id).hebergePar == .racines)
    }

    /// Le banc n'administre pas les racines : l'écran d'administration ne
    /// s'offre pas.
    @Test func pasDAdministrationPourQuiNAdministrePas() async throws {
        let banc = try await bancOuvert()
        #expect(try await banc.inscriptions() == nil)
    }
}
