import Foundation
import Testing
@testable import AirServiceLocator

/// Choisir sa racine : le fichier qui les décrit, sous ses deux formes, le
/// choix retenu, et la bascule — l'ancienne racine fermée, son écoute
/// arrêtée, avant que la nouvelle serve.
struct ChoixDAnnuaireEssais {
    private static let pem = Data("-----BEGIN CERTIFICATE-----".utf8)

    private static func preferenceVierge() -> PreferenceDAnnuaire {
        PreferenceDAnnuaire(defauts: UserDefaults(suiteName: "essais.annuaire.\(UUID().uuidString)")!)
    }

    // MARK: - Le fichier

    @Test func laListeSeLitDansSonOrdreAvecSesLibelles() {
        let json = Data("""
        {"annuaires": [
          {"adresse": "asl-root.air-desktop.org:6630", "nom": "asl-root.air-desktop.org", "libelle": "Automatique"},
          {"adresse": "nitrogen.air-desktop.org:6630", "nom": "nitrogen.air-desktop.org"},
          {"adresse": "argon.air-desktop.org:6630", "nom": "argon.air-desktop.org"}
        ]}
        """.utf8)
        let annuaires = ChoixDAnnuaire.lire(json: json, racinesPEM: Self.pem)
        #expect(annuaires.map(\.nom) == ["asl-root.air-desktop.org", "nitrogen.air-desktop.org", "argon.air-desktop.org"])
        #expect(annuaires.map(\.affiche) == ["Automatique", "nitrogen.air-desktop.org", "argon.air-desktop.org"])
        // Une seule racine PEM, pour toutes.
        #expect(annuaires.allSatisfy { $0.racinesPEM == Self.pem })
    }

