import Observation
import OSLog
import UserNotifications

/// Hors de l'acteur : `Logger` est `Sendable`, et rien ne l'y attache.
private let journal = Logger(subsystem: "org.airdesktop.servicelocator", category: "notifications")

/// Les notifications locales du Mac — le seul endroit où l'application en
/// montre (`protocole.md` §2, « notifications sans tiers »).
///
/// # CE QUI LES DÉCLENCHE, ET CE QU'ELLES NE SONT PAS
///
/// Ce n'est pas une poussée : aucun APNs, aucun tiers. L'application tient
/// sa connexion à l'annuaire et y écoute `GET /v1/nouvelles`
/// (``Donnees/ecouter(_:)``) ; quand une ligne arrive, elle relit les accès,
/// et **c'est la différence avec le déjà-vu** (``Nouveautes``) qui décide
/// s'il y a quelque chose à dire. La notification ne sert qu'à le dire hors
/// de la fenêtre — et elle se tait si la permission manque : la pastille
/// d'« Accès » dit la même chose, sans permission.
///
/// # LA PERMISSION, SUR UN GESTE
///
/// macOS ne pose la question qu'une fois. La poser au lancement, c'est la
/// poser à quelqu'un qui ne sait pas encore à quoi elle sert — et un refus
/// là ne se rattrape que dans les Réglages du système. Elle se pose donc
/// sur le bouton « Activer » de la page Compte, après l'explication.
@MainActor
@Observable
final class NotificationsMac {
    enum Etat: Equatable {
        /// Pas encore lu.
        case inconnu
        /// Jamais demandé : le bouton « Activer » est proposé.
        case aDemander
        case autorisees
        /// Refusé — ne se redemande pas d'ici : macOS renvoie aux Réglages.
        case refusees
    }

    private(set) var etat: Etat = .inconnu

    // # RIEN DU CENTRE NE TRAVERSE L'ACTEUR
    //
    // `UNUserNotificationCenter`, ses réglages et ses contenus ne sont pas
    // `Sendable`. Les appeler par leurs méthodes `async` depuis cet acteur,
    // c'est les envoyer hors de lui — ce que le Swift 6 de la CI refuse.
    // Chaque appel se fait donc par sa forme à rappel, dans une fermeture qui
    // obtient le centre elle-même et construit ce qu'elle poste : seuls un
    // statut et un texte d'erreur en reviennent.

    func relireEtat() async {
        let statut = await withCheckedContinuation { suite in
            UNUserNotificationCenter.current().getNotificationSettings { suite.resume(returning: $0.authorizationStatus) }
        }
        etat = switch statut {
        case .notDetermined: .aDemander
        case .denied: .refusees
        default: .autorisees
        }
    }

    /// Le geste « Activer » : la seule question que macOS posera.
    func activer() async {
        let erreur = await withCheckedContinuation { (suite: CheckedContinuation<String?, Never>) in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, erreur in
                suite.resume(returning: erreur?.localizedDescription)
            }
        }
        if let erreur { journal.error("la permission n'a pas pu être demandée : \(erreur, privacy: .public)") }
        await relireEtat()
    }

    /// « Du nouveau » — générique, par principe (``TextesNouveautes``). Une
    /// seule à la fois : la suivante remplace la précédente sous le même
    /// identifiant, plutôt que d'empiler dix fois la même phrase.
    func annoncer() async {
        await relireEtat()
        guard etat == .autorisees else { return }
        let (titre, corps) = (TextesNouveautes.titre, TextesNouveautes.corps)
        let erreur = await withCheckedContinuation { (suite: CheckedContinuation<String?, Never>) in
            let contenu = UNMutableNotificationContent()
            contenu.title = titre
            contenu.body = corps
            contenu.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "acces", content: contenu, trigger: nil)) { erreur in
                suite.resume(returning: erreur?.localizedDescription)
            }
        }
        if let erreur { journal.error("la notification n'a pas pu être posée : \(erreur, privacy: .public)") }
    }
}
