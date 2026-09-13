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
    ///
    /// # Ce que l'annuaire dit, et ce que cet appareil sait en plus
    ///
    /// L'annuaire rend deux états — `attendue`, `enrolee` — et rien d'autre :
    /// il ne range ni horodatage, ni le code en cours (gardé par son empreinte
    /// seulement), ni la trace d'une révocation. Le code n'est donc connu que
    /// du téléphone qui l'a fait émettre ; la date d'enrôlement, la
    /// révocation, de celui qui a agi. D'où les optionnels : `nil` veut dire
    /// « cet appareil ne le sait pas », jamais « ça n'a pas eu lieu ».
    enum Cle: Hashable, Sendable {
        /// Déclarée, pas encore enrôlée : la clé n'existe pas encore. Elle sera
        /// générée SUR la machine, et sa partie privée n'en sortira jamais. Le
        /// code est celui émis d'ici, s'il y en a un.
        case attendue(code: CodeEnrolement?)
        case enrolee(le: Date?)
        /// Révoquée depuis l'application : connexions fermées, baux tombés. La
        /// machine reste — nom, capacités, services — et attend un nouveau code.
        /// L'annuaire ne distingue pas une clé révoquée d'une clé jamais posée ;
        /// seul l'appareil qui a révoqué le sait, et depuis quand.
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
