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
    /// **Un nom d'hôte** depuis l'annuaire 0.26.0 (décision 47) : lettres
    /// ASCII, chiffres et tiret, rangé en minuscules. Un nom rangé avant, en
    /// texte libre, reste tel quel et s'affiche tel quel.
    var nom: String
    var capacites: Set<Capacite>
    var cle: Cle
    var services: [Service]
    /// Texte choisi, libre — un nom complet, des accents, des espaces —,
    /// non unique, indépendant du nom (``NomsEtAlias/aliasDeMachineValide(_:)``).
    /// `nil` tant qu'on n'en a pas posé.
    var alias: String? = nil
    /// L'état d'écho (annuaire ≥ 0.43.0) ; `nil` : aucun `asl-echo` annoncé.
    var echo: EtatDEcho? = nil

    /// Un nouveau nom, ou un renommage, peut-il partir ? Un nom d'hôte
    /// (``NomsEtAlias/nomDHote(_:)``) ; l'annuaire rend `400` pour tout autre.
    static func nomValide(_ nom: String) -> Bool {
        NomsEtAlias.nomDHote(nom) != nil
    }

    /// Ce que l'écran met en titre : l'alias s'il y en a un — c'est le texte
    /// que son propriétaire a choisi pour la reconnaître —, sinon le nom.
    var titre: String { alias ?? nom }
    /// Le nom d'hôte sous le titre, quand l'alias a pris sa place.
    var sousTitre: String? { alias == nil ? nil : nom }

    var capacitesTexte: String {
        Capacite.allCases.filter { capacites.contains($0) }.map(\.libelle).joined(separator: ", ")
    }

    /// Deux daemons du même nom se chassent l'un l'autre : la date d'annonce
    /// oscille, et l'application le signale.
    var unServiceOscille: Bool { services.contains(where: \.oscille) }
}

/// Une machine d'un AUTRE compte, telle qu'une autorisation la donne à voir
/// (`docs/protocole.md` §2.2, `GET /v1/utilisateurs/{u}/machines`) : son
/// identifiant et son nom — rien d'autre, ni capacités, ni clé, ni code, qui
/// n'appartiennent qu'au propriétaire.
struct MachineVisible: Identifiable, Hashable, Sendable {
    let id: Identifiant
    let nom: String
    var alias: String? = nil

    var titre: String { alias ?? nom }
}
