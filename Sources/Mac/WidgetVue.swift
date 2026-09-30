import AppKit
import SwiftUI

/// Le widget sous l'icône de la barre de menus : il DIT, il ne fait pas.
///
/// Le compte (l'identifiant en entier, à copier), les machines avec leur
/// puce d'état, la version de l'annuaire et celle de l'application — et un
/// seul bouton, qui ouvre la fenêtre. Un clic sur une machine ouvre la
/// fenêtre sur elle. Tout geste vit là-bas : un popover se ferme dès qu'il
/// perd le focus, et Touch ID le lui fait perdre — ce n'est pas un endroit
/// pour agir.
struct WidgetVue: View {
    static let identifiant = FenetreVue.identifiant
    @Environment(Session.self) private var session
    @Environment(Donnees.self) private var donnees
    @Environment(EtatFenetre.self) private var etat
    @Environment(MachineDeCeMac.self) private var machineDeCeMac: MachineDeCeMac?
    @Environment(\.openWindow) private var ouvrirFenetre

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            Divider()
            if session.premiereRelectureEnCours {
                Text("Relecture du compte — Touch ID prouve la clé de ce Mac.")
                    .font(.callout).foregroundStyle(.secondary).padding(14)
            } else if let compte = session.compte {
                sectionCompte(compte)
                sectionMachines
            } else {
                Text("Ce Mac n'est enrôlé sur aucun compte. Ouvrez \(Version.nomDeLApplication) pour en ouvrir un, ou en rejoindre un.")
                    .font(.callout).foregroundStyle(.secondary).padding(14)
            }
            if let erreur = donnees.erreur ?? session.erreurDeRelecture {
                Text(erreur).font(.caption).foregroundStyle(Couleurs.Texte.alerte).padding(.horizontal, 14).padding(.bottom, 8)
            }
            Divider()
            pied
        }
        .task { await donnees.recharger(session) }
    }

    private var entete: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(Version.nomDeLApplication).font(.headline)
                Text("annuaire \(session.annuaire.nom)\(versionDeLAnnuaire)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if donnees.enCours { ProgressView().controlSize(.small) }
            Button {
                Task { await donnees.recharger(session) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Relire l'annuaire")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func sectionCompte(_ compte: Compte) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Titre("Compte")
            HStack(spacing: 8) {
                Text(compte.identifiant.texte).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(compte.identifiant.texte, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copier l'identifiant")
            }
            Text("alias public : \(compte.alias ?? "aucun") · \(donnees.appareilsVivants.count) appareil\(donnees.appareilsVivants.count > 1 ? "s" : "")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var sectionMachines: some View {
        VStack(alignment: .leading, spacing: 2) {
            Titre("Machines").padding(.horizontal, 14)
            if donnees.machines.isEmpty {
                Text("Aucune machine.").font(.callout).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 6)
            }
            ForEach(donnees.machines) { machine in
                Button {
                    ouvrir(sur: .machine(machine.id))
                } label: {
                    TuileDeMachine(machine: machine, estCeMac: machine.id == machineDeCeMac?.identifiant)
                }
                .buttonStyle(.plain)
                .help("Ouvrir cette machine dans la fenêtre")
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var pied: some View {
        HStack {
            Button {
                ouvrir(sur: session.compte == nil ? .compte : etat.page ?? .compte)
            } label: {
                Label("Ouvrir \(Version.nomDeLApplication)", systemImage: "macwindow")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
            Text("app \(Version.texte)").font(.caption2).foregroundStyle(.secondary)
            Button("Quitter") { NSApp.terminate(nil) }
                .buttonStyle(.borderless).font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// « 0.2.2 », ou rien tant qu'on ne sait pas.
    private var versionDeLAnnuaire: String {
        switch donnees.versionAnnuaire {
        case .some(.some(let annuaire)): " · \(annuaire.version)"
        case .some(.none): " · version inconnue"
        case .none: ""
        }
    }

    private func ouvrir(sur page: EtatFenetre.Page) {
        etat.page = page
        ouvrirFenetre(id: FenetreVue.identifiant)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Une machine dans le panneau de la barre de menus.
///
/// # Deux lignes, et rien de tronqué
///
/// C'était un tableau à trois colonnes. Dans 380 points, le nom
/// (« oxygen@air-dictator-house ») retombait à la ligne et l'identifiant ne
/// tenait qu'abrégé — `m-26W6…H4S` —, c'est-à-dire illisible : on ne
/// reconnaît pas une machine à ses dix caractères du milieu manquants, et on
/// ne les recopie pas. Le nom prend donc sa ligne, l'identifiant ENTIER la
/// sienne, et l'état se range au bout de la seconde, là où il reste de la
/// place.
///
/// `lineLimit(1)` avec `fixedSize` : plutôt déborder que couper. Les noms
/// d'aujourd'hui tiennent au large (le plus long, vingt-cinq caractères,
/// occupe la moitié de la largeur).
private struct TuileDeMachine: View {
    let machine: Machine
    let estCeMac: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                PastilleMac(couleur: machine.couleur)
                Text(machine.titre).font(.callout.weight(.medium))
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                if estCeMac {
                    Text("ce Mac").font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Couleurs.accent.opacity(0.14), in: Capsule())
                        .foregroundStyle(Couleurs.accent)
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(machine.id.texte).font(.system(.caption, design: .monospaced))
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Badge(machine.etatCourt, couleur: machine.couleur, encre: machine.encre)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            .padding(.leading, 16)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension Machine {
    /// La couleur de la puce : ce que l'écran iPhone montre aussi.
    var couleur: Color { teintes.pastille }
    /// De quoi écrire son état en badge : le fond prend la couleur de la
    /// puce, l'encre sa teinte lisible (``Couleurs``).
    var encre: Color { teintes.encre }

    /// Les deux d'un coup, pour qu'elles ne divergent jamais.
    private var teintes: (pastille: Color, encre: Color) {
        if unServiceOscille { return (Couleurs.attention, Couleurs.Texte.attention) }
        if services.contains(where: { if case .annonce = $0.etat { true } else { false } }) {
            return (Couleurs.joignable, Couleurs.Texte.joignable)
        }
        if case .revoquee = cle { return (Couleurs.attention, Couleurs.Texte.attention) }
        return (Couleurs.parti, .secondary)
    }

    /// Un mot pour le widget : ce que la machine fait en ce moment.
    var etatCourt: String {
        switch cle {
        case let .attendue(code): return code.map { $0.estValide(a: .now) ? "code valable" : "code expiré" } ?? "pas de clé"
        case .revoquee: return "clé révoquée"
        case .enrolee:
            let vivants = services.filter { if case .annonce = $0.etat { true } else { false } }
            if vivants.isEmpty { return services.isEmpty ? "enrôlée" : "parti" }
            if vivants.contains(where: { if case .joignable = $0.resume { true } else { false } }) { return "joignable" }
            return "annoncé"
        }
    }
}
