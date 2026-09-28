import Foundation
import Testing
@testable import AirServiceLocator

/// Choisir sa racine : le fichier qui les décrit — par leur identité, et
/// rien d'autre —, le choix retenu, et la bascule — l'ancienne racine fermée,
/// son écoute arrêtée, avant que la nouvelle serve.
struct ChoixDAnnuaireEssais {
    private static func preferenceVierge() -> PreferenceDAnnuaire {
        PreferenceDAnnuaire(defauts: UserDefaults(suiteName: "essais.annuaire.\(UUID().uuidString)")!)
    }

    private static let nitrogen = "n-0PWT8HZD80QMSPPDZ5CQXXYHQC"
    private static let argon = "n-3K3P6H252W8K9370QG1YYTWBWB"

    // MARK: - Le fichier

    private static let identifie = Data("""
    {"annuaires": [
      {"libelle": "Automatique", "racines": [
         {"annuaire": "n-0PWT8HZD80QMSPPDZ5CQXXYHQC", "locateurs": ["[2001:41d0:20a:900::1dd4]:6630", "178.32.16.250:6630"]},
         {"annuaire": "n-3K3P6H252W8K9370QG1YYTWBWB", "locateurs": ["[2001:41d0:20a:900::1d32]:6630", "178.32.16.249:6630"]}]},
      {"annuaire": "n-0PWT8HZD80QMSPPDZ5CQXXYHQC", "locateurs": ["[2001:41d0:20a:900::1dd4]:6630", "178.32.16.250:6630"]},
      {"annuaire": "n-3K3P6H252W8K9370QG1YYTWBWB", "locateurs": ["[2001:41d0:20a:900::1d32]:6630", "178.32.16.249:6630"]}
    ]}
    """.utf8)

    /// Les deux écritures d'une entrée, dans l'ordre du fichier, nommées par
    /// la liste embarquée.
    @Test func laListeSeLitSousSesDeuxEcritures() {
        let annuaires = ChoixDAnnuaire.lire(json: Self.identifie)
        #expect(annuaires.map(\.affiche) == ["Automatique", "nitrogen.air-desktop.org", "argon.air-desktop.org"])
        #expect(annuaires[0].identites.map(\.annuaire) == [Self.nitrogen, Self.argon])
        let attendue = AnnuaireReel.RacineIdentifiee(annuaire: Self.nitrogen, locateurs: ["[2001:41d0:20a:900::1dd4]:6630", "178.32.16.250:6630"])
        #expect(annuaires[1].identites == [attendue])
        #expect(annuaires.map(\.cle) == ["\(Self.nitrogen),\(Self.argon)", Self.nitrogen, Self.argon])
    }

    /// La forme d'hier n'est plus lue : une entrée sans identité est laissée
    /// de côté, l'objet seul d'hier ne donne rien.
    @Test func uneEntreeSansIdentiteEstLaisseeDeCote() {
        let json = Data("""
        {"annuaires": [
          {"adresse": "nitrogen.air-desktop.org:6630", "nom": "nitrogen.air-desktop.org"},
          {"annuaire": "n-3K3P6H252W8K9370QG1YYTWBWB", "locateurs": ["178.32.16.249:6630"]}
        ]}
        """.utf8)
        #expect(ChoixDAnnuaire.lire(json: json).map(\.nom) == ["argon.air-desktop.org"])
        #expect(ChoixDAnnuaire.lire(json: Data(#"{"adresse": "nitrogen.air-desktop.org:6630", "nom": "nitrogen.air-desktop.org"}"#.utf8)).isEmpty)
    }

