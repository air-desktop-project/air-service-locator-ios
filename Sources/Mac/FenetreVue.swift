import AppKit
import SwiftUI

/// La fenêtre de l'application : une barre latérale, une page.
///
/// Compte, Machines (chacune sous son nom, avec sa puce), Appareils, Accès —
/// et, dans la page, tout ce que le widget n'a pas la place de dire : les
/// identifiants en entier, les dates, les verdicts, les gestes. Rien n'y est
/// tronqué ; c'est la raison d'être de cette fenêtre.
///
/// Tant qu'elle est ouverte, l'application est ordinaire — Dock, menu,
/// ⌘-Tab ; fermée, elle se retire dans la barre de menus. C'est ce que
/// `LSUIElement` seul ne sait pas faire, et ce que `onAppear`/`onDisappear`
/// font ici.
struct FenetreVue: View {
    static let identifiant = "principale"

    @Environment(Session.self) private var session
    @Environment(Donnees.self) private var donnees
    @Environment(EtatFenetre.self) private var etat

    @Environment(MachineDeCeMac.self) private var machineDeCeMac: MachineDeCeMac?

    var body: some View {
        @Bindable var etat = etat
        Group {
            if session.premiereRelectureEnCours {
                ProgressView("Relecture du compte — Touch ID prouve la clé de ce Mac.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.compte == nil {
                SansCompteVue()
            } else {
                NavigationSplitView {
                    lateral
                } detail: {
                    page
                }
                .toolbar { barreDOutils }
                .sheet(item: $etat.feuille) { feuille in
                    FeuilleVue(feuille: feuille)
                        .environment(session)
                        .environment(donnees)
                        .environment(gestes)
                        .environment(machineDeCeMac)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .task { await donnees.recharger(session) }
        .onAppear { NSApp.setActivationPolicy(.regular) }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }

    @Environment(GestesDuPanneau.self) private var gestes

    /// Ce Mac est-il déjà une machine que l'annuaire connaît ? Sinon, le
    /// geste est proposé — une machine oubliée là-bas se refait ici.
    private var ceMacEstUneMachine: Bool {
        guard let machineDeCeMac else { return true }
        return donnees.machines.contains { $0.id == machineDeCeMac.identifiant }
    }

    // MARK: - La barre d'outils

    @ToolbarContentBuilder private var barreDOutils: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                etat.feuille = .declarerMachine
            } label: {
                Label("Ajouter une machine", systemImage: "plus")
            }
            .help("Ajouter une machine — déclarer un Linux, et obtenir son code d'enrôlement")
            Button {
                etat.feuille = .ceMacMachine
            } label: {
                Label("Faire de ce Mac une machine", systemImage: "laptopcomputer.and.arrow.down")
            }
            .help(ceMacEstUneMachine ? "Ce Mac est déjà une machine du compte" : "Faire de ce Mac une machine — déclarer et enrôler ce Mac, en un geste")
            .disabled(ceMacEstUneMachine)
            Button {
                Task { await donnees.recharger(session) }
            } label: {
                Label("Relire l'annuaire", systemImage: "arrow.clockwise")
            }
            .help("Relire l'annuaire")
        }
    }

    // MARK: - La barre latérale

    private var lateral: some View {
        @Bindable var etat = etat
        // Tout en sections : une liste à sélection qui mêle lignes nues et
        // sections perd la sélection des lignes qui suivent une section.
        return List(selection: $etat.page) {
            Section {
                Label("Compte", systemImage: "person.crop.circle").tag(EtatFenetre.Page.compte)
            }
            Section {
                ForEach(donnees.machines) { machine in
                    HStack(spacing: 8) {
                        PastilleMac(couleur: machine.couleur)
                        Text(machine.nom)
                    }
                    .tag(EtatFenetre.Page.machine(machine.id))
                }
                if donnees.machines.isEmpty {
                    Text("Aucune machine").foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Label("Machines", systemImage: "desktopcomputer")
                    Spacer()
                    Text("\(donnees.machines.count)").foregroundStyle(.secondary)
                }
            }
            Section {
                HStack {
                    Label("Appareils", systemImage: "iphone.gen3")
                    Spacer()
                    Text("\(donnees.appareilsVivants.count)").foregroundStyle(.secondary)
                }
                .tag(EtatFenetre.Page.appareils)
                HStack {
                    Label("Accès", systemImage: "key.horizontal")
                    Spacer()
                    Text("\(donnees.autorisations.filter { !$0.estRevoquee }.count)").foregroundStyle(.secondary)
                }
                .tag(EtatFenetre.Page.acces)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.annuaire.nom)\(versionDeLAnnuaire)")
                Text("Service Locator \(Version.texte)")
            }
            .font(.caption2).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var versionDeLAnnuaire: String {
        switch donnees.versionAnnuaire {
        case .some(.some(let annuaire)): " · annuaire \(annuaire.version)"
        case .some(.none): " · version inconnue"
        case .none: ""
        }
    }

    // MARK: - La page

    @ViewBuilder private var page: some View {
        switch etat.page {
        case .compte, .none:
            CompteFenetreVue()
        case let .machine(id):
            if let machine = donnees.machine(id) {
                MachineFenetreVue(machine: machine)
            } else {
                ContentUnavailableView("Cette machine n'est plus dans l'annuaire", systemImage: "desktopcomputer")
            }
        case .appareils:
            AppareilsFenetreVue()
        case .acces:
            AccesFenetreVue()
        }
    }
}

/// Un geste en feuille : déclarer une machine, ou faire de ce Mac une
/// machine. La feuille est la même vue que le panneau montrait ; elle a ici
/// un titre, une marge et un bouton pour la fermer.
struct FeuilleVue: View {
    @Environment(Session.self) private var session
    @Environment(Donnees.self) private var donnees
    @Environment(MachineDeCeMac.self) private var machineDeCeMac: MachineDeCeMac?
    @Environment(\.dismiss) private var fermer
    let feuille: EtatFenetre.Feuille

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(titre).font(.title2.weight(.semibold))
            switch feuille {
            case .declarerMachine:
                DeclarerVueMac { await donnees.recharger(session); fermer() }
            case .ceMacMachine:
                if let machineDeCeMac {
                    CeMacMachineVueMac(machineDeCeMac: machineDeCeMac) { await donnees.recharger(session); fermer() }
                } else {
                    Text("Le banc de démonstration ne sait pas enrôler une machine.").foregroundStyle(.secondary)
                }
            }
            HStack { Spacer(); Button("Fermer") { fermer() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var titre: String {
        switch feuille {
        case .declarerMachine: "Ajouter une machine"
        case .ceMacMachine: "Faire de ce Mac une machine"
        }
    }
}

/// Ce Mac n'a pas de compte : en ouvrir un, ou en rejoindre un — le geste
/// d'ouverture de compte, sous Touch ID.
struct SansCompteVue: View {
    @Environment(Session.self) private var session
    @Environment(Donnees.self) private var donnees
    @Environment(GestesDuPanneau.self) private var gestes
    @State private var erreur: String?
    @State private var enCours = false
    /// Ce que `GET /v1/version` a dit : `nil` tant qu'on n'a pas demandé. Ce
    /// Mac n'a pas de compte, donc `Donnees` n'a rien relu — c'est cet écran
    /// qui demande, et lui seul.
    @State private var annuaire: VersionAnnuaire??
    @State private var codeSaisi = ""

    private var exigeUneInvitation: Bool { (annuaire ?? nil)?.exigeUneInvitation ?? false }
    private var invitation: CodeInvitation? { CodeInvitation.essai(codeSaisi) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
            Text("Service Locator").font(.largeTitle.weight(.bold))
            Text("Vos machines, leurs daemons, et le port où les joindre.").font(.title3).foregroundStyle(.secondary)
            Text("Un compte est un jeu d'appareils, sans mot de passe. La clé de ce Mac vit dans sa Secure Enclave et signe sous Touch ID ; rien d'autre ne quitte la machine.")
                .font(.callout).foregroundStyle(.secondary)
            if exigeUneInvitation {
                VStack(alignment: .leading, spacing: 6) {
                    Text(TextesInvitation.titre).font(.headline)
                    Text(TextesInvitation.explication).font(.callout).foregroundStyle(.secondary)
                    TextField(TextesInvitation.exemple, text: $codeSaisi)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 220)
                    Text(TextesInvitation.duree).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let erreur = erreur ?? session.erreurDeRelecture { Text(erreur).font(.callout).foregroundStyle(.red) }
            HStack {
                Button {
                    Task { await ouvrir() }
                } label: {
                    Label("Ouvrir un compte avec Touch ID", systemImage: "touchid")
                }
                .buttonStyle(.borderedProminent)
                .disabled(enCours || (exigeUneInvitation && invitation == nil))
                if enCours { ProgressView().controlSize(.small) }
            }
            Depliant("Rejoindre un compte existant", ouvert: Binding(get: { gestes.enCours == .rejoindre }, set: { gestes.enCours = $0 ? .rejoindre : nil })) {
                RejoindreVueMac()
            }
        }
        .frame(maxWidth: 520)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { annuaire = .some(try? await session.annuaire.version()) }
    }

    private func ouvrir() async {
        enCours = true
        defer { enCours = false }
        do {
            try await session.ouvrirCompte(invitation: exigeUneInvitation ? invitation : nil)
            erreur = nil
            await donnees.recharger(session)
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}
