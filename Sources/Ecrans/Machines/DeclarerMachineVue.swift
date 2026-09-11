import SwiftUI

/// Déclarer une machine : un nom, des capacités, et le code en retour.
struct DeclarerMachineVue: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var fermer
    @State private var nom = ""
    @State private var capacites: Set<Capacite> = []
    @State private var declaree: Machine?
    @State private var erreur: String?
    @State private var enCours = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom", text: $nom)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Nom")
                } footer: {
                    Text("Pour vous, jamais pour la machine. Accents et émoji acceptés, 64 octets au plus.")
                }
                Section {
                    ChoixCapacites(capacites: $capacites)
                } header: {
                    Text("Capacités")
                } footer: {
                    Text("Rien n'est coché d'avance. Une machine qui porte les deux a un rayon de dégât plus large : un daemon compromis pourrait aussi énumérer tout ce que vous avez le droit de voir.")
                }
                if let erreur {
                    Section { Text(erreur).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Nouvelle machine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { fermer() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Suivant") { Task { await declarer() } }
                        .disabled(enCours || !Machine.nomValide(nom))
                }
            }
            .navigationDestination(item: $declaree) { machine in
                CodeEnrolementVue(machine: machine, premiereFois: true) {}
            }
        }
    }

    private func declarer() async {
        enCours = true
        defer { enCours = false }
        do {
            declaree = try await session.annuaire.declarerMachine(nom: nom, capacites: capacites)
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}
