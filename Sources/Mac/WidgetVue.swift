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
                Text("Ce Mac n'est enrôlé sur aucun compte. Ouvrez Service Locator pour en ouvrir un, ou en rejoindre un.")
                    .font(.callout).foregroundStyle(.secondary).padding(14)
            }
            if let erreur = donnees.erreur ?? session.erreurDeRelecture {
                Text(erreur).font(.caption).foregroundStyle(.red).padding(.horizontal, 14).padding(.bottom, 8)
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
                Text("Service Locator").font(.headline)
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
            Text("alias public : \(compte.alias ?? "aucun") · \(donnees.appareils.count) appareil\(donnees.appareils.count > 1 ? "s" : "")")
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
                    HStack(spacing: 10) {
                        PastilleMac(couleur: machine.couleur)
                        Text(machine.nom).font(.callout.weight(.medium))
                        if machine.id == machineDeCeMac?.identifiant {
                            Text("ce Mac").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(machine.id.abrege).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        Text(machine.etatCourt).font(.caption).foregroundStyle(.secondary)
                            .frame(width: 78, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .contentShape(Rectangle())
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
                Label("Ouvrir Service Locator", systemImage: "macwindow")
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
        case .some(.some(let version)): " · \(version)"
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

extension Machine {
    /// La couleur de la puce : ce que l'écran iPhone montre aussi.
    var couleur: Color {
        if unServiceOscille { return Couleurs.attention }
        if services.contains(where: { if case .annonce = $0.etat { true } else { false } }) { return Couleurs.joignable }
        if case .attendue = cle { return Couleurs.parti }
        if case .revoquee = cle { return Couleurs.attention }
        return Couleurs.parti
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
