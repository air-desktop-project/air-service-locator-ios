import Foundation

/// Ce que deux téléphones s'échangent pour enrôler le second
/// (`docs/protocole.md` §2.2, `POST /v1/appareils`).
///
/// # Pourquoi deux messages, et dans ce sens
///
/// L'annuaire n'enrôle un appareil de plus que **sur la demande d'un appareil
/// déjà enrôlé** : c'est lui qui poste la clé du nouveau. La clé ne peut venir
/// que du nouveau téléphone — elle est née dans son matériel — et l'identifiant
/// rendu ne peut venir que de l'ancien — c'est à lui que l'annuaire l'a dit.
/// D'où l'aller-retour, d'un écran à une caméra :
///
/// 1. le nouveau montre ``cle(_:)`` ;
/// 2. l'ancien la lit, la poste, et montre ``appareil(compte:appareil:)`` ;
/// 3. le nouveau la lit, et prouve sa clé sur sa propre connexion.
///
/// Rien de secret ne passe : une clé publique, deux identifiants. Ce qui
/// prouve, c'est la signature que seul le nouveau saura produire ensuite.
///
/// # La forme
///
/// Un texte, lisible à voix haute au besoin, préfixé pour qu'un lecteur de QR
/// sache ce qu'il tient : `asl:cle:` puis cinquante-trois symboles de
/// Crockford (33 octets) ; `asl:appareil:` puis `u-…:a-…`. Même alphabet que
/// les identifiants, mêmes confusions rattrapées.
enum Invitation: Equatable, Sendable {
    /// Du nouveau vers l'ancien : la clé publique du nouveau, SEC1 compressée.
    case cle([UInt8])
    /// De l'ancien vers le nouveau : le compte rejoint, et l'identifiant que
    /// l'annuaire a donné au nouvel appareil.
    case appareil(compte: Identifiant, appareil: Identifiant)

    static let prefixeCle = "asl:cle:"
    static let prefixeAppareil = "asl:appareil:"

    var texte: String {
        switch self {
        case let .cle(octets): Self.prefixeCle + Crockford.texte(octets)
        case let .appareil(compte, appareil): Self.prefixeAppareil + compte.texte + ":" + appareil.texte
        }
    }

    /// Lit une invitation, ou rend `nil` : un QR étranger, une faute de frappe.
    static func analyser(_ texte: String) -> Invitation? {
        let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        // Un clavier trop zélé fait de `cle` un `clé` : le préfixe se lit sans
        // ses accents, le corps ne peut pas en porter. (Un `é` composé occupe
        // un caractère, comme le `e` qu'il remplace : les positions ne
        // bougent pas.)
        let minuscules = propre.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        if minuscules.hasPrefix(prefixeCle) {
            let corps = String(propre.dropFirst(prefixeCle.count))
            guard let octets = Crockford.octets(corps, compte: Messages.cleOctets), octets[0] == 0x02 || octets[0] == 0x03 else { return nil }
            return .cle(octets)
        }
        if minuscules.hasPrefix(prefixeAppareil) {
            let morceaux = propre.dropFirst(prefixeAppareil.count).split(separator: ":", omittingEmptySubsequences: false)
            guard morceaux.count == 2,
                  let compte = try? Identifiant.analyser(String(morceaux[0]), genre: .utilisateur),
                  let appareil = try? Identifiant.analyser(String(morceaux[1]), genre: .appareil) else { return nil }
            return .appareil(compte: compte, appareil: appareil)
        }
        return nil
    }
}

/// Le base32 de Crockford sur un nombre d'octets quelconque — l'alphabet des
/// identifiants, étendu à une clé.
///
/// Les bits sont lus par groupes de cinq **de droite à gauche**, comme pour un
/// identifiant : le premier symbole ne porte que le reste, et complète à zéro.
/// Ce qui n'est pas un multiple de cinq n'est donc jamais ambigu à la lecture.
enum Crockford {
    static func texte(_ octets: [UInt8]) -> String {
        let symboles = (octets.count * 8 + 4) / 5
        let bourrage = symboles * 5 - octets.count * 8
        let bits = [UInt8](repeating: 0, count: bourrage) + octets.flatMap { octet in (0..<8).reversed().map { (octet >> $0) & 1 } }
        return String((0..<symboles).map { position in
            let tranche = bits[(position * 5)..<(position * 5 + 5)]
            return Identifiant.alphabet[tranche.reduce(0) { ($0 << 1) | Int($1) }]
        })
    }

    /// Les octets, exactement `compte`, ou `nil` : mauvaise longueur, symbole
    /// hors alphabet, ou des bits de bourrage qui ne sont pas à zéro.
    static func octets(_ texte: String, compte: Int) -> [UInt8]? {
        let symboles = (compte * 8 + 4) / 5
        let caracteres = Array(texte)
        guard caracteres.count == symboles else { return nil }
        var bits: [UInt8] = []
        bits.reserveCapacity(symboles * 5)
        for caractere in caracteres {
            guard let valeur = Identifiant.valeur(caractere) else { return nil }
            bits += (0..<5).reversed().map { (valeur >> $0) & 1 }
        }
        let bourrage = symboles * 5 - compte * 8
        guard bits.prefix(bourrage).allSatisfy({ $0 == 0 }) else { return nil }
        let utiles = bits.dropFirst(bourrage)
        return (0..<compte).map { indice in
            utiles[(utiles.startIndex + indice * 8)..<(utiles.startIndex + indice * 8 + 8)].reduce(0) { ($0 << 1) | $1 }
        }
    }
}
