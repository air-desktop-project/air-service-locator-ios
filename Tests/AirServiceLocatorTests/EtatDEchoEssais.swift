import Foundation
import Testing
@testable import AirServiceLocator

/// L'état d'écho d'une machine (annuaire ≥ 0.43.0) : lu par clés, absent
/// quand aucun `asl-echo` n'est annoncé, un mot inconnu dit tel quel.
struct EtatDEchoEssais {
    private static func objet(_ json: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func verifieDuDehors() throws {
        let echo = try #require(EtatDEcho.lire(try Self.objet("""
        {"machine":"m-6CGATDSJEPMAH7VPDJ5WA8HTBD","echo":"verifie","echo_a":1790545643327,
         "echo_par":"n-0PWT8HZD80QMSPPDZ5CQXXYHQC","echo_depuis":"exterieur","echo_via":"upnp"}
        """)))
        #expect(echo.verdict == .verifie)
        #expect(echo.depuis == .exterieur)
        #expect(echo.a == Date(timeIntervalSince1970: 1_790_545_643.327))
        #expect(echo.par?.texte == "n-0PWT8HZD80QMSPPDZ5CQXXYHQC")
        #expect(echo.libelle == "Écho vérifié, du dehors")
        #expect(echo.detail.hasPrefix("par la redirection que la box a accordée (UPnP), constaté "))
        #expect(echo.detail.hasSuffix(", par l'annuaire n-0PWT…YHQC"))
    }

    /// De l'intérieur : vérifié, mais on dit ce que cela ne prouve pas.
    @Test func verifieDeLInterieur() throws {
        let echo = try #require(EtatDEcho.lire(try Self.objet(#"{"echo":"verifie","echo_depuis":"interieur"}"#)))
        #expect(echo.libelle == "Écho vérifié, de l'intérieur")
        #expect(echo.detail == TextesEcho.interieur)
    }

    @Test func lesAutresVerdicts() throws {
        #expect(EtatDEcho.lire(try Self.objet(#"{"echo":"injoignable"}"#))?.libelle == "Écho injoignable")
        let autre = try #require(EtatDEcho.lire(try Self.objet(#"{"echo":"autre_cle","echo_via":"nat"}"#)))
        #expect(autre.verdict == .autreCle)
        // `echo_via` n'accompagne que `verifie` : sur une autre clé, il ne se dit pas.
        #expect(autre.detail == TextesEcho.autreCle)
        #expect(EtatDEcho.lire(try Self.objet(#"{"echo":"en_cours"}"#))?.libelle == "Écho en cours de vérification")
        #expect(EtatDEcho.lire(try Self.objet(#"{"echo":"prouve_pcp"}"#))?.libelle == "Écho : prouve_pcp")
    }

    /// Aucun `asl-echo` annoncé : pas d'état — ni échec, ni succès.
    @Test func absentPasDEcho() throws {
        #expect(EtatDEcho.lire(try Self.objet(#"{"machine":"m-6CGATDSJEPMAH7VPDJ5WA8HTBD","nom":"helium"}"#)) == nil)
    }

    /// Le détail d'un domaine porte l'état de chaque machine rangée.
    @Test func leDomaineLePorte() throws {
        let domaine = try #require(ReponsesDomaines.detail(Data("""
        {"domaine":"d-4M7FFS0Q7WMYSYF1EZ032XDEVD","proprietaire":"u-5884A5EE7THEKHBQ3BT0VPGJKN","droits":["voir"],
         "heberge_par":"racines",
         "machines":[{"machine":"m-6CGATDSJEPMAH7VPDJ5WA8HTBD","proprietaire":"u-5884A5EE7THEKHBQ3BT0VPGJKN","nom":"helium",
                      "echo":"verifie","echo_depuis":"exterieur"},
                     {"machine":"m-32Q2JXER1HTVRZQ956T7V3GE0S","proprietaire":"u-5884A5EE7THEKHBQ3BT0VPGJKN","nom":"speedy"}]}
        """.utf8)))
        #expect(domaine.machines.map { $0.echo?.verdict } == [.verifie, nil])
    }
}