    /// Un fichier sans rien d'identifié se dit : pas de repli, ni DNS ni banc.
    @Test func sansRacineIdentifieeLePaquetEstInutilisable() throws {
        let fichier = FileManager.default.temporaryDirectory.appending(path: "annuaire-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fichier) }
        #expect(ChoixDAnnuaire.depuis(nil) == .absent)
        #expect(ChoixDAnnuaire.depuis(fichier) == .absent)
        try Data(#"{"annuaires": [{"adresse": "nitrogen.air-desktop.org:6630", "nom": "nitrogen.air-desktop.org"}]}"#.utf8).write(to: fichier)
        #expect(ChoixDAnnuaire.depuis(fichier) == .inutilisable(TextesRacine.aucuneIdentifiee))
        try Self.identifie.write(to: fichier)
        #expect(ChoixDAnnuaire.depuis(fichier) == .annuaires(ChoixDAnnuaire.lire(json: Self.identifie)))
    }

    /// Aucun nom ne se résout : un locateur qui n'est pas littéral se laisse
    /// de côté, et une racine qui n'en garde aucun aussi — comme un `n-…` de
    /// travers.
    @Test func unLocateurQuiNEstPasLitteralSeLaisseDeCote() {
        let json = Data("""
        {"annuaires": [
          {"annuaire": "n-0PWT8HZD80QMSPPDZ5CQXXYHQC", "locateurs": ["nitrogen.air-desktop.org:6630", "178.32.16.250:6630", "[::1]", "[2001:db8::1]:6630"]},
          {"annuaire": "n-3K3P6H252W8K9370QG1YYTWBWB", "locateurs": ["argon.air-desktop.org:6630"]},
          {"annuaire": "u-0PWT8HZD80QMSPPDZ5CQXXYHQC", "locateurs": ["178.32.16.249:6630"]}
        ]}
        """.utf8)
        let annuaires = ChoixDAnnuaire.lire(json: json)
        #expect(annuaires.count == 1)
        #expect(annuaires.first?.identites.first?.locateurs == ["178.32.16.250:6630", "[2001:db8::1]:6630"])
    }

    @Test func unFichierIllisibleNeDonneRienEtUneEntreeDoubleNeCompteQuUneFois() {
        #expect(ChoixDAnnuaire.lire(json: Data("pas du json".utf8)).isEmpty)
        let double = Data(#"{"annuaires": [{"nom": "a", "annuaire": "n-0PWT8HZD80QMSPPDZ5CQXXYHQC", "locateurs": ["192.0.2.1:1"]}, {"nom": "b", "annuaire": "n-0PWT8HZD80QMSPPDZ5CQXXYHQC", "locateurs": ["192.0.2.2:1"]}]}"#.utf8)
        #expect(ChoixDAnnuaire.lire(json: double).map(\.nom) == ["a"])
    }

    /// Ce que la ligne de commande reçoit : `locateur=n-…`.
    @Test func laLigneDeCommandeVisePartOuLOnSaitJoindre() {
        let annuaires = ChoixDAnnuaire.lire(json: Self.identifie)
        #expect(annuaires[2].pourLaLigneDeCommande == "[2001:41d0:20a:900::1d32]:6630=\(Self.argon)")
    }

    // MARK: - Le choix retenu

    private static let trois = ChoixDAnnuaire.lire(json: Data("""
    {"annuaires": [
      {"nom": "n", "adresse": "nitrogen.air-desktop.org:6630", "annuaire": "n-0PWT8HZD80QMSPPDZ5CQXXYHQC", "locateurs": ["192.0.2.1:6630"]},
      {"nom": "a", "annuaire": "n-3K3P6H252W8K9370QG1YYTWBWB", "locateurs": ["192.0.2.2:6630"]},
      {"nom": "r", "annuaire": "n-7MSV5RPCXBZH25PQM4ZPE5X87P", "locateurs": ["192.0.2.3:6630"]}
    ]}
    """.utf8))

    /// Une préférence retenue avant 0.20.0 l'était par l'adresse d'hier :
    /// elle désigne encore l'entrée qui la porte.
    @Test func unChoixRetenuParLAdresseDHierTientEncore() {
        let defauts = UserDefaults(suiteName: "essais.annuaire.\(UUID().uuidString)")!
        defauts.set("nitrogen.air-desktop.org:6630", forKey: "annuaire.adresse")
        let preference = PreferenceDAnnuaire(defauts: defauts)
        #expect(preference.choisi(parmi: Array(Self.trois.reversed()))?.nom == "n")
    }

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
