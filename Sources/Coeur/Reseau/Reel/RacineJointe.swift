import Foundation

/// Quelle racine a répondu, dite par son nom.
///
/// La connexion ne connaît que l'adresse jointe (`asl_appareil_distante`).
/// Cette adresse est l'un des locateurs d'une racine identifiée, qui dit
/// l'identité trouvée au bout ; c'est **l'identité** qui se nomme
/// (``RacinesConnues``) — jamais un nom DNS. Sous « Automatique », qui
/// couvre les deux racines, c'est donc bien celle qui a répondu qu'on nomme.
enum RacineJointe {
    /// Le nom de la racine dont `adresse` est un locateur, d'après son
    /// identité ; `nil` si aucune identité ne la porte.
    static func nommer(_ adresse: String, identites: [AnnuaireReel.RacineIdentifiee]) -> String? {
        identites.first { $0.locateurs.contains(adresse) }.map { RacinesConnues.nom(de: $0.annuaire) }
    }
}

/// La racine que tient la connexion — ce que l'écran dit sous « Connecté
/// à … ». Le nom quand on sait le donner (``RacineJointe/nommer(_:identites:)``),
/// l'adresse toujours.
struct RacineTenue: Equatable, Sendable {
    let adresse: String
    let nom: String?

    var affiche: String { nom ?? adresse }
}
