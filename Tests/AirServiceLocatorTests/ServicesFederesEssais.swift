import Foundation
import Testing
@testable import AirServiceLocator

/// Les services des machines d'autres comptes rangées dans un domaine
/// (annuaire ≥ 0.40.0, décisions 100 à 104) : `voir` les donne sans
/// adresses, et l'écran ne montre pas de sections vides.
struct ServicesFederesEssais {
    /// `voir` sans `localiser` : un service vivant à `"annonce":{}`.
    @Test func annonceVideSeLitSansDetail() throws {
        let corps = Data("""
        [{"service":"s-6AQ1BCA8SY1GVVMR0JMWXCA0AQ","nom":"asl-echo","etat":"annonce","annonce":{}},
         {"service":"s-17PNPAMTAGY9160FRMAJ6DR77K","nom":"essai-renvoi","etat":"parti","volontaire":true}]
        """.utf8)
        let services = AnnuaireReel.lireServices(corps)
        #expect(services.count == 2)
        let vivant = try #require(services.first)
        #expect(vivant.sansDetail)
        guard case .annonce = vivant.etat else { Issue.record("vivant attendu"); return }
        #expect(vivant.points.isEmpty && vivant.candidats.isEmpty && vivant.diagnostic == nil)
        #expect(vivant.libelleEtat == "Annoncé")
        #expect(vivant.detailEtat == TextesDomaines.sansDetail)
        #expect(!services[1].sansDetail)
    }

    /// Avec `localiser`, l'annonce est entière : rien ne change.
    @Test func annonceEntiereGardeSonDetail() throws {
        let corps = Data("""
        [{"service":"s-6AQ1BCA8SY1GVVMR0JMWXCA0AQ","nom":"asl-echo","etat":"annonce",
          "annonce":{"joignabilite":[{"protocole":"tcp","port":8080,"verdict":"non_sonde"}]}}]
        """.utf8)
        let service = try #require(AnnuaireReel.lireServices(corps).first)
        #expect(!service.sansDetail)
        #expect(service.pointsTexte == "tcp 8080")
    }

    private static let moi = try! Identifiant.analyser("u-5884A5EE7THEKHBQ3BT0VPGJKN", genre: .utilisateur)
    private static let autre = try! Identifiant.analyser("u-0Z971MJ6TZRWXE8C5CE8VBD2AY", genre: .utilisateur)
    private static let maMachine = try! Identifiant.analyser("m-26W610F86BVRH6GPKGSSQK9H4S", genre: .machine)
    private static let saMachine = try! Identifiant.analyser("m-5N5A5Z42DJRZSB6G3HF9PH99AD", genre: .machine)

    private static func domaine(proprietaire: Identifiant, droits: [String]) throws -> Domaine {
        Domaine(id: try Identifiant.analyser("d-4M7FFS0Q7WMYSYF1EZ032XDEVD", genre: .domaine), proprietaire: proprietaire,
                alias: "maison", hebergePar: .racines, droits: droits,
                machines: [Domaine.MachineRangee(id: maMachine, proprietaire: moi, nom: "oxygen", alias: nil),
                           Domaine.MachineRangee(id: saMachine, proprietaire: autre, nom: "argon", alias: nil)])
    }

    /// Une machine lue a sa clé — même vide ; une machine qu'on ne lit pas
    /// n'en a pas : « on n'en sait rien », pas « aucun service ».
    @Test func lesServicesDesAutresSeLisentAvecVoir() async throws {
        let banc = AnnuaireSimule()
        let sansDroit = try Self.domaine(proprietaire: Self.moi, droits: ["rattacher"])
        #expect(await ServicesDuDomaine.charger(sansDroit, moi: Self.moi, aussiLesMiennes: false, annuaire: banc).isEmpty)
        let avecVoir = try Self.domaine(proprietaire: Self.moi, droits: ["voir"])
        #expect(Set(await ServicesDuDomaine.charger(avecVoir, moi: Self.moi, aussiLesMiennes: false, annuaire: banc).keys) == [Self.saMachine])
        let avecLocaliser = try Self.domaine(proprietaire: Self.moi, droits: ["localiser"])
        #expect(Set(await ServicesDuDomaine.charger(avecLocaliser, moi: Self.moi, aussiLesMiennes: true, annuaire: banc).keys) == [Self.maMachine, Self.saMachine])
        #expect(Set(await ServicesDuDomaine.charger(sansDroit, moi: Self.moi, aussiLesMiennes: true, annuaire: banc).keys) == [Self.maMachine])
    }

    @Test func rangerChezUnAutreSeDitAvant() throws {
        #expect(try Self.domaine(proprietaire: Self.autre, droits: ["rattacher"]).appartientAUnAutre(que: Self.moi))
        #expect(!(try Self.domaine(proprietaire: Self.moi, droits: ["rattacher"]).appartientAUnAutre(que: Self.moi)))
        #expect(TextesDomaines.ceQueLeRangementOuvre == "Qui voit ce domaine verra les services de cette machine ; qui y localise les joindra.")
    }
}
