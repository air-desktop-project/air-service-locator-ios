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
///
/// L'annuaire en rend l'identifiant, l'attestation sous laquelle il est entré
/// et s'il est révoqué — pas de date : il n'en range aucune. Les dates ne
/// sont connues que du téléphone qui a agi, et la biométrie que du téléphone
/// lui-même ; `nil` dit « inconnu d'ici ».
struct Appareil: Identifiable, Hashable, Sendable {
    enum Biometrie: Sendable { case visage, empreinte }
    /// Sous quoi l'appareil est entré (`docs/modele.md` §2.2) : une valeur,
    /// pas une absence — c'est ce qu'on regarde le jour où l'on resserre.
    enum Attestation: String, Sendable { case aucune, apple, google }

    let id: Identifiant
    /// Un nom d'affichage, tenu par l'appareil lui-même — l'annuaire ne le
    /// connaît pas : il ne connaît qu'une clé publique.
    var nom: String
    var biometrie: Biometrie?
    var attestation: Attestation?
    var enroleLe: Date?
    /// Un appareil révoqué reste dans la liste, marqué : l'écran qu'on regarde
    /// après avoir perdu un téléphone doit montrer ce qu'on a retiré.
    var estRevoque: Bool
    /// Poser une date, c'est révoquer : l'un ne va pas sans l'autre.
    var revoqueLe: Date? {
        didSet { if revoqueLe != nil { estRevoque = true } }
    }
    /// Celui qui affiche l'écran. Il ne peut pas se révoquer lui-même.
    var estCeluiCi: Bool

    init(id: Identifiant, nom: String, biometrie: Biometrie? = nil, attestation: Attestation? = nil, enroleLe: Date? = nil,
         revoqueLe: Date? = nil, estRevoque: Bool? = nil, estCeluiCi: Bool = false) {
        self.id = id
        self.nom = nom
        self.biometrie = biometrie
        self.attestation = attestation
        self.enroleLe = enroleLe
        self.revoqueLe = revoqueLe
        self.estRevoque = estRevoque ?? (revoqueLe != nil)
        self.estCeluiCi = estCeluiCi
    }
}
