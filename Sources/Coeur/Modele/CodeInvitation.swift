import Foundation

/// Le code qu'un exploitant d'annuaire donne à qui il invite, et que celui-ci
/// recopie à l'ouverture de son compte.
///
/// Dix symboles de Crockford — cinquante bits —, à usage unique, valables
/// vingt-quatre heures par défaut (`docs/protocole.md` §2.1, la posture
/// `invitation`). Même forme qu'un ``CodeEnrolement``, et pour la même raison :
/// c'est un humain qui le tape, souvent depuis un message ou un bout de papier.
///
/// # Ici on LIT un code, là on en AFFICHE un
///
/// ``CodeEnrolement`` sait se fabriquer et se montrer : l'annuaire le rend, et
/// l'application l'affiche. Celui-ci fait l'inverse — il n'est jamais produit
/// ici, seulement saisi —, d'où un type à part plutôt qu'un initialiseur de
/// plus : les deux n'ont ni la même provenance ni la même durée, et les
/// confondre ferait écrire un jour `asl enroll` avec une invitation.
///
/// # Ce qui part sur le fil
///
/// **Les dix symboles canoniques, en ASCII** — dix octets exactement, dans la
/// case d'attestation de `POST /v1/comptes` sous la plate-forme `3`. L'annuaire
/// refuse `400` si la case n'en porte pas dix : c'est pourquoi le tiret
/// d'affichage se retire ICI, avant l'envoi, et non là-bas.
struct CodeInvitation: Hashable, Sendable {
    static let nombreSymboles = 10

    /// Les dix symboles, en majuscules canoniques — sans tiret.
    let symboles: String

    enum Erreur: Error, Equatable {
        case longueur(obtenue: Int)
        case symboleInvalide(Character)
    }

    /// Lit un code tapé par un humain.
    ///
    /// **La casse est indifférente, le tiret d'affichage est accepté autant
    /// qu'omis, et les confusions de Crockford sont rattrapées** (`I` et `L`
    /// valent `1`, `O` vaut `0`) — par ``Identifiant/valeur(_:)``, qui porte
    /// déjà cette table. Refuser `4k9m2-p7r1t` parce qu'on a affiché
    /// `4K9M2-P7R1T` serait une cruauté gratuite.
    ///
    /// Les espaces sont retirés aussi : un code collé depuis un message en
    /// traîne souvent un.
    init(saisie: String) throws(Erreur) {
        let utiles = saisie.filter { !$0.isWhitespace && $0 != "-" }
        guard utiles.count == Self.nombreSymboles else {
            throw .longueur(obtenue: utiles.count)
        }
        var canoniques: [Character] = []
        canoniques.reserveCapacity(Self.nombreSymboles)
        for caractere in utiles {
            guard let chiffre = Identifiant.valeur(caractere) else {
                throw .symboleInvalide(caractere)
            }
            canoniques.append(Identifiant.alphabet[Int(chiffre)])
        }
        symboles = String(canoniques)
    }

    /// Groupé pour l'œil : `4K9M2-P7R1T`.
    var texteGroupe: String { "\(symboles.prefix(5))-\(symboles.suffix(5))" }

    /// Les dix octets ASCII que porte la case d'attestation.
    var octets: [UInt8] { Array(symboles.utf8) }

    /// Ce qu'une saisie en cours vaut : `nil` tant qu'elle n'est pas un code.
    /// De quoi n'activer un bouton que lorsqu'il servira à quelque chose,
    /// sans crier sur qui n'a pas fini de taper.
    static func essai(_ saisie: String) -> CodeInvitation? { try? CodeInvitation(saisie: saisie) }
}
