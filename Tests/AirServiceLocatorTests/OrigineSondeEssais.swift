import Foundation
import Testing
@testable import AirServiceLocator

/// L'origine de la sonde d'un service fédéré (décision 60) : lue quand le
/// serveur la dit, absente sinon — et alors rien ne change.
struct OrigineSondeEssais {
    private static let speedy = "n-7MSV5RPCXBZH25PQM4ZPE5X87P"

    private static func corps(sonde: String) -> Data {
        Data("""
        [{"service":"s-6AQ1BCA8SY1GVVMR0JMWXCA0AQ","nom":"essai-federation","etat":"annonce",
          "annonce":{"service":"s-6AQ1BCA8SY1GVVMR0JMWXCA0AQ","keepalive_secondes":10,"inactivite_secondes":30,
            "vu_depuis":{"adresse":"2a01:cb19:d27:2f00:3ac9:86ff:fe47:9d54","port":33995},"derriere_nat":"non",
            "joignabilite":[{"protocole":"tcp","port":8080,"verdict":"joignable","candidat":"[2a01:cb19:d27:2f00:3ac9:86ff:fe47:9d54]:8080","origine":"reflexif","a":1790545643327}]}\(sonde)},
         {"service":"s-17PNPAMTAGY9160FRMAJ6DR77K","nom":"essai-renvoi","etat":"parti","volontaire":null\(sonde)}]
        """.utf8)
    }

    @Test func lesDeuxChampsSeLisent() throws {
        let services = AnnuaireReel.lireServices(Self.corps(sonde: #","sonde_par":"n-7MSV5RPCXBZH25PQM4ZPE5X87P","sonde_locale":true"#))
        #expect(services.count == 2)
        let federe = try #require(services.first)
        let attendue = Sonde(par: try Identifiant.analyser(Self.speedy, genre: .annuaire), locale: true)
        #expect(federe.sonde == attendue)
        #expect(federe.libelleEtat == "Joignable depuis la machine")
        #expect(federe.detailEtat.hasPrefix("rapporté par l'annuaire n-7MSV…X87P, "))
        #expect(federe.joignableDeLInterieurSeulement)
        #expect(services[1].sonde?.locale == true)
    }

    /// Sondé par l'annuaire local, mais du dehors : « Joignable », rapporté
    /// par lui, sans mise en garde.
    @Test func uneSondeDuDehorsDitJoignable() {
        let services = AnnuaireReel.lireServices(Self.corps(sonde: #","sonde_par":"n-7MSV5RPCXBZH25PQM4ZPE5X87P","sonde_locale":false"#))
        #expect(services.first?.libelleEtat == "Joignable")
        #expect(services.first?.detailEtat.hasPrefix("rapporté par l'annuaire n-7MSV…X87P, ") == true)
        #expect(services.first?.joignableDeLInterieurSeulement == false)
    }

    /// Absents — un service sondé par les racines, ou un serveur d'avant la
    /// décision 60 : comme avant.
    @Test func absentsRienNeChange() {
        let services = AnnuaireReel.lireServices(Self.corps(sonde: ""))
        #expect(services.map(\.sonde) == [nil, nil])
        #expect(services.first?.libelleEtat == "Joignable")
        #expect(services.first?.detailEtat.hasPrefix("depuis l'annuaire, ") == true)
        #expect(services.first?.joignableDeLInterieurSeulement == false)
    }

    /// Un `sonde_par` illisible ne s'invente pas en origine ; une sonde
    /// locale non dite se prend pour une sonde du dehors.
    @Test func unChampDeTraversNeSInventePas() {
        #expect(AnnuaireReel.lireServices(Self.corps(sonde: #","sonde_par":"pas-un-n","sonde_locale":true"#)).first?.sonde == nil)
        #expect(AnnuaireReel.lireServices(Self.corps(sonde: #","sonde_par":"n-7MSV5RPCXBZH25PQM4ZPE5X87P""#)).first?.sonde?.locale == false)
    }
}
