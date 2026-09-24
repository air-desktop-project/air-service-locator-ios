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
    /// `android` est l'attestation de clé du Keystore, vérifiée hors ligne
    /// (C19) ; `invitation`, un code de l'exploitant.
    ///
    /// **`attendue` n'est pas une entrée** : une clé qu'un autre appareil du
    /// compte a apportée sous une posture exigée, et que son porteur n'a pas
    /// encore prouvée. Elle se révoque comme les autres et compte comme
    /// vivante tant qu'elle ne l'est pas — un compte dont le seul appareil
    /// est `attendue` n'est pas orphelin, il est en train de rejoindre
    /// (`protocole.md` §2.2, 2026-09-21).
    enum Attestation: String, Sendable { case aucune, apple, android, invitation, attendue }

    /// Ce que l'appareil fait tourner : une liste fermée, celle des
    /// applications de ce produit (`docs/protocole.md` §2.2).
    enum Plateforme: String, Sendable { case ios, android, macos }

    /// Ce que l'appareil dit de lui-même (`docs/modele.md` §2.2) : sa
    /// plate-forme et son **modèle** — « iPhone 17 », jamais « iPhone de
    /// Thierry », qui porte un prénom (C13).
    ///
    /// **Une étiquette, pas une preuve.** L'annuaire ne vérifie rien de ce
    /// qu'elle dit ; un appareil pirate peut se dire « iPhone 17 ». Ce qui
    /// identifie un appareil est son `a-…`, affiché à côté. L'étiquette sert à
    /// ce que l'écran Compte montre « MacBook Pro » plutôt que « Autre » — de
    /// quoi reconnaître les siens, pas de quoi les prouver.
    struct Description: Hashable, Sendable {
        let plateforme: Plateforme
        let modele: String

        /// Le modèle, 1 à 64 octets : les règles du nom de machine. Un modèle
        /// que le système rendrait trop long est coupé, pas refusé — c'est une
        /// étiquette.
        static let modeleOctetsMax = 64
    }

    let id: Identifiant
    /// Un nom d'affichage de repli, tenu par l'appareil lui-même — quand
    /// l'annuaire n'a pas de ``description`` à rendre.
    var nom: String
    var biometrie: Biometrie?
    var attestation: Attestation?
    /// Absente tant que l'appareil ne l'a pas posée ; reste sur un appareil
    /// révoqué (« iPhone 17, révoqué » dit ce qu'on a retiré).
    var description: Description?
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

    /// Ce que l'écran affiche en titre : le modèle que l'annuaire rend, sinon
    /// le nom de repli.
    var titre: String { description?.modele ?? nom }

    init(id: Identifiant, nom: String, biometrie: Biometrie? = nil, attestation: Attestation? = nil, description: Description? = nil,
         enroleLe: Date? = nil, revoqueLe: Date? = nil, estRevoque: Bool? = nil, estCeluiCi: Bool = false) {
        self.id = id
        self.nom = nom
        self.biometrie = biometrie
        self.attestation = attestation
        self.description = description
        self.enroleLe = enroleLe
        self.revoqueLe = revoqueLe
        self.estRevoque = estRevoque ?? (revoqueLe != nil)
        self.estCeluiCi = estCeluiCi
    }
}
