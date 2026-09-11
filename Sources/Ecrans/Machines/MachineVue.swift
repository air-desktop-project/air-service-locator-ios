import SwiftUI

/// Une machine : ses services et leur joignabilité, son identité, sa clé.
struct MachineVue: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var fermer
    let id: Identifiant

    @State private var machine: Machine?
    @State private var erreur: String?
    @State private var renommer = false
    @State private var nouveauNom = ""
    @State private var confirmerRevocation = false

    var body: some View {
        List {
            if let erreur {
                Section { Text(erreur).foregroundStyle(.red) }
            }
            if let machine {
                if machine.capacites.contains(.annonce) {
                    Section {
                        if machine.services.isEmpty {
                            Text("Aucun service annoncé pour l'instant.").foregroundStyle(.secondary)
                        }
                        ForEach(machine.services) { service in
                            LigneService(service: service)
                        }
                    } header: {
                        Text("Services")
                    } footer: {
                        Text("« Joignable » veut dire : l'annuaire a lui-même ouvert une connexion vers ce port, à cette date. Un point d'écoute UDP ne se sonde pas.")
                    }
                }

                Section("Machine") {
                    LigneIdentifiant(titre: "Identifiant public", identifiant: machine.id)
                    NavigationLink {
                        CapacitesVue(machine: machine) { await charger() }
                    } label: {
                        LabeledContent("Capacités", value: machine.capacitesTexte.isEmpty ? "aucune" : machine.capacitesTexte)
                    }
                    LigneCle(machine: machine)
                }

                switch machine.cle {
                case .enrolee:
                    Section {
                        Button(role: .destructive) { confirmerRevocation = true } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Révoquer la clé")
                                Text("Effet immédiat : connexions fermées, baux tombés. La machine reste, il faudra la ré-enrôler sur place.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                case .attendue, .revoquee:
                    Section {
                        NavigationLink {
                            CodeEnrolementVue(machine: machine) { await charger() }
                        } label: {
                            Label("Code d'enrôlement", systemImage: "terminal")
                        }
                    }
                }
            }
        }
        .navigationTitle(machine?.nom ?? "")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            Button("Renommer") {
                nouveauNom = machine?.nom ?? ""
                renommer = true
            }
        }
        .alert("Renommer la machine", isPresented: $renommer) {
            TextField("Nom", text: $nouveauNom)
            Button("Annuler", role: .cancel) {}
            Button("Renommer") { Task { await modifier(nom: nouveauNom) } }
                .disabled(!Machine.nomValide(nouveauNom))
        } message: {
            Text("Pour vous, jamais pour la machine. Un nom ne retire aucun droit.")
        }
        .confirmationDialog("Révoquer la clé de \(machine?.nom ?? "") ?", isPresented: $confirmerRevocation, titleVisibility: .visible) {
            Button("Révoquer la clé", role: .destructive) { Task { await revoquer() } }
        } message: {
            Text("Les connexions de la machine sont fermées à la seconde et ses annonces tombent. Elle garde son nom, ses capacités et ses services ; il faudra saisir un nouveau code sur place.")
        }
        .task { await charger() }
    }

    private func charger() async {
        do {
            let toutes = try await session.annuaire.machines()
            guard let trouvee = toutes.first(where: { $0.id == id }) else {
                throw ErreurAnnuaire.introuvable
            }
            machine = trouvee
            erreur = nil
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func modifier(nom: String) async {
        do {
            machine = try await session.annuaire.modifierMachine(id, nom: nom, capacites: nil)
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func revoquer() async {
        do {
            try await session.annuaire.revoquerCle(de: id)
            await charger()
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

struct LigneService: View {
    let service: Service

    var body: some View {
        HStack(spacing: 12) {
            Pastille(couleur: service.couleur)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.nom).font(.system(.subheadline, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.75)
                Text(service.pointsTexte).font(.footnote).foregroundStyle(.secondary)
                if service.oscille {
                    Text("Deux daemons de ce nom se chassent l'un l'autre.")
                        .font(.caption).foregroundStyle(Couleurs.attention)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(service.libelleEtat).font(.footnote.weight(.semibold))
                Text(service.detailEtat).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
            .frame(maxWidth: 130, alignment: .trailing)
        }
    }
}

private struct LigneCle: View {
    let machine: Machine

    var body: some View {
        switch machine.cle {
        case let .enrolee(le):
            Label {
                LabeledContent("Clé", value: "enrôlée \(le.relatif)")
            } icon: {
                Image(systemName: "checkmark").foregroundStyle(Couleurs.joignable)
            }
        case .attendue:
            Label {
                LabeledContent("Clé", value: "pas encore enrôlée")
            } icon: {
                Image(systemName: "clock").foregroundStyle(Couleurs.attention)
            }
        case let .revoquee(le, _):
            Label {
                LabeledContent("Clé", value: "révoquée \(le.relatif)")
            } icon: {
                Image(systemName: "xmark").foregroundStyle(.red)
            }
        }
    }
}

/// Les capacités d'une machine, modifiables — `PATCH /v1/machines/{m}`.
struct CapacitesVue: View {
    @Environment(Session.self) private var session
    let machine: Machine
    let apres: () async -> Void
    @State private var capacites: Set<Capacite>
    @State private var erreur: String?

    init(machine: Machine, apres: @escaping () async -> Void) {
        self.machine = machine
        self.apres = apres
        _capacites = State(initialValue: machine.capacites)
    }

    var body: some View {
        List {
            Section {
                ChoixCapacites(capacites: $capacites)
            } footer: {
                Text("Retirer l'annonce ferme les connexions de la machine et fait tomber ses baux. Retirer la lecture ne ferme rien : sa prochaine demande sera refusée.")
            }
            if let erreur {
                Section { Text(erreur).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Capacités")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: capacites) { _, nouvelles in
            Task {
                do {
                    _ = try await session.annuaire.modifierMachine(machine.id, nom: nil, capacites: nouvelles)
                    await apres()
                } catch {
                    erreur = error.messageAnnuaire
                }
            }
        }
    }
}

/// Les deux cases, avec ce que chacune ouvre. Rien n'est coché d'avance.
struct ChoixCapacites: View {
    @Binding var capacites: Set<Capacite>

    var body: some View {
        Toggle(isOn: lien(.annonce)) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Annonce")
                Text("Ses daemons peuvent annoncer leurs ports.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        Toggle(isOn: lien(.lecture)) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Lecture")
                Text("Elle peut demander où joindre un service — les vôtres, et ceux qu'on vous a accordés.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func lien(_ capacite: Capacite) -> Binding<Bool> {
        Binding(
            get: { capacites.contains(capacite) },
            set: { coche in if coche { capacites.insert(capacite) } else { capacites.remove(capacite) } }
        )
    }
}
