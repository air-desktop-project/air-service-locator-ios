import Foundation
import Testing
@testable import AirServiceLocator

/// L'activité qui tient l'écoute éveillée : ouverte une fois, fermée une fois,
/// jamais orpheline. Éprouvée sans le vrai `ProcessInfo` — une activité
/// réelle ouverte par un essai tiendrait le simulateur éveillé pour rien.
struct ActiviteTenueEssais {
    /// Compte ce qui s'ouvre et ce qui se ferme, et refuse de fermer ce
    /// qu'il n'a pas ouvert.
    final class Compteur: SourceDActivites, @unchecked Sendable {
        private let verrou = NSLock()
        private var ouvertes: [ObjectIdentifier: String] = [:]
        private(set) var fermetures = 0
        private(set) var etrangeres = 0

        var enCours: Int { verrou.withLock { ouvertes.count } }
        var raisons: [String] { verrou.withLock { Array(ouvertes.values) } }

        func commencer(raison: String) -> any NSObjectProtocol {
            let jeton = NSObject()
            verrou.withLock { ouvertes[ObjectIdentifier(jeton)] = raison }
            return jeton
        }

        func finir(_ activite: any NSObjectProtocol) {
            verrou.withLock {
                if ouvertes.removeValue(forKey: ObjectIdentifier(activite)) == nil { etrangeres += 1 } else { fermetures += 1 }
            }
        }
    }

    @Test func ouverteALaConstructionAvecSaRaison() {
        let compteur = Compteur()
        let activite = ActiviteTenue(raison: "écoute des nouvelles", source: compteur)
        #expect(activite.enCours)
        #expect(compteur.raisons == ["écoute des nouvelles"])
    }

    /// La fin d'une écoute peut être constatée deux fois — par elle-même et
    /// par la suivante qui la remplace : la seconde fois ne ferme rien.
    @Test func terminerDeuxFoisNeFermeQuUneFois() {
        let compteur = Compteur()
        let activite = ActiviteTenue(raison: "écoute", source: compteur)
        activite.terminer()
        activite.terminer()
        #expect(!activite.enCours)
        #expect(compteur.enCours == 0)
        #expect(compteur.fermetures == 1)
        #expect(compteur.etrangeres == 0)
    }

    /// Jamais orpheline : un objet qui disparaît sans avoir été terminé ferme
    /// son activité.
    @Test func disparaitreFermeCeQuiEstOuvert() {
        let compteur = Compteur()
        do { _ = ActiviteTenue(raison: "écoute", source: compteur) }
        #expect(compteur.enCours == 0)
        #expect(compteur.fermetures == 1)
    }

    /// Et un objet terminé puis détruit ne ferme pas une seconde fois.
    @Test func terminePuisDetruitNeFermePasDeuxFois() {
        let compteur = Compteur()
        do { ActiviteTenue(raison: "écoute", source: compteur).terminer() }
        #expect(compteur.fermetures == 1)
        #expect(compteur.etrangeres == 0)
    }

    /// Ce que fait `Donnees.ecouter` quand une écoute en remplace une autre :
    /// l'ancienne est close avant que la nouvelle s'ouvre — jamais deux.
    @Test func uneEcouteQuiEnRemplaceUneAutreNeLaisseQuUneActivite() {
        let compteur = Compteur()
        var eveil: ActiviteTenue? = ActiviteTenue(raison: "première", source: compteur)
        eveil?.terminer()
        eveil = ActiviteTenue(raison: "seconde", source: compteur)
        #expect(compteur.enCours == 1)
        #expect(compteur.raisons == ["seconde"])
        eveil = nil
        #expect(compteur.enCours == 0)
    }
}
