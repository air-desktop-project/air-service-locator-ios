import AppKit
import SwiftUI

// Les morceaux que le widget et la fenêtre partagent.

/// Un titre qu'on clique pour déplier ce qu'il annonce. Toute la ligne
/// répond, pas seulement un triangle : dans un panneau de barre de menus, la
/// cible doit être large.
struct Depliant<Contenu: View>: View {
    let titre: String
    @Binding var ouvert: Bool
    @ViewBuilder let contenu: () -> Contenu

    init(_ titre: String, ouvert: Binding<Bool>, @ViewBuilder contenu: @escaping () -> Contenu) {
        self.titre = titre
        _ouvert = ouvert
        self.contenu = contenu
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { ouvert.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(ouvert ? 90 : 0))
                    Text(titre).font(.callout)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if ouvert { contenu() }
        }
    }
}

struct Titre: View {
    let texte: String
    init(_ texte: String) { self.texte = texte }
    var body: some View {
        Text(texte.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
    }
}

/// Un texte en police fixe, avec le bouton pour le copier.
struct LigneCopiableMac: View {
    let titre: String
    let texte: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titre).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top) {
                Text(texte).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(texte, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copier")
            }
        }
    }
}

struct PastilleMac: View {
    let couleur: Color
    var taille: CGFloat = 8
    var body: some View { Circle().fill(couleur).frame(width: taille, height: taille) }
}

// MARK: - Les morceaux de la fenêtre

/// Un cadre à fond blanc, bordé, comme un groupe de réglages.
struct Carte<Contenu: View>: View {
    var fond: Color = Color(nsColor: .textBackgroundColor)
    var marges: CGFloat = 12
    @ViewBuilder let contenu: () -> Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { contenu() }
            .padding(marges)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fond, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
    }
}

/// Une ligne « libellé — valeur » d'une carte : le libellé à gauche sur une
/// colonne fixe, la valeur qui prend le reste et se replie sans se tronquer.
struct Champ<Valeur: View>: View {
    let libelle: String
    @ViewBuilder let valeur: () -> Valeur

    init(_ libelle: String, @ViewBuilder valeur: @escaping () -> Valeur) {
        self.libelle = libelle
        self.valeur = valeur
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(libelle).foregroundStyle(.secondary).frame(width: 160, alignment: .leading)
            valeur().frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }
}

/// Un identifiant ou une commande, en police fixe, entier, avec son bouton
/// pour le copier. `suite` est ce qu'on affiche après, hors copie.
struct Copiable: View {
    let texte: String
    var suite: String = ""

    init(_ texte: String, suite: String = "") {
        self.texte = texte
        self.suite = suite
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            (Text(texte).font(.system(.body, design: .monospaced)) + Text(suite).font(.body))
                .textSelection(.enabled)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(texte, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc").font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Copier")
        }
    }
}