    /// Les fichiers déjà posés sur les postes gardent leur sens : un objet
    /// seul est une liste d'un élément.
    @Test func lAncienneFormeEstUneListeDUnElement() {
        let json = Data(#"{"adresse": "nitrogen.air-desktop.org:6630", "nom": "nitrogen.air-desktop.org"}"#.utf8)
        let annuaires = ChoixDAnnuaire.lire(json: json, racinesPEM: Self.pem)
        #expect(annuaires.count == 1)
        #expect(annuaires.first?.adresse == "nitrogen.air-desktop.org:6630")
        #expect(annuaires.first?.libelle == nil)
    }

    @Test func unFichierIllisibleNeDonneRienEtUneAdresseDoubleNeCompteQuUneFois() {
        #expect(ChoixDAnnuaire.lire(json: Data("pas du json".utf8), racinesPEM: Self.pem).isEmpty)
        let double = Data(#"{"annuaires": [{"adresse": "a:1", "nom": "a"}, {"adresse": "a:1", "nom": "b"}]}"#.utf8)
        #expect(ChoixDAnnuaire.lire(json: double, racinesPEM: Self.pem).map(\.nom) == ["a"])
    }

    // MARK: - L'identité par la clé

    private static let nitrogen = "n-0PWT8HZD80QMSPPDZ5CQXXYHQC"
    private static let argon = "n-3K3P6H252W8K9370QG1YYTWBWB"

    private static let identifie = Data("""
    {"annuaires": [
      {"libelle": "Automatique",
       "adresse": "asl-root.air-desktop.org:6630", "nom": "asl-root.air-desktop.org",
       "racines": [
         {"annuaire": "n-0PWT8HZD80QMSPPDZ5CQXXYHQC", "locateurs": ["[2001:41d0:20a:900::1dd4]:6630", "178.32.16.250:6630"]},
         {"annuaire": "n-3K3P6H252W8K9370QG1YYTWBWB", "locateurs": ["[2001:41d0:20a:900::1d32]:6630", "178.32.16.249:6630"]}]},
      {"adresse": "nitrogen.air-desktop.org:6630", "nom": "nitrogen.air-desktop.org",
       "annuaire": "n-0PWT8HZD80QMSPPDZ5CQXXYHQC", "locateurs": ["[2001:41d0:20a:900::1dd4]:6630", "178.32.16.250:6630"]},
      {"annuaire": "n-3K3P6H252W8K9370QG1YYTWBWB", "locateurs": ["[2001:41d0:20a:900::1d32]:6630", "178.32.16.249:6630"]}
    ]}
    """.utf8)

    @Test func laFormeIdentifieeSeLitSousSesDeuxEcritures() {
        let annuaires = ChoixDAnnuaire.lire(json: Self.identifie, racinesPEM: Self.pem)
        #expect(annuaires.map(\.affiche) == ["Automatique", "nitrogen.air-desktop.org", "argon.air-desktop.org"])
        #expect(annuaires[0].identites.map(\.annuaire) == [Self.nitrogen, Self.argon])
        let attendue = AnnuaireReel.RacineIdentifiee(annuaire: Self.nitrogen, locateurs: ["[2001:41d0:20a:900::1dd4]:6630", "178.32.16.250:6630"])
        #expect(annuaires[1].identites == [attendue])
        #expect(annuaires.allSatisfy { $0.parIdentite })
    }

    /// Une préférence retenue hier par l'adresse désigne la même entrée ; une
    /// entrée sans adresse se désigne par ses identités.
    @Test func laCleEstLAdresseDHierSinonLesIdentites() {
        let annuaires = ChoixDAnnuaire.lire(json: Self.identifie, racinesPEM: Self.pem)
        #expect(annuaires.map(\.cle) == ["asl-root.air-desktop.org:6630", "nitrogen.air-desktop.org:6630", Self.argon])
        let preference = Self.preferenceVierge()
        preference.retenir(annuaires[2])
        #expect(preference.choisi(parmi: annuaires)?.nom == "argon.air-desktop.org")
    }

    /// Aucun nom ne se résout : un locateur qui n'est pas littéral se laisse
    /// de côté, et une racine qui n'en garde aucun aussi — comme un `n-…` de
    /// travers.
    @Test func unLocateurQuiNEstPasLitteralSeLaisseDeCote() {
        let json = Data("""
        {"annuaires": [
          {"annuaire": "n-0PWT8HZD80QMSPPDZ5CQXXYHQC", "locateurs": ["nitrogen.air-desktop.org:6630", "178.32.16.250:6630", "[::1]", "[2001:db8::1]:6630"]},
          {"annuaire": "n-0PWT8HZD80QMSPPDZ5CQXXYHQC", "locateurs": ["argon.air-desktop.org:6630"]},
          {"annuaire": "u-0PWT8HZD80QMSPPDZ5CQXXYHQC", "locateurs": ["178.32.16.249:6630"]}
        ]}
        """.utf8)
        let annuaires = ChoixDAnnuaire.lire(json: json, racinesPEM: Self.pem)
        #expect(annuaires.count == 1)
        #expect(annuaires.first?.identites.first?.locateurs == ["178.32.16.250:6630", "[2001:db8::1]:6630"])
    }

    /// Le PEM n'est plus exigé : sans lui, les entrées d'hier n'ont rien à
    /// croire et s'en vont ; les identifiées restent.
    @Test func sansAutoriteSeulesLesEntreesIdentifieesRestent() {
        let json = Data("""
        {"annuaires": [
          {"adresse": "nitrogen.air-desktop.org:6630", "nom": "nitrogen.air-desktop.org"},
          {"annuaire": "n-3K3P6H252W8K9370QG1YYTWBWB", "locateurs": ["178.32.16.249:6630"]}
        ]}
        """.utf8)
        #expect(ChoixDAnnuaire.lire(json: json, racinesPEM: Data()).map(\.nom) == ["argon.air-desktop.org"])
        #expect(ChoixDAnnuaire.lire(json: json, racinesPEM: Self.pem).map(\.parIdentite) == [false, true])
    }

    /// Ce que la ligne de commande reçoit : l'adresse d'hier, sinon
    /// `locateur=n-…`.
    @Test func laLigneDeCommandeVisePartOuLOnSaitJoindre() {
        let annuaires = ChoixDAnnuaire.lire(json: Self.identifie, racinesPEM: Self.pem)
        #expect(annuaires[1].pourLaLigneDeCommande == "nitrogen.air-desktop.org:6630")
        #expect(annuaires[2].pourLaLigneDeCommande == "[2001:41d0:20a:900::1d32]:6630=\(Self.argon)")
    }

    // MARK: - Le choix retenu

    private static let trois = ChoixDAnnuaire.lire(json: Data("""
    {"annuaires": [{"adresse": "n:6630", "nom": "n"}, {"adresse": "a:6630", "nom": "a"}, {"adresse": "r:6630", "nom": "r"}]}
    """.utf8), racinesPEM: pem)

    @Test func parDefautLaPremiereDeLaListe() {
        #expect(Self.preferenceVierge().choisi(parmi: Self.trois)?.nom == "n")
        #expect(Self.preferenceVierge().choisi(parmi: []) == nil)
    }

    @Test func leChoixEstRetenu() {
        let preference = Self.preferenceVierge()
        preference.retenir(Self.trois[1])
        #expect(preference.choisi(parmi: Self.trois)?.nom == "a")
    }

    /// Une racine retirée du fichier ne laisse pas l'application sans
    /// annuaire : on retombe sur la première.
    @Test func uneRacineRetireeDuFichierRetombeSurLaPremiere() {
        let preference = Self.preferenceVierge()
        preference.retenir(Self.trois[2])
        #expect(preference.choisi(parmi: Array(Self.trois.prefix(2)))?.nom == "n")
    }

    // MARK: - La bascule

    /// Garde les bancs fabriqués, pour regarder l'ancien après la bascule.
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

    @MainActor
    @Test func basculerFermeLAncienneRacineEtArreteSonEcouteAvant() async throws {
        let fabrique = Fabrique()
        let preference = Self.preferenceVierge()
        let reelle = Session.reelle(
            annuaires: Self.trois, preference: preference,
            fabrique: { fabrique.fabriquer($0) }, signataire: { CleLogicielle() }
        )
        let session = try #require(reelle)
        #expect(session.annuaireChoisi?.nom == "n")
        try await session.ouvrirCompte()
        let ancien = try #require(fabrique.banc("n"))
        let flux = try #require(await ancien.nouvelles())

        await session.choisirAnnuaire(Self.trois[1])

        // L'écoute de l'ancienne racine est terminée — le flux ne rend plus rien.
        var iterateur = flux.makeAsyncIterator()
        let apres: Void? = await iterateur.next()
        #expect(apres == nil)
        #expect(await ancien.fermetures == 1)
        // La nouvelle sert, et le choix est retenu pour le prochain lancement.
        #expect(session.annuaireChoisi?.nom == "a")
        #expect(session.annuaire as? AnnuaireSimule === fabrique.banc("a"))
        #expect(preference.choisi(parmi: Self.trois)?.nom == "a")
        // Le compte ne bouge pas : il est le même sur toutes les racines.
        #expect(session.compte != nil)
    }

    /// Rechoisir la racine en cours ne ferme rien.
    @MainActor
    @Test func rechoisirLaMemeRacineNeFermeRien() async throws {
        let fabrique = Fabrique()
        let reelle = Session.reelle(
            annuaires: Self.trois, preference: Self.preferenceVierge(),
            fabrique: { fabrique.fabriquer($0) }, signataire: { CleLogicielle() }
        )
        let session = try #require(reelle)
        await session.choisirAnnuaire(Self.trois[0])
        #expect(await fabrique.banc("n")?.fermetures == 0)
    }
}
