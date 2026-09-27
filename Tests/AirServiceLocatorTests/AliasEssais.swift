import Foundation
import Testing
@testable import AirServiceLocator

/// Les alias depuis l'annuaire 0.26.0 : de compte (unique, 3 à 32 octets)
/// et de machine (1 à 253 octets), en UTF-8 NFC, sensibles à la casse — et la
/// requête qui résout un alias de compte.
struct AliasEssais {
    // MARK: - L'alias de compte

    @Test func unAliasDeCompteGardeCasseEtAccents() {
        #expect(NomsEtAlias.aliasDeCompteValide("thierry"))
        #expect(NomsEtAlias.aliasDeCompteValide("Thierry"))
        #expect(NomsEtAlias.aliasDeCompteValide("Amélie"))
        #expect(NomsEtAlias.aliasDeCompteValide("air-desktop-project-dictator"))
    }

    @Test func lesBornesDUnAliasDeCompte() {
        #expect(!NomsEtAlias.aliasDeCompteValide("ab"))                                 // 2 octets
        #expect(NomsEtAlias.aliasDeCompteValide("abc"))
        #expect(NomsEtAlias.aliasDeCompteValide(String(repeating: "a", count: 32)))
        #expect(!NomsEtAlias.aliasDeCompteValide(String(repeating: "a", count: 33)))
        // Les octets comptent, pas les caractères : seize « é » font 32 octets.
        #expect(NomsEtAlias.aliasDeCompteValide(String(repeating: "é", count: 16)))
        #expect(!NomsEtAlias.aliasDeCompteValide(String(repeating: "é", count: 17)))
    }

    /// Il ne doit pas ressembler à un `u-…`.
    @Test func pasDeTiretEnDeuxiemeCaractere() {
        #expect(!NomsEtAlias.aliasDeCompteValide("u-thierry"))
        #expect(NomsEtAlias.aliasDeCompteValide("-thierry"))
        #expect(NomsEtAlias.aliasDeCompteValide("th-ierry"))
    }

    /// NFC : un « é » décomposé compte comme le composé — c'est la forme que
    /// l'annuaire range et compare.
    @Test func laFormeNFCFaitFoi() {
        let decompose = "Ame\u{0301}lie"
        #expect(NomsEtAlias.nfc(decompose) == "Amélie")
        #expect(NomsEtAlias.nfc(decompose).utf8.count == 7)
        // 16 « é » décomposés : 48 octets saisis, 32 une fois en NFC.
        #expect(NomsEtAlias.aliasDeCompteValide(String(repeating: "e\u{0301}", count: 16)))
    }

    @Test func lesCaracteresRefuses() {
        for refuse in ["a\"bc", "a\\bc", "ab\u{0000}c", "ab\u{007F}", "é\u{0085}x", "a\u{202E}bc", "\u{2066}abc", "\u{FEFF}abc"] {
            #expect(!NomsEtAlias.aliasDeCompteValide(refuse), "« \(refuse.debugDescription) »")
        }
    }

    // MARK: - L'alias de machine

    @Test func lesBornesDUnAliasDeMachine() {
        #expect(NomsEtAlias.aliasDeMachineValide("S"))
        #expect(NomsEtAlias.aliasDeMachineValide("Salle à manger — le NAS 🏠"))
        #expect(NomsEtAlias.aliasDeMachineValide("grenier.maison.example.org"))
        #expect(NomsEtAlias.aliasDeMachineValide(String(repeating: "a", count: 253)))
        #expect(!NomsEtAlias.aliasDeMachineValide(String(repeating: "a", count: 254)))
        #expect(!NomsEtAlias.aliasDeMachineValide(""))
        #expect(!NomsEtAlias.aliasDeMachineValide("a\u{0000}"))
    }

    // MARK: - Résoudre un alias de compte

    /// Un alias ASCII garde le chemin d'avant 0.26.0, que les deux versions
    /// servent ; un alias UTF-8 passe par `?alias=`, pourcent-encodé, en NFC.
    @Test func laRequeteDeResolution() {
        #expect(NomsEtAlias.cheminDeResolution("thierry") == "/v1/alias/thierry")
        #expect(NomsEtAlias.cheminDeResolution("Thierry") == "/v1/alias/Thierry")
        #expect(NomsEtAlias.cheminDeResolution("Amélie") == "/v1/alias?alias=Am%C3%A9lie")
        // Décomposé à la saisie, composé sur le fil.
        #expect(NomsEtAlias.cheminDeResolution("Ame\u{0301}lie") == "/v1/alias?alias=Am%C3%A9lie")
        #expect(NomsEtAlias.cheminDeResolution("le salon") == "/v1/alias?alias=le%20salon")
        #expect(NomsEtAlias.cheminDeResolution("a/b") == "/v1/alias?alias=a%2Fb")
    }

    @Test func lEncodageNeLaissePasserQueLesNonReserves() {
        #expect(NomsEtAlias.pourcentEncode("a-b_c.d~e") == "a-b_c.d~e")
        #expect(NomsEtAlias.pourcentEncode("a+b&c=d") == "a%2Bb%26c%3Dd")
        #expect(NomsEtAlias.pourcentEncode("🏠") == "%F0%9F%8F%A0")
    }

    // MARK: - La version qui les sert

    @Test func lAliasDeMachineAttendLaVersion026() {
        #expect(!VersionAnnuaire(version: "0.25.0", posture: nil).porteLesAliasDeMachine)
        #expect(VersionAnnuaire(version: "0.26.0", posture: nil).porteLesAliasDeMachine)
        #expect(VersionAnnuaire(version: "0.27.3", posture: nil).porteLesAliasDeMachine)
        #expect(VersionAnnuaire(version: "1.0.0", posture: nil).porteLesAliasDeMachine)
        #expect(!VersionAnnuaire(version: "banc en mémoire", posture: nil).porteLesAliasDeMachine)
    }

    // MARK: - Le banc suit l'annuaire

    @Test func leBancRangeEtRetireLAliasDUneMachine() async throws {
        let annuaire = AnnuaireSimule()
        _ = try await annuaire.ouvrirCompte(avec: CleLogicielle(), invitation: nil)
        let machine = try await annuaire.declarerMachine(nom: "Grenier", capacites: [])
        #expect(machine.nom == "grenier")
        try await annuaire.definirAliasDeMachine(machine.id, alias: "Le grenier de Ve\u{0301}ro")
        #expect(try await annuaire.machines().first?.alias == "Le grenier de Véro")
        #expect(try await annuaire.machines().first?.titre == "Le grenier de Véro")
        #expect(try await annuaire.machines().first?.sousTitre == "grenier")
        try await annuaire.definirAliasDeMachine(machine.id, alias: nil)
        #expect(try await annuaire.machines().first?.alias == nil)
        await #expect(throws: ErreurAnnuaire.requeteInvalide("nom")) {
            _ = try await annuaire.declarerMachine(nom: "Salle à manger", capacites: [])
        }
    }
}
