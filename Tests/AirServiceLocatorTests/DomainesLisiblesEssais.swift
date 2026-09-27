import Foundation
import Testing
@testable import AirServiceLocator

/// Ce que la liste des domaines dit d'une ligne : l'identifiant entier quand
/// il n'y a pas d'alias, et qui sert le domaine, avec ses adresses.
struct DomainesLisiblesEssais {
    private static let id = Identifiant(genre: .domaine, octets: (0..<16).map { _ in UInt8.random(in: 0...255) })
    private static let moi = Identifiant(genre: .utilisateur, octets: (0..<16).map { _ in UInt8.random(in: 0...255) })

    private static func domaine(alias: String?, hebergePar: Domaine.Hebergeur = .racines) -> Domaine {
        Domaine(id: id, proprietaire: moi, alias: alias, hebergePar: hebergePar, droits: [])
    }

    @Test func sansAliasLIdentifiantEntierEtLeDire() {
        #expect(Self.domaine(alias: nil).titreComplet == "\(Self.id.texte) - pas d'alias")
        #expect(Self.domaine(alias: "Maison").titreComplet == "Maison")
    }

    private static let racines = ChoixDAnnuaire.lire(json: Data("""
    {"annuaires": [
      {"libelle": "Automatique", "racines": [
         {"annuaire": "n-0PWT8HZD80QMSPPDZ5CQXXYHQC", "locateurs": ["[2001:41d0:20a:900::1dd4]:6630", "178.32.16.250:6630"]},
         {"annuaire": "n-3K3P6H252W8K9370QG1YYTWBWB", "locateurs": ["[2001:41d0:20a:900::1d32]:6630", "178.32.16.249:6630"]}]},
      {"annuaire": "n-0PWT8HZD80QMSPPDZ5CQXXYHQC", "locateurs": ["[2001:41d0:20a:900::1dd4]:6630", "178.32.16.250:6630"]}
    ]}
    """.utf8), racinesPEM: Data())

    /// Chaque racine une fois, même présente sous « Automatique » et sous
    /// son nom, avec ses adresses.
    @Test func lesRacinesSeDisentAvecLeursAdresses() {
        let hebergement = Hebergement(.racines, racines: Self.racines, locaux: [])
        #expect(hebergement.titre == "Hébergé par : les racines")
        #expect(hebergement.serveurs.map(\.nom) == ["nitrogen.air-desktop.org", "argon.air-desktop.org"])
        #expect(hebergement.serveurs.first?.adresses == ["[2001:41d0:20a:900::1dd4]:6630", "178.32.16.250:6630"])
    }

    /// Un annuaire local : les adresses déclarées de ses membres, et d'aucun
    /// autre annuaire.
    @Test func unAnnuaireLocalSeDitParLesAdressesDeSesMembres() {
        let n = Identifiant(genre: .annuaire, octets: (0..<16).map { _ in UInt8.random(in: 0...255) })
        let second = Identifiant(genre: .annuaire, octets: (0..<16).map { _ in UInt8.random(in: 0...255) })
        let locaux = [
            AnnuaireLocal(membre: n, annuaire: n, etat: .acceptee, adresse: "[2001:db8::1]:6630", expireLe: nil),
            AnnuaireLocal(membre: second, annuaire: n, etat: .acceptee, adresse: "192.0.2.2:6630", expireLe: nil),
            AnnuaireLocal(membre: nil, annuaire: nil, etat: .attendue, adresse: "192.0.2.9:6630", expireLe: nil),
        ]
        let hebergement = Hebergement(.annuaire(n), racines: Self.racines, locaux: locaux)
        #expect(hebergement.serveurs.flatMap(\.adresses) == ["[2001:db8::1]:6630", "192.0.2.2:6630"])
        // Sans rien de connu, aucune adresse inventée.
        #expect(Hebergement(.annuaire(n), racines: Self.racines, locaux: []).serveurs.isEmpty)
    }
}
