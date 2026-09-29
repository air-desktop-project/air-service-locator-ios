import Foundation
import ServiceManagement

/// L'agent `asl-echo` de ce Mac (décision 93) : l'`asl` du paquet, lancé par
/// launchd en `asl echo`, enregistré par `SMAppService` — le seul moyen, en
/// bac à sable, de poser un agent de session.
///
/// **L'écho n'est pas actif par défaut** (décision 93, point 4) : la fiche
/// « ce Mac » le propose, l'utilisateur l'active. Une fois enregistré, il
/// tourne à chaque ouverture de session, application fermée comprise ;
/// macOS le montre dans Réglages › Général › Ouverture, où il peut aussi
/// être coupé — d'où ``relire()`` à chaque affichage plutôt qu'un état
/// retenu ici.
@MainActor
@Observable
final class AgentEcho {
    /// `Contents/Library/LaunchAgents/…` dans le paquet.
    static let plist = "org.airdesktop.asl-echo.plist"

    private let service = SMAppService.agent(plistName: AgentEcho.plist)
    private(set) var etat: SMAppService.Status = .notRegistered
    private(set) var erreur: String?

    init() { relire() }

    func relire() { etat = service.status }

    var actif: Bool { etat == .enabled }

    /// Peut-on l'activer ? **`notFound` en fait partie** : tant que rien n'a
    /// été enregistré, macOS ne connaît AUCUN élément d'arrière-plan pour ce
    /// paquet et rend `notFound` — vu sur oxygen, avec le plist bien présent
    /// et signé dans `Contents/Library/LaunchAgents`, et le journal de
    /// `backgroundtaskmanagementd` qui lit sa configuration puis conclut
    /// « record not found ». Le prendre pour « absent du paquet » cachait le
    /// seul bouton qui l'aurait posé.
    var activable: Bool { !actif && etat != .requiresApproval }

    func activer() {
        do {
            try service.register()
            erreur = nil
        } catch {
            erreur = "L'agent n'a pas pu être enregistré : \(error.localizedDescription)"
        }
        relire()
    }

    /// Couper l'agent : launchd l'arrête (SIGTERM), et `asl echo` retire à
    /// l'arrêt la redirection UPnP qu'il avait ouverte, avant de fermer son
    /// bail.
    func desactiver() {
        do {
            try service.unregister()
            erreur = nil
        } catch {
            erreur = "L'agent n'a pas pu être retiré : \(error.localizedDescription)"
        }
        relire()
    }

    func ouvrirLesReglages() { SMAppService.openSystemSettingsLoginItems() }

    var libelle: String {
        switch etat {
        case .enabled: "Actif — répond aux sondes de l'annuaire"
        case .requiresApproval: "En attente de votre accord dans Réglages › Général › Ouverture"
        // `notFound` : rien n'est enregistré — ni plus, ni moins.
        default: "Inactif"
        }
    }
}
