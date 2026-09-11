import Foundation

/// Une arête entre deux comptes — jamais un jeton porteur. On voit à qui on a
/// donné, on retire à qui on veut, et retirer suffit : il n'y a rien à
/// récupérer (`docs/modele.md` §2.5).
struct Autorisation: Identifiable, Hashable, Sendable {
    /// Un seul champ, et le genre de l'identifiant la désigne — un objet
    /// `{sorte, cible}` rendrait représentable une demande incohérente.
    enum Portee: Hashable, Sendable {
        case tout
        case machine(Identifiant)
        case service(Identifiant)
    }

    let id: Identifiant
    let accordeePar: Identifiant
    let accordeeA: Identifiant
    let portee: Portee
    /// Libre — pour savoir ce qu'on révoque six mois plus tard.
    var etiquette: String
    let accordeeLe: Date
    /// Révoquée, elle reste dans la liste, marquée : taire les révoquées ferait
    /// douter d'avoir cliqué.
    var revoqueeLe: Date?

    var estRevoquee: Bool { revoqueeLe != nil }
}
