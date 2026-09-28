import Testing
@testable import AirServiceLocator

/// Nommer la racine qui a répondu : le locateur joint dit l'identité, et
/// l'identité se nomme — jamais un nom DNS.
struct RacineJointeEssais {
    // MARK: - Par l'identité

    private static let identites = [
        AnnuaireReel.RacineIdentifiee(annuaire: "n-0PWT8HZD80QMSPPDZ5CQXXYHQC", locateurs: ["[2001:41d0:20a:900::1dd4]:6630", "178.32.16.250:6630"]),
        AnnuaireReel.RacineIdentifiee(annuaire: "n-3K3P6H252W8K9370QG1YYTWBWB", locateurs: ["[2001:41d0:20a:900::1d32]:6630", "178.32.16.249:6630"]),
    ]

    /// Le locateur joint dit l'identité, et l'identité se nomme — sans DNS.
    @Test func leLocateurJointSeNommeParSonIdentite() {
        #expect(RacineJointe.nommer("178.32.16.250:6630", identites: Self.identites) == "nitrogen.air-desktop.org")
        #expect(RacineJointe.nommer("[2001:41d0:20a:900::1d32]:6630", identites: Self.identites) == "argon.air-desktop.org")
        #expect(RacineJointe.nommer("192.0.2.7:6630", identites: Self.identites) == nil)
    }

    /// Une identité que la liste embarquée ne connaît pas se dit abrégée.
    @Test func uneIdentiteInconnueSeDitAbregee() throws {
        let inconnue = "n-7ZZZZZZZZZZZZZZZZZZZZZZZZZ"
        let attendu = try Identifiant.analyser(inconnue, genre: .annuaire).abrege
        #expect(RacineJointe.nommer("192.0.2.7:6630", identites: [.init(annuaire: inconnue, locateurs: ["192.0.2.7:6630"])]) == attendu)
    }
}
