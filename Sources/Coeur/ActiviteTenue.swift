import Foundation

/// Qui ouvre et ferme une activité — le vrai `ProcessInfo` dans l'application,
/// un compteur dans les essais.
protocol SourceDActivites: Sendable {
    func commencer(raison: String) -> any NSObjectProtocol
    func finir(_ activite: any NSObjectProtocol)
}

/// `ProcessInfo.beginActivity` : ce qui tient l'application éveillée.
///
/// `.userInitiatedAllowingIdleSystemSleep` et rien de plus : l'utilisateur a
/// voulu cette écoute, App Nap ne doit pas l'endormir — mais le Mac garde le
/// droit de se mettre en veille. En veille, la connexion tombe de toute façon,
/// et l'écoute s'arrête proprement.
struct ActivitesDuSysteme: SourceDActivites {
    func commencer(raison: String) -> any NSObjectProtocol {
        ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: raison)
    }

    func finir(_ activite: any NSObjectProtocol) {
        ProcessInfo.processInfo.endActivity(activite)
    }
}

/// Une activité ouverte à la construction, fermée une fois et une seule —
/// par ``terminer()``, ou à défaut quand l'objet disparaît.
///
/// # POURQUOI L'ÉCOUTE DES NOUVELLES EN A BESOIN
///
/// Mesuré le 2026-09-25 sur le Mac : fenêtre passée à l'arrière-plan,
/// `runningboardd` a mis l'application en App Nap **une minute et quinze
/// secondes plus tard** (`PreventTimerThrottleTier4` pour seul reste). Ses
/// minuteries sont alors regroupées et retardées — celles du keepalive de la
/// connexion comprises, qui part toutes les dix secondes. L'annuaire ferme une
/// connexion muette après trente secondes (`--idle`) : elle est tombée pendant
/// la sieste, et on ne l'a appris qu'au réveil, quatre minutes plus tard, par
/// `ASL_NON_CONNECTE`. Une nouvelle arrivée entre-temps n'a jamais été
/// entendue.
///
/// # POURQUOI UN TYPE, ET PAS DEUX APPELS
///
/// Une activité oubliée ouverte tiendrait l'application éveillée pour
/// rien ; deux ouvertes, l'une survivrait à l'autre. La fin est donc
/// garantie par l'objet : ``terminer()`` est sans effet la seconde fois, et
/// `deinit` ferme ce qui ne l'a pas été.
final class ActiviteTenue: @unchecked Sendable {
    private let source: any SourceDActivites
    private let verrou = NSLock()
    private var activite: (any NSObjectProtocol)?

    init(raison: String, source: any SourceDActivites = ActivitesDuSysteme()) {
        self.source = source
        activite = source.commencer(raison: raison)
    }

    deinit { terminer() }

    var enCours: Bool { verrou.withLock { activite != nil } }

    func terminer() {
        let fin: (any NSObjectProtocol)? = verrou.withLock {
            defer { activite = nil }
            return activite
        }
        if let fin { source.finir(fin) }
    }
}
