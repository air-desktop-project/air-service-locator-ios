import Foundation

/// Ce qu'une machine a le droit de faire. **Rien n'est coché d'avance** : une
/// machine qui porte les deux a un rayon de dégât plus large qu'une machine qui
/// n'en porte qu'une (`docs/modele.md` §2.3).
enum Capacite: String, CaseIterable, Hashable, Sendable {
    /// Ses daemons peuvent annoncer et rafraîchir des services.
    case annonce
    /// Elle peut demander où joindre un service — les siens, et ceux accordés.
    case lecture

    var libelle: String {
        switch self {
        case .annonce: "annonce"
        case .lecture: "lecture"
        }
    }
}

/// Une machine déclarée depuis l'application — celle qui sert un service comme
/// celle qui le consomme.
struct Machine: Identifiable, Hashable, Sendable {
    /// Ce que l'annuaire sait de la clé Ed25519 de la machine.
    enum Cle: Hashable, Sendable {
        /// Déclarée, pas encore enrôlée : la clé n'existe pas encore. Elle sera
        /// générée SUR la machine, et sa partie privée n'en sortira jamais.
        case attendue(code: CodeEnrolement)
        case enrolee(le: Date)
        /// Révoquée depuis l'application : connexions fermées, baux tombés. La
        /// machine reste — nom, capacités, services — et attend un nouveau code.
        case revoquee(le: Date, code: CodeEnrolement?)
    }

    let id: Identifiant
    /// Libre, pour l'humain. 1 à 64 octets, tout l'UTF-8 sauf `"`, `\` et les
    /// contrôles.
    var nom: String
    var capacites: Set<Capacite>
    var cle: Cle
    var services: [Service]

    /// Le nom respecte-t-il les règles de `docs/modele.md` §2.3 ?
    static func nomValide(_ nom: String) -> Bool {
        let octets = nom.utf8.count
        guard octets >= 1, octets <= 64 else { return false }
        return !nom.unicodeScalars.contains { scalaire in
            scalaire == "\"" || scalaire == "\\"
                || scalaire.value < 0x20 || scalaire.value == 0x7F      // C0 et DEL
                || (0x80...0x9F).contains(scalaire.value)               // C1
                || scalaire.value == 0xFEFF                             // marque d'ordre
                || (0x202A...0x202E).contains(scalaire.value)           // forceurs de sens
                || (0x2066...0x2069).contains(scalaire.value)
        }
    }

    var capacitesTexte: String {
        Capacite.allCases.filter { capacites.contains($0) }.map(\.libelle).joined(separator: ", ")
    }

    /// Deux daemons du même nom se chassent l'un l'autre : la date d'annonce
    /// oscille, et l'application le signale.
    var unServiceOscille: Bool { services.contains(where: \.oscille) }
}
