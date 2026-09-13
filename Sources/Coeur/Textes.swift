import Foundation

/// L'application parle français ; ses dates aussi, quel que soit le réglage
/// de l'appareil — un « il y a 2 min » au milieu d'un écran français ne doit
/// pas devenir « 2 minutes ago » parce que le téléphone est en anglais.
extension Locale {
    static let francais = Locale(identifier: "fr_FR")
}

extension Date {
    /// « il y a 2 min », « la semaine dernière ».
    var relatif: String {
        formatted(.relative(presentation: .named).locale(.francais))
    }

    /// « 11 sept. 2026 ».
    var jour: String {
        formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: .francais))
    }
}

extension Joignabilite {
    /// Le mot, exactement — et jamais « en ligne ».
    var libelle: String {
        switch self {
        case .enCours: "Annoncé"
        case .joignable: "Joignable"
        case .injoignable: "Annoncé, injoignable"
        case .nonSonde: "Annoncé"
        }
    }

    /// « joignable » porte toujours sa date : un « joignable » sans date décrit
    /// le passé au présent.
    var detail: String {
        switch self {
        case .enCours: "sonde en cours"
        case let .joignable(depuis, _): "depuis l'annuaire, \(depuis.relatif)"
        case let .injoignable(depuis): "depuis l'annuaire, \(depuis.relatif)"
        case .nonSonde: "UDP — non sondé"
        }
    }
}

extension Service {
    var libelleEtat: String {
        switch etat {
        case .annonce: resume?.libelle ?? "Annoncé"
        case .parti: "Parti"
        }
    }

    var detailEtat: String {
        switch etat {
        case .annonce: resume?.detail ?? ""
        case let .parti(volontaire, le):
            [volontaire.map { $0 ? "arrêt volontaire" : "inactivité" } ?? "motif inconnu", le?.relatif].compactMap { $0 }.joined(separator: ", ")
        }
    }
}

extension Machine {
    var resumeListe: String {
        var morceaux = [capacitesTexte]
        let vivants = services.filter { if case .annonce = $0.etat { true } else { false } }.count
        if vivants > 0 { morceaux.append("\(vivants) service\(vivants > 1 ? "s" : "")") }
        if unServiceOscille { morceaux.append("un service oscille") }
        return morceaux.joined(separator: " · ")
    }
}

/// Une erreur d'annuaire, dite à l'utilisateur dans ses mots.
extension ErreurAnnuaire {
    var message: String {
        switch self {
        case .introuvable: "Introuvable."
        case .interdit: "Un appareil ne peut pas se révoquer lui-même."
        case .aliasPris: "Cet alias est déjà pris."
        case let .requeteInvalide(champ): "Demande refusée : \(champ)."
        case .nonImplemente: "L'annuaire ne sait pas encore le dire."
        case let .reseau(detail): "Annuaire injoignable : \(detail)"
        case .nonConfirme: "Identité non confirmée ; rien n'a été envoyé."
        case .preuveInvalide: "La preuve de possession de la clé ne vérifie pas."
        }
    }
}

extension Error {
    var messageAnnuaire: String {
        (self as? ErreurAnnuaire)?.message ?? localizedDescription
    }
}
