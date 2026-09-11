import Foundation

/// Le code qu'un administrateur recopie du téléphone vers un terminal :
/// `asl enrole 4K9M2-P7R1T`.
///
/// Dix symboles de Crockford — cinquante bits — à usage unique, valables dix
/// minutes (`docs/modele.md` §2.3). Il est groupé pour l'œil, cinq par cinq :
/// c'est un humain qui le tape, et chaque symbole de trop est une occasion de
/// se tromper.
///
/// **C'est un secret partagé, et il faut le dire** : ce qui le rend acceptable
/// est qu'il n'authentifie rien sur la durée. Une fois, quelques minutes, une
/// seule opération — lier une clé.
struct CodeEnrolement: Hashable, Sendable {
    static let nombreSymboles = 10
    static let validite: TimeInterval = 600

    /// Les dix symboles, en majuscules canoniques.
    let symboles: String
    let expireLe: Date

    /// Groupé pour l'œil : `4K9M2-P7R1T`.
    var texteGroupe: String {
        "\(symboles.prefix(5))-\(symboles.suffix(5))"
    }

    /// La commande à taper sur la machine.
    var commande: String { "asl enrole \(texteGroupe)" }

    func estValide(a instant: Date) -> Bool { instant < expireLe }

    /// Le temps qu'il reste, jamais négatif.
    func reste(a instant: Date) -> TimeInterval { max(0, expireLe.timeIntervalSince(instant)) }

    /// Depuis huit octets d'aléa, comme `asl_cle::CodeEnrolement::depuis_entropie`.
    init(entropie: [UInt8], emisLe: Date) {
        precondition(entropie.count == 8)
        var valeur = entropie.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } >> 14
        var caracteres: [Character] = []
        for _ in 0..<Self.nombreSymboles {
            caracteres.append(Identifiant.alphabet[Int(valeur & 31)])
            valeur >>= 5
        }
        symboles = String(caracteres.reversed())
        expireLe = emisLe.addingTimeInterval(Self.validite)
    }
}
