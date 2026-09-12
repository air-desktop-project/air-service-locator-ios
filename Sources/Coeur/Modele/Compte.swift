import Foundation

/// Le compte : un identifiant, un jeu d'appareils, et rien d'autre.
///
/// Pas de courriel, pas de numéro, pas de nom, pas de mot de passe. La seule
/// donnée confiée est l'**alias**, facultatif, public et devinable — il ne rend
/// que l'identifiant, et ne l'enregistrer jamais est une position tenable.
struct Compte: Hashable, Sendable {
    let identifiant: Identifiant
    var alias: String?
}

/// Un téléphone enrôlé. **C'est l'appareil qui signe**, jamais l'utilisateur.
struct Appareil: Identifiable, Hashable, Sendable {
    enum Biometrie: Sendable { case visage, empreinte }

    let id: Identifiant
    /// Un nom d'affichage, tenu par l'appareil lui-même — l'annuaire ne le
    /// connaît pas : il ne connaît qu'une clé publique.
    var nom: String
    var biometrie: Biometrie
    let enroleLe: Date
    /// Un appareil révoqué reste dans la liste, marqué : l'écran qu'on regarde
    /// après avoir perdu un téléphone doit montrer ce qu'on a retiré.
    var revoqueLe: Date?
    /// Celui qui affiche l'écran. Il ne peut pas se révoquer lui-même.
    var estCeluiCi: Bool

    var estRevoque: Bool { revoqueLe != nil }
}
