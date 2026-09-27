import Foundation

/// Quelle racine a répondu, dite par son nom.
///
/// La connexion ne connaît que l'adresse jointe (`asl_appareil_distante`).
/// Chaque entrée de la liste (``ChoixDAnnuaire``) se résout en ses adresses ;
/// la racine jointe est **l'entrée la plus précise qui la contient** : un
/// alias qui couvre les deux racines — « Automatique » — contient toutes les
/// adresses, et le dire ne renseignerait rien. nitrogen, qui n'a que les
/// siennes, est la réponse.
///
/// Une entrée identifiée ne se résout pas : l'adresse jointe est l'un de ses
/// locateurs, qui dit l'identité trouvée au bout, et c'est **l'identité**
/// qui se nomme (``RacinesConnues``) — pas un nom DNS.
enum RacineJointe {
    /// Le nom de la racine dont `adresse` est un locateur, d'après son
    /// identité ; `nil` si aucune identité ne la porte.
    static func nommer(_ adresse: String, identites: [AnnuaireReel.RacineIdentifiee]) -> String? {
        identites.first { $0.locateurs.contains(adresse) }.map { RacinesConnues.nom(de: $0.annuaire) }
    }

    static func nommer(_ adresse: String, parmi racines: [(nom: String, adresses: [String])]) -> String? {
        racines
            .filter { $0.adresses.contains(adresse) }
            .min { $0.adresses.count < $1.adresses.count }?
            .nom
    }
}

/// La racine que tient la connexion — ce que l'écran dit sous « Connecté
/// à … ». Le nom quand on sait le donner (``RacineJointe/nommer(_:parmi:)``),
/// l'adresse toujours.
struct RacineTenue: Equatable, Sendable {
    let adresse: String
    let nom: String?

    var affiche: String { nom ?? adresse }
}
