import Foundation

/// La version de cette application, telle que `project.yml` la fixe
/// (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`) et que le paquet la
/// porte. Elle se lit à l'écran : c'est ce qu'un utilisateur cite quand il
/// rapporte quelque chose, et ce qui dit si deux appareils font tourner le
/// même code. Chaque PR la change — la règle est dans `CLAUDE.md`.
enum Version {
    /// `0.2.0` — semver, ce que l'utilisateur lit.
    static var semver: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// Le numéro de build, entier croissant.
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// `0.2.0 (2)` — la forme affichée.
    static var texte: String { "\(semver) (\(build))" }
}
