import SwiftUI

/// Les autorisations, dans les deux sens. Les révoquées restent, barrées.
struct AccesVue: View {
    @Environment(Session.self) private var session
    @State private var autorisations: [Autorisation] = []
    @State private var machines: [Machine] = []
    @State private var accorder = false
    @State private var aRevoquer: Autorisation?
    @State private var erreur: String?

    private var moi: Identifiant? { session.compte?.identifiant }
    private var accordees: [Autorisation] { autorisations.filter { $0.accordeePar == moi } }
    private var recues: [Autorisation] { autorisations.filter { $0.accordeeA == moi } }

    var body: some View {
        List {
            if let erreur {
                Section { Text(erreur).foregroundStyle(.red) }
            }
            Section {
                if accordees.isEmpty {
                    Text("Vous n'avez accordé aucun accès.").foregroundStyle(.secondary)
                }
                ForEach(accordees) { autorisation in
                    LigneAutorisation(autorisation: autorisation, machines: machines, sens: .accordee)
                        .swipeActions {
                            if !autorisation.estRevoquee {
                                Button("Révoquer", role: .destructive) { aRevoquer = autorisation }
                            }
                        }
                }
            } header: {
                Text("Accordés par moi")
            } footer: {
                Text("Retirer suffit : il n'y a aucun jeton à récupérer. Les accès révoqués restent visibles, barrés.")
            }
            Section {
                if recues.isEmpty {
                    Text("Personne ne vous a encore accordé d'accès.").foregroundStyle(.secondary)
                }
                ForEach(recues) { autorisation in
                    LigneAutorisation(autorisation: autorisation, machines: machines, sens: .recue)
                }
            } header: {
                Text("Accordés à moi")
            } footer: {
                Text("Vos machines portant la capacité « lecture » peuvent résoudre ces services.")
            }
        }
        .navigationTitle("Accès")
        .toolbar {
            Button { accorder = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Accorder un accès")
        }
        .sheet(isPresented: $accorder, onDismiss: { Task { await charger() } }) {
            AccorderVue()
        }
        .confirmationDialog("Révoquer cet accès ?", isPresented: Binding(get: { aRevoquer != nil }, set: { if !$0 { aRevoquer = nil } }), titleVisibility: .visible) {
            Button("Révoquer", role: .destructive) {
                if let aRevoquer { Task { await revoquer(aRevoquer) } }
            }
        } message: {
            Text("Effet immédiat. Les machines de ce compte ne pourront plus résoudre ce que cet accès ouvrait.")
        }
        .task { await charger() }
        .refreshable { await charger() }
    }

    private func charger() async {
        do {
            async let a = session.annuaire.autorisations()
            async let m = session.annuaire.machines()
            autorisations = try await a
            machines = try await m
            erreur = nil
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func revoquer(_ autorisation: Autorisation) async {
        do {
            try await session.annuaire.revoquerAutorisation(autorisation.id)
            await charger()
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

struct LigneAutorisation: View {
    enum Sens { case accordee, recue }
    let autorisation: Autorisation
    let machines: [Machine]
    let sens: Sens

    /// L'annuaire ne connaît ni nom ni courriel : ce que l'on peut montrer de
    /// l'autre compte est son identifiant, et — pour ce que l'on a accordé —
    /// l'étiquette que l'on a posée soi-même.
    private var titre: String {
        switch sens {
        case .accordee: autorisation.etiquette.isEmpty ? autorisation.accordeeA.abrege : autorisation.etiquette
        case .recue: autorisation.accordeePar.abrege
        }
    }

    private var sousTitre: String {
        var morceaux: [String] = []
        if case .accordee = sens, !autorisation.etiquette.isEmpty { morceaux.append(autorisation.accordeeA.abrege) }
        morceaux.append(portee)
        if let le = autorisation.revoqueeLe { morceaux.append("révoquée \(le.relatif)") }
        return morceaux.joined(separator: " · ")
    }

    private var portee: String {
        switch autorisation.portee {
        case .tout: sens == .accordee ? "Tout mon compte" : "Tout son compte"
        case let .machine(id): "Machine \(machines.first { $0.id == id }?.nom ?? id.abrege)"
        case let .service(id):
            "Service \(machines.flatMap(\.services).first { $0.id == id }?.nom ?? id.abrege)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titre)
                .strikethrough(autorisation.estRevoquee)
                .foregroundStyle(autorisation.estRevoquee ? .secondary : .primary)
            Text(sousTitre).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
