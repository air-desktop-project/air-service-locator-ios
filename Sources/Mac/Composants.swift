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

// MARK: - Les tuiles : lire, et agir en regard de ce qu'on lit

/// Une tuile : un objet de la liste (un domaine, un annuaire, une demande),
/// tout entier lisible, avec ses gestes. Plus aérée qu'une ``Carte``, qui
/// regroupe des réglages.
struct Tuile<Contenu: View>: View {
    @ViewBuilder let contenu: () -> Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { contenu() }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor)))
    }
}

/// Une ligne de tuile ou de carte : le libellé, la valeur ENTIÈRE — elle se
/// replie, elle ne se tronque pas —, et le geste qui porte sur elle, en
/// regard. Sans geste, la ligne se lit seulement.
struct LigneAGeste<Valeur: View, Geste: View>: View {
    let libelle: String
    @ViewBuilder let valeur: () -> Valeur
    @ViewBuilder let geste: () -> Geste

    init(_ libelle: String, @ViewBuilder valeur: @escaping () -> Valeur, @ViewBuilder geste: @escaping () -> Geste) {
        self.libelle = libelle
        self.valeur = valeur
        self.geste = geste
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(libelle).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            valeur().frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            geste().controlSize(.small).fixedSize()
        }
    }
}

extension LigneAGeste where Geste == EmptyView {
    init(_ libelle: String, @ViewBuilder valeur: @escaping () -> Valeur) {
        self.init(libelle, valeur: valeur) { EmptyView() }
    }
}

/// Un état, une étiquette : « Propriétaire », « Acceptée », « En attente ».
struct Badge: View {
    let texte: String
    let couleur: Color
    /// De quoi écrire par-dessus : le vert et l'orange des boutons de
    /// fenêtre ne se lisent pas sur fond clair (``Couleurs``).
    var encre: Color?

    init(_ texte: String, couleur: Color, encre: Color? = nil) {
        self.texte = texte
        self.couleur = couleur
        self.encre = encre
    }

    var body: some View {
        Text(texte)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(couleur.opacity(0.18), in: Capsule())
            .foregroundStyle(encre ?? couleur)
            .fixedSize()
    }
}

/// Un vrai bouton « Copier », pour ce qui se recopie ailleurs.
struct BoutonCopier: View {
    let texte: String
    init(_ texte: String) { self.texte = texte }

    var body: some View {
        Button("Copier") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(texte, forType: .string)
        }
        .help("Copier « \(texte) »")
    }
}

/// Le texte d'un identifiant ou d'une adresse : en police fixe, entier,
/// sélectionnable.
struct TexteFixe: View {
    let texte: String
    var secondaire = false
    init(_ texte: String, secondaire: Bool = false) {
        self.texte = texte
        self.secondaire = secondaire
    }

    var body: some View {
        Text(texte).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            .foregroundStyle(secondaire ? .secondary : .primary)
    }
}

/// Le geste qu'on ne défait pas, à part en bas de page : ce qu'il fait, dit
/// en une phrase, et le bouton rouge.
struct PiedDestructif: View {
    let explication: String
    let titre: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Divider()
            HStack(alignment: .center, spacing: 16) {
                Text(explication).font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                BoutonDestructif(titre, action: action)
            }
        }
        .padding(.top, 8)
    }
}

/// Une feuille de saisie : un titre, une explication, le formulaire, et les
/// boutons en bas — Annuler, et l'action par défaut.
struct FeuilleDeSaisie<Formulaire: View, Gauche: View>: View {
    let titre: String
    var explication: String?
    let action: String
    var actionPermise = true
    var enCours = false
    var erreur: String?
    @ViewBuilder let formulaire: () -> Formulaire
    @ViewBuilder let gauche: () -> Gauche
    let valider: () -> Void
    @Environment(\.dismiss) private var fermer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(titre).font(.title3.weight(.semibold))
            if let explication { Text(explication).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            formulaire()
            if let erreur { Text(erreur).font(.callout).foregroundStyle(Couleurs.Texte.alerte) }
            HStack(spacing: 8) {
                gauche()
                Spacer()
                if enCours { ProgressView().controlSize(.small) }
                Button("Annuler") { fermer() }.keyboardShortcut(.cancelAction)
                Button(action, action: valider)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!actionPermise || enCours)
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(width: 480)
    }
}

extension FeuilleDeSaisie where Gauche == EmptyView {
    init(titre: String, explication: String? = nil, action: String, actionPermise: Bool = true, enCours: Bool = false,
         erreur: String? = nil, @ViewBuilder formulaire: @escaping () -> Formulaire, valider: @escaping () -> Void) {
        self.init(titre: titre, explication: explication, action: action, actionPermise: actionPermise, enCours: enCours,
                  erreur: erreur, formulaire: formulaire, gauche: { EmptyView() }, valider: valider)
    }
}

/// Une page de la fenêtre : défilante, avec sa phrase d'introduction, et une
/// largeur de lecture bornée sur un grand écran.
struct PageFenetre<Contenu: View>: View {
    var introduction: String?
    @ViewBuilder let contenu: () -> Contenu

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let introduction { Text(introduction).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                contenu()
            }
            .padding(24)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Un geste qu'on ne défait pas : un vrai bouton, au texte rouge — le style
/// bordé du Mac ne colore pas seul le rôle destructif.
struct BoutonDestructif: View {
    let titre: String
    let action: () -> Void

    init(_ titre: String, action: @escaping () -> Void) {
        self.titre = titre
        self.action = action
    }

    var body: some View {
        Button(role: .destructive, action: action) {
            Text(titre).foregroundStyle(Couleurs.Texte.alerte)
        }
        .fixedSize()
    }
}
