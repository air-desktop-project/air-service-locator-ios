import Foundation

/// Un point d'écoute annoncé par un daemon : `(protocole, port)`.
struct PointEcoute: Hashable, Sendable {
    enum Protocole: String, Hashable, Sendable { case tcp, udp }
    let protocole: Protocole
    let port: UInt16

    var texte: String { "\(protocole.rawValue) \(port)" }
}

/// Une adresse où l'on peut essayer de joindre un service, rendue IPv6 d'abord.
struct Candidat: Hashable, Sendable {
    enum Origine: Hashable, Sendable {
        /// Le daemon le dit : vrai sur son réseau, souvent faux ailleurs.
        case annonce
        /// L'annuaire l'a OBSERVÉ sur la connexion d'annonce.
        case reflexif
    }
    let protocole: PointEcoute.Protocole
    let adresse: String
    let port: UInt16
    let origine: Origine
}

/// Ce que l'annuaire affirme d'un point d'écoute, exactement — et jamais « en
/// ligne », qui confond « le daemon parle » avec « on peut l'atteindre »
/// (`docs/modele.md` §4.2).
enum Joignabilite: Hashable, Sendable {
    /// La connexion du daemon est tenue ; la sonde n'a pas encore conclu.
    case enCours
    /// L'annuaire a lui-même ouvert une connexion vers ce candidat, à cette date.
    case joignable(depuis: Date, candidat: String)
    case injoignable(depuis: Date)
    /// L'UDP ne se sonde pas : aucune poignée de main, aucun écho générique.
    case nonSonde
}

/// Ce que l'annuaire a répondu au daemon à son annonce, et qu'aucun autre
/// moyen ne lui apprend (`docs/protocole.md` §1.1) : sous quelle adresse il
/// l'a vu, s'il le croit derrière un NAT, et le bail qu'il lui tient.
struct Diagnostic: Hashable, Sendable {
    /// Le verdict que l'annuaire est seul à pouvoir rendre — et **trois
    /// valeurs, pas un booléen** : sans adresse locale annoncée, il n'y a rien
    /// à comparer, et dire « non » affirmerait une chose qu'on n'a pas mesurée.
    enum Nat: String, Hashable, Sendable {
        case oui, non, indetermine
    }

    /// `adresse:port` d'où l'annuaire a vu la connexion d'annonce.
    var vuDepuis: String?
    var derriereNat: Nat?
    var keepaliveSecondes: Int?
    var inactiviteSecondes: Int?
}

/// Ce qu'un daemon annonce. Identifié par le couple (machine, nom).
struct Service: Identifiable, Hashable, Sendable {
    /// La connexion EST le bail : elle est tenue, ou elle est fermée.
    enum Etat: Hashable, Sendable {
        case annonce(depuis: Date)
        /// Proprement — le daemon l'a dit — ou par expiration du délai
        /// d'inactivité. Un arrêt volontaire et une coupure n'appellent pas la
        /// même réaction chez celui qui regarde.
        /// La date n'est connue que si l'on a vu le départ : l'annuaire n'en
        /// range pas. Et il ne sait plus toujours si c'était voulu.
        case parti(volontaire: Bool?, le: Date?)
    }

    let id: Identifiant
    let nom: String
    var points: [PointEcoute]
    var etat: Etat
    var joignabilite: [PointEcoute: Joignabilite]
    var candidats: [Candidat]
    var oscille: Bool = false
    /// Ce que l'annuaire a répondu à l'annonce ; absent pour un service parti.
    var diagnostic: Diagnostic?

    var pointsTexte: String { points.map(\.texte).joined(separator: " · ") }

    /// Le verdict qui résume le service pour une liste : le meilleur des points
    /// TCP, sinon ce que l'état dit.
    var resume: Joignabilite? {
        guard case .annonce = etat else { return nil }
        let verdicts = points.compactMap { joignabilite[$0] }
        if let bon = verdicts.first(where: { if case .joignable = $0 { true } else { false } }) { return bon }
        if let mauvais = verdicts.first(where: { if case .injoignable = $0 { true } else { false } }) { return mauvais }
        if verdicts.contains(.enCours) { return .enCours }
        return verdicts.first
    }
}
