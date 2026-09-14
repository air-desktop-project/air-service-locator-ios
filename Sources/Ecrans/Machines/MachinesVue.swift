import SwiftUI

/// Les machines du compte : celles qui attendent leur enrôlement, puis les
/// autres.
struct MachinesVue: View {
    @Environment(Session.self) private var session
    @State private var machines: [Machine] = []
    @State private var declarer = false
    @State private var erreur: String?

    private var enAttente: [Machine] { machines.filter { if case .enrolee = $0.cle { false } else { true } } }
    private var enrolees: [Machine] { machines.filter { if case .enrolee = $0.cle { true } else { false } } }

    var body: some View {
        List {
            if let erreur {
                Section { Text(erreur).foregroundStyle(.red) }
            }
            if !enAttente.isEmpty {
                Section {
                    ForEach(enAttente) { machine in
                        NavigationLink(value: machine.id) {
                            LigneMachineEnAttente(machine: machine)
                        }
                    }
                } header: {
                    Text("En attente d'enrôlement")
                } footer: {
                    Text("Ouvrez la machine pour lire le code à saisir sur place.")
                }
            }
            Section {
                if enrolees.isEmpty && enAttente.isEmpty {
                    ContentUnavailableView(
                        "Aucune machine",
                        systemImage: "desktopcomputer",
                        description: Text("Déclarez une machine pour obtenir son code d'enrôlement.")
                    )
                }
                ForEach(enrolees) { machine in
                    NavigationLink(value: machine.id) {
                        HStack(spacing: 12) {
                            Pastille(couleur: machine.couleur, taille: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(machine.nom)
                                Text(machine.resumeListe).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Mes machines")
            } footer: {
                if !enrolees.isEmpty {
                    Text("Le point dit si la machine tient une connexion à l'annuaire. Il ne dit pas qu'un service est joignable.")
                }
            }
        }
        .navigationTitle("Machines")
        .navigationDestination(for: Identifiant.self) { id in
            MachineVue(id: id)
        }
        .toolbar {
            Button { declarer = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Déclarer une machine")
        }
        .sheet(isPresented: $declarer, onDismiss: { Task { await charger() } }) {
            DeclarerMachineVue()
        }
        .task { await charger() }
        .refreshable { await charger() }
    }

    private func charger() async {
        do {
            machines = try await session.annuaire.machines()
            erreur = nil
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

private struct LigneMachineEnAttente: View {
    let machine: Machine

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock").foregroundStyle(Couleurs.attention)
            VStack(alignment: .leading, spacing: 2) {
                Text(machine.nom)
                TimelineView(.periodic(from: .now, by: 1)) { contexte in
                    Text(sousTitre(a: contexte.date)).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sousTitre(a instant: Date) -> String {
        switch machine.cle {
        case let .attendue(.some(code)), let .revoquee(_, .some(code)):
            code.estValide(a: instant)
                ? "Code d'enrôlement valable encore \(Duration.seconds(code.reste(a: instant)).formatted(.time(pattern: .minuteSecond)))"
                : "Code d'enrôlement expiré — émettez-en un nouveau"
        case .attendue(nil):
            // Déclarée d'un autre appareil : le code n'est connu que de lui.
            "Pas de clé — émettez un code d'enrôlement"
        case .revoquee:
            "Clé révoquée — émettez un code pour ré-enrôler"
        case .enrolee:
            ""
        }
    }
}
