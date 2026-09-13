import SwiftUI

/// Un point de couleur : ce que l'on met devant une machine ou un service.
struct Pastille: View {
    let couleur: Color
    var taille: CGFloat = 8

    var body: some View {
        Circle().fill(couleur).frame(width: taille, height: taille)
    }
}

extension Joignabilite {
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
}

extension Machine {
    /// Le point dit si la machine tient une connexion à l'annuaire. Il ne dit
    /// pas qu'un service est joignable.
    var couleur: Color {
        if unServiceOscille { return Couleurs.attention }
        if services.contains(where: { if case .annonce = $0.etat { true } else { false } }) { return Couleurs.joignable }
        return Couleurs.parti
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

