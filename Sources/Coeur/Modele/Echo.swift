import Foundation

/// L'état d'écho d'une machine (`protocole.md`, « L'état par machine »,
/// annuaire ≥ 0.43.0, décisions 91 à 97) : ce que la dernière sonde de
/// l'annuaire a prouvé de la machine elle-même — que sa clé répond, et d'où.
///
/// **Absent** (`nil` sur la machine) : aucun `asl-echo` n'est annoncé. Ce
/// n'est ni un échec ni un succès, et l'écran le dit comme tel.
///
/// **Pas d'adresse, pas de port** : l'état dit qu'on a prouvé, pas où.
/// L'adresse reste derrière `localiser`. Le propriétaire le lit dans
/// `GET /v1/machines` ; qui a `voir` sur le domaine, dans
/// `GET /v1/domaines/{d}`.
struct EtatDEcho: Hashable, Sendable {
    enum Verdict: Hashable, Sendable {
        /// Une réponse est venue, signée par la clé de la machine.
        case verifie
        /// Rien n'est venu, ou rien de bien formé.
        case injoignable
        /// Une réponse bien formée, signée par une AUTRE clé : le cas que
        /// l'écho est fait pour voir.
        case autreCle
        /// Pas encore sondé.
        case enCours
        /// Un mot que cette version ne connaît pas : dit tel quel.
        case inconnu(String)

        init(_ texte: String) {
            switch texte {
            case "verifie": self = .verifie
            case "injoignable": self = .injoignable
            case "autre_cle": self = .autreCle
            case "en_cours": self = .enCours
            default: self = .inconnu(texte)
            }
        }
    }

    /// D'où l'annuaire a sondé — la règle de `sonde_locale` (décision 60).
    enum Depuis: Hashable, Sendable {
        /// Du dehors : la preuve dit qu'on joint la machine depuis l'Internet.
        case exterieur
        /// De la machine même, ou de son réseau : la clé est là, et c'est
        /// tout ce que cela dit.
        case interieur
        case inconnu(String)

        init(_ texte: String) {
            switch texte {
            case "exterieur": self = .exterieur
            case "interieur": self = .interieur
            default: self = .inconnu(texte)
            }
        }
    }

    let verdict: Verdict
    /// `echo_a` : l'instant de la mesure ; absent sur `en_cours`.
    var a: Date?
    /// `echo_par` : l'annuaire qui a sondé.
    var par: Identifiant?
    var depuis: Depuis?
    /// `echo_via` (décision 97), avec `verifie` seulement : `upnp`, `nat`,
    /// `direct` — et `pcp`, `natpmp` plus tard. Gardé en texte : un mot
    /// inconnu se dit tel quel.
    var via: String?

    /// Les champs `echo*` d'un objet machine ; `nil` sans `echo`.
    static func lire(_ objet: [String: Any]) -> EtatDEcho? {
        guard let texte = objet["echo"] as? String else { return nil }
        return EtatDEcho(verdict: Verdict(texte),
                         a: (objet["echo_a"] as? Double).map { Date(timeIntervalSince1970: $0 / 1_000) },
                         par: (objet["echo_par"] as? String).flatMap { try? Identifiant.analyser($0, genre: .annuaire) },
                         depuis: (objet["echo_depuis"] as? String).map(Depuis.init),
                         via: objet["echo_via"] as? String)
    }
}
