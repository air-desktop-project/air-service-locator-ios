import Testing
@testable import AirServiceLocator

/// Nommer la racine qui a répondu : l'entrée la plus précise qui contient
/// l'adresse jointe — jamais l'alias qui les couvre toutes.
struct RacineJointeEssais {
    private static let racines: [(nom: String, adresses: [String])] = [
        ("asl-root.air-desktop.org", ["[2001:41d0:20a:900::1dd4]:6630", "[2001:41d0:20a:900::1d32]:6630", "178.32.16.250:6630", "178.32.16.249:6630"]),
        ("nitrogen.air-desktop.org", ["[2001:41d0:20a:900::1dd4]:6630", "178.32.16.250:6630"]),
        ("argon.air-desktop.org", ["[2001:41d0:20a:900::1d32]:6630", "178.32.16.249:6630"]),
    ]

    @Test func sousAutomatiqueCEstLaRacineQuiEstNommee() {
        #expect(RacineJointe.nommer("[2001:41d0:20a:900::1dd4]:6630", parmi: Self.racines) == "nitrogen.air-desktop.org")
        #expect(RacineJointe.nommer("178.32.16.249:6630", parmi: Self.racines) == "argon.air-desktop.org")
    }

    /// L'ordre de la liste ne change rien : c'est la précision qui décide.
    @Test func lOrdreDeLaListeNeComptePas() {
        #expect(RacineJointe.nommer("[2001:41d0:20a:900::1d32]:6630", parmi: Self.racines.reversed()) == "argon.air-desktop.org")
    }

    /// Seul l'alias la contient : c'est lui qu'on nomme.
    @Test func fauteDeMieuxLAlias() {
        #expect(RacineJointe.nommer("[2001:db8::1]:6630", parmi: [("asl-root", ["[2001:db8::1]:6630"])]) == "asl-root")
    }

    /// Une adresse que rien ne contient ne se nomme pas : le journal la dit
    /// brute.
    @Test func uneAdresseInconnueNeSeNommePas() {
        #expect(RacineJointe.nommer("192.0.2.7:6630", parmi: Self.racines) == nil)
    }
}
