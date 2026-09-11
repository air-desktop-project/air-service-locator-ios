import SwiftUI

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

/// Un point de couleur : ce que l'on met devant une machine ou un service.
struct Pastille: View {
    let couleur: Color
    var taille: CGFloat = 8

    var body: some View {
        Circle().fill(couleur).frame(width: taille, height: taille)
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

    var couleur: Color {
        switch self {
        case .enCours: Couleurs.accent
        case .joignable: Couleurs.joignable
        case .injoignable: Couleurs.attention
        case .nonSonde: Color(uiColor: .systemGray3)
        }
    }
}

extension Service {
    var couleur: Color {
        switch etat {
        case .annonce: resume?.couleur ?? Couleurs.accent
        case .parti: Couleurs.parti
        }
    }

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
            "\(volontaire ? "arrêt volontaire" : "inactivité"), \(le.relatif)"
        }
    }
}

extension Machine {
    /// Le point dit si la machine tient une connexion à l'annuaire. Il ne dit
    /// pas qu'un service est joignable.
    var couleur: Color {
        if unServiceOscille { return Couleurs.attention }
        if services.contains(where: { if case .annonce = $0.etat { true } else { false } }) { return Couleurs.joignable }
        return Couleurs.parti
    }

    var resumeListe: String {
        var morceaux = [capacitesTexte]
        let vivants = services.filter { if case .annonce = $0.etat { true } else { false } }.count
        if vivants > 0 { morceaux.append("\(vivants) service\(vivants > 1 ? "s" : "")") }
        if unServiceOscille { morceaux.append("un service oscille") }
        return morceaux.joined(separator: " · ")
    }
}

/// Une ligne « identifiant à copier ».
struct LigneIdentifiant: View {
    let titre: String
    let identifiant: Identifiant
    var partageable = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titre).font(.footnote).foregroundStyle(.secondary)
                Text(identifiant.texte).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
            }
            Spacer()
            Button {
                UIPasteboard.general.string = identifiant.texte
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Copier l'identifiant")
            if partageable {
                ShareLink(item: identifiant.texte) { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.borderless)
            }
        }
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
        }
    }
}

extension Error {
    var messageAnnuaire: String {
        (self as? ErreurAnnuaire)?.message ?? localizedDescription
    }
}
