import SwiftUI

/// Accorder un accès à un autre compte : son identifiant ou son alias, une
/// portée, une étiquette — et ce que cela révèle, dit avant, pas après.
struct AccorderVue: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var fermer

    @State private var saisie = ""
    @State private var beneficiaire: Identifiant?
    @State private var verdict: Verdict = .vide
    @State private var portee: ChoixPortee = .tout
    @State private var machine: Identifiant?
    @State private var service: Identifiant?
    @State private var etiquette = ""
    @State private var machines: [Machine] = []
    @State private var erreur: String?
    @State private var enCours = false

    enum Verdict: Equatable { case vide, recherche, existe, inconnu, malForme }
    enum ChoixPortee: Hashable { case tout, machine, service }

    private var porteeChoisie: Autorisation.Portee? {
        switch portee {
        case .tout: .tout
        case .machine: machine.map { .machine($0) }
        case .service: service.map { .service($0) }
        }
    }

    private var peutAccorder: Bool {
        verdict == .existe && beneficiaire != nil && porteeChoisie != nil && !enCours
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Identifiant ou alias", text: $saisie)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    LigneVerdict(verdict: verdict)
                } header: {
                    Text("Bénéficiaire")
                } footer: {
                    Text("Un identifiant u-… que la personne vous a transmis, ou son alias public. L'annuaire ne connaît ni nom, ni courriel.")
                }

                Section("Portée") {
                    Picker("Portée", selection: $portee) {
                        Text("Tout mon compte").tag(ChoixPortee.tout)
                        Text("Une machine").tag(ChoixPortee.machine)
                        Text("Un service").tag(ChoixPortee.service)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if portee == .machine {
                        Picker("Machine", selection: $machine) {
                            Text("Choisir…").tag(Identifiant?.none)
                            ForEach(machines) { Text($0.nom).tag(Identifiant?.some($0.id)) }
                        }
                    }
                    if portee == .service {
                        Picker("Service", selection: $service) {
                            Text("Choisir…").tag(Identifiant?.none)
                            ForEach(machines) { m in
                                ForEach(m.services) { s in
                                    Text("\(m.nom) · \(s.nom)").tag(Identifiant?.some(s.id))
                                }
                            }
                        }
                    }
                }

                Section {
                    TextField("Étiquette", text: $etiquette)
                } header: {
                    Text("Étiquette")
                } footer: {
                    Text("Pour savoir ce que vous révoquez dans six mois.")
                }

                Section {
                    Label {
                        Text("Ce compte verra les **noms** de vos machines et services concernés, leurs **adresses IP réelles** et ports, et leur état de joignabilité.")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(Couleurs.attention)
                    }
                }

                if let erreur {
                    Section { Text(erreur).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Accorder un accès")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { fermer() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Accorder") { Task { await accorder() } }.disabled(!peutAccorder)
                }
            }
            .task { machines = (try? await session.annuaire.machines()) ?? [] }
            .task(id: saisie) { await verifier() }
        }
    }

    /// La saisie confirme que le destinataire existe : sans quoi une faute de
    /// frappe produit une autorisation muette accordée à personne.
    private func verifier() async {
        let texte = saisie.trimmingCharacters(in: .whitespaces)
        guard !texte.isEmpty else { verdict = .vide; beneficiaire = nil; return }
        verdict = .recherche
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            if texte.count == Identifiant.longueurTexte || texte.contains("-") && texte.count > 20 {
                let id = try Identifiant.analyser(texte, genre: .utilisateur)
                let existe = try await session.annuaire.utilisateurExiste(id)
                beneficiaire = existe ? id : nil
                verdict = existe ? .existe : .inconnu
            } else if let id = try await session.annuaire.identifiant(pourAlias: texte) {
                beneficiaire = id
                verdict = .existe
            } else {
                beneficiaire = nil
                verdict = .inconnu
            }
        } catch is Identifiant.Erreur {
            beneficiaire = nil
            verdict = .malForme
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func accorder() async {
        guard let beneficiaire, let porteeChoisie else { return }
        enCours = true
        defer { enCours = false }
        do {
            _ = try await session.annuaire.accorder(a: beneficiaire, portee: porteeChoisie, etiquette: etiquette)
            fermer()
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

private struct LigneVerdict: View {
    let verdict: AccorderVue.Verdict

    var body: some View {
        switch verdict {
        case .vide:
            EmptyView()
        case .recherche:
            Label("Vérification…", systemImage: "ellipsis").foregroundStyle(.secondary)
        case .existe:
            Label("Ce compte existe.", systemImage: "checkmark").foregroundStyle(Couleurs.joignable)
        case .inconnu:
            Label("Aucun compte sous cet identifiant ou cet alias.", systemImage: "questionmark").foregroundStyle(Couleurs.attention)
        case .malForme:
            Label("Ce n'est ni un identifiant u-… ni un alias.", systemImage: "xmark").foregroundStyle(.red)
        }
    }
}
