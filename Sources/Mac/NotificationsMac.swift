import Observation
import OSLog
import UserNotifications

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
    private static let journal = Logger(subsystem: "org.airdesktop.servicelocator", category: "notifications")

    private var centre: UNUserNotificationCenter { .current() }

    func relireEtat() async {
        // Le statut seul, lu dans le rappel : les réglages entiers ne sont pas
        // `Sendable`, et le SDK de la CI refuse de les faire traverser.
        let statut = await withCheckedContinuation { suite in
            centre.getNotificationSettings { suite.resume(returning: $0.authorizationStatus) }
        }
        etat = switch statut {
        case .notDetermined: .aDemander
        case .denied: .refusees
        default: .autorisees
        }
    }

    /// Le geste « Activer » : la seule question que macOS posera.
    func activer() async {
        do {
            _ = try await centre.requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.journal.error("la permission n'a pas pu être demandée : \(error.localizedDescription, privacy: .public)")
        }
        await relireEtat()
    }

    /// « Du nouveau » — générique, par principe (``TextesNouveautes``). Une
    /// seule à la fois : la suivante remplace la précédente sous le même
    /// identifiant, plutôt que d'empiler dix fois la même phrase.
    func annoncer() async {
        await relireEtat()
        guard etat == .autorisees else { return }
        let contenu = UNMutableNotificationContent()
        contenu.title = TextesNouveautes.titre
        contenu.body = TextesNouveautes.corps
        contenu.sound = .default
        do {
            try await centre.add(UNNotificationRequest(identifier: "acces", content: contenu, trigger: nil))
        } catch {
            Self.journal.error("la notification n'a pas pu être posée : \(error.localizedDescription, privacy: .public)")
        }
    }
}
