import Observation
import SwiftUI

/// Ce qu'un geste en cours doit garder quand le panneau se ferme.
///
/// # Pourquoi ce n'est pas un `@State` des vues
///
/// Le panneau est un popover de barre de menus : il se ferme dès qu'il perd
/// le focus — et Touch ID le lui fait perdre. Un `@State` vit avec sa vue,
/// et la vue meurt avec le popover : la réponse d'enrôlement, rendue par
/// l'annuaire juste après le geste, disparaissait avant qu'on ait pu la
/// copier. L'enrôlement, lui, avait eu lieu — l'annuaire connaissait un
/// appareil de plus, et l'écran ne savait plus lequel. C'est arrivé.
///
/// Cet objet est porté par l'application, pas par le panneau : il survit à
/// chaque fermeture, et le geste reprend là où il en était quand le panneau
/// rouvre. Rien ici n'est un secret — une clé publique collée, deux
/// identifiants rendus — et rien n'est écrit sur disque : l'application
/// relancée repart d'un panneau vide, ce qui est le sens voulu.
@MainActor
@Observable
final class GestesDuPanneau {
    /// Le geste déplié, s'il y en a un : un seul à la fois.
    enum Geste: Hashable {
        case rejoindre, declarer, enrolerAppareil
    }

    var enCours: Geste?

    // Enrôler un autre appareil, depuis ce Mac.
    /// La clé collée, `asl:cle:…`, tant qu'elle n'est pas enrôlée.
    var cleAEnroler = ""
    /// Ce que l'annuaire a rendu, à donner au nouvel appareil — gardé jusqu'à
    /// « Terminé », quel que soit le nombre de fois où le panneau se ferme.
    var reponseRendue: Invitation?

    // Rejoindre un compte, depuis ce Mac.
    /// La réponse collée, `asl:appareil:…`, tant qu'elle n'est pas prouvée.
    var reponseCollee = ""
}
