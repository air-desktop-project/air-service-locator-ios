import SwiftUI

/// Ce qu'un accès reçu me donne à voir : les machines de l'autre compte,
/// dans la portée qu'il a accordée (`GET /v1/utilisateurs/{u}/machines`).
///
/// Identifiant et nom, rien d'autre — ses capacités, sa clé, ses codes
/// n'appartiennent qu'à lui. Vide n'est pas une erreur : c'est ce que
/// l'annuaire rend à qui n'a rien, et il ne dit pas si c'est faute d'accord
/// ou faute de machine.
struct MachinesVisiblesVue: View {
    @Environment(Session.self) private var session
    let de: Identifiant
    let autorisation: Autorisation
    @State private var machines: [MachineVisible]?
    @State private var erreur: String?

    var body: some View {
        List {
            Section {
                LigneCopiable(titre: "Compte", texte: de.texte)
                if autorisation.estRevoquee {
                    Text("Cet accès est révoqué : il ne donne plus rien à voir.").foregroundStyle(.secondary)
                }
            }
            Section {
                if let erreur {
                    Text(erreur).foregroundStyle(.red)
                } else if let machines {
                    if machines.isEmpty {
                        Text("Aucune machine visible : cet accès n'en nomme aucune — ou ce compte n'en a aucune ; l'annuaire ne dit pas lequel.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(machines) { machine in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(machine.nom)
                            Text(machine.id.texte).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                } else {
                    ProgressView()
                }
            } header: {
                Text("Ses machines, dans la portée accordée")
            } footer: {
                Text("Identifiant et nom : ce qu'il faut pour demander où joindre un service (asl ou <machine> <service>). Le reste n'appartient qu'à lui.")
            }
        }
        .navigationTitle("Ce que je vois de lui")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { machines = try await session.annuaire.machines(de: de) } catch { erreur = error.messageAnnuaire }
        }
    }
}
