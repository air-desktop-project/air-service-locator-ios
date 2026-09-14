import Foundation
import Testing
@testable import AirServiceLocator

/// La grammaire des identifiants, telle que `asl-id` l'arrête côté serveur.
struct IdentifiantEssais {
    @Test func unTexteCanoniqueSeRelitTelQuel() throws {
        let octets: [UInt8] = (0..<16).map { UInt8($0 * 17) }
        let identifiant = Identifiant(genre: .machine, octets: octets)
        let texte = identifiant.texte
        #expect(texte.count == 28)
        #expect(texte.hasPrefix("m-"))
        #expect(try Identifiant.analyser(texte) == identifiant)
    }

    @Test func lesConfusionsDeCrockfordSontRattrapees() throws {
        let identifiant = Identifiant(genre: .utilisateur, octets: [UInt8](repeating: 0x01, count: 16))
        var texte = identifiant.texte
        // Le corps porte des `1` et des `0` : on les écrit avec les lettres
        // que l'œil confond, en minuscules, et on doit retomber sur les mêmes
        // octets.
        texte = texte.replacingOccurrences(of: "1", with: "l").replacingOccurrences(of: "0", with: "O").lowercased()
        #expect(try Identifiant.analyser(texte) == identifiant)
    }

    @Test func leGenreEstVerifieALaLecture() {
        let texte = Identifiant(genre: .machine, octets: [UInt8](repeating: 0, count: 16)).texte
        #expect(throws: Identifiant.Erreur.genreInattendu(attendu: .utilisateur, obtenu: .machine)) {
            try Identifiant.analyser(texte, genre: .utilisateur)
        }
    }

    @Test func ceQuiNestPasUnIdentifiantEstRefuse() {
        #expect(throws: Identifiant.Erreur.longueur(attendue: 28, obtenue: 3)) { try Identifiant.analyser("u-1") }
        #expect(throws: Identifiant.Erreur.prefixeInconnu) { try Identifiant.analyser("x-00000000000000000000000000") }
        #expect(throws: Identifiant.Erreur.separateurAbsent) { try Identifiant.analyser("u_00000000000000000000000000") }
        #expect(throws: Identifiant.Erreur.symboleInvalide(position: 3)) { try Identifiant.analyser("u-000U0000000000000000000000") }
        // Un premier symbole ≥ 8 : 130 bits ne tiennent pas dans 128.
        #expect(throws: Identifiant.Erreur.debordement) { try Identifiant.analyser("u-80000000000000000000000000") }
    }

    @Test func deuxTextesDifferentsPeuventDesignerLeMemeIdentifiant() throws {
        let a = try Identifiant.analyser("u-0123456789ABCDEFGHJKMNPQRS")
        let b = try Identifiant.analyser("u-0i23456789abcdefghjkmnpqrs")
        #expect(a == b)
        #expect(a.texte == "u-0123456789ABCDEFGHJKMNPQRS")
    }
}

struct CodeEnrolementEssais {
    @Test func dixSymbolesGroupesParCinq() {
        let code = CodeEnrolement(entropie: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF], emisLe: .distantPast)
        #expect(code.symboles == "ZZZZZZZZZZ")
        #expect(code.texteGroupe == "ZZZZZ-ZZZZZ")
        #expect(code.commande == "asl enrole ZZZZZ-ZZZZZ")
    }

    @Test func laMemeEntropieQueLeServeur() {
        // `asl_cle::CodeEnrolement::depuis_entropie` : `u64::from_be_bytes >> 14`,
        // puis cinq bits par symbole, de droite à gauche.
        let code = CodeEnrolement(entropie: [0, 0, 0, 0, 0, 0, 0x40, 0x00], emisLe: .distantPast)
        #expect(code.symboles == "0000000001")
    }

    @Test func dixMinutesEtPasUneDePlus() {
        let emis = Date(timeIntervalSince1970: 1_000_000)
        let code = CodeEnrolement(entropie: [UInt8](repeating: 0, count: 8), emisLe: emis)
        #expect(code.estValide(a: emis.addingTimeInterval(599)))
        #expect(!code.estValide(a: emis.addingTimeInterval(600)))
        #expect(code.reste(a: emis.addingTimeInterval(700)) == 0)
    }
}

struct NomDeMachineEssais {
    @Test func toutLutf8SaufCeQuiRetourneSesVoisins() {
        #expect(Machine.nomValide("grenier"))
        #expect(Machine.nomValide("serveur été 🏠"))
        #expect(!Machine.nomValide(""))
        #expect(!Machine.nomValide(String(repeating: "é", count: 33)))  // 66 octets
        #expect(!Machine.nomValide("a\"b"))
        #expect(!Machine.nomValide("a\\b"))
        #expect(!Machine.nomValide("a\tb"))
        #expect(!Machine.nomValide("a\u{202E}b"))
        #expect(!Machine.nomValide("\u{FEFF}a"))
    }
}
