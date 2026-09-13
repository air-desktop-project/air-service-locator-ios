import SwiftUI

/// Rejoindre un compte existant, **depuis le nouveau téléphone** : montrer sa
/// clé, puis lire l'invitation que l'autre téléphone rend.
///
/// La clé est née ici, dans la Secure Enclave, à la première ouverture de cet
/// écran ; la montrer ne demande aucun geste. Le geste vient à la fin, quand
/// l'invitation est lue : c'est la preuve, sur cette connexion, que la clé
/// enrôlée là-bas est bien celle d'ici.
struct RejoindreVue: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var fermer
    @State private var cle: [UInt8]?
    @State private var enCours = false
    @State private var erreur: String?

    var body: some View {
        List {
            if let cle {
                let invitation = Invitation.cle(cle)
                Section {
                    VStack(spacing: 12) {
                        CodeQR(texte: invitation.texte)
                        Text("Sur le téléphone déjà enrôlé : Compte › Enrôler un autre appareil, puis lisez ce code.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    LigneCopiable(titre: "Ou envoyez-lui ce texte", texte: invitation.texte)
                } header: {
                    Text("1. Montrez la clé de cet appareil")
                } footer: {
                    Text("C'est une clé publique : la montrer ne donne rien à personne. Sa moitié secrète ne quitte pas la Secure Enclave.")
                }
                Section {
                    Text("Il affiche alors un code en retour.").font(.footnote).foregroundStyle(.secondary)
                }
                ReceptionInvitation(attendu: "Le code commence par « asl:appareil: ». Le lire demande un geste : la clé de cet appareil prouve qu'elle est bien celle qui vient d'être enrôlée.") { invitation in
                    Task { await rejoindre(invitation) }
                }
                if enCours {
                    Section { ProgressView("Preuve de la clé…") }
                }
                if let erreur {
                    Section { Text(erreur).foregroundStyle(.red) }
                }
            } else if let erreur {
                Section { Text(erreur).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Rejoindre un compte")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                cle = try session.clePublique()
            } catch {
                erreur = "La clé de cet appareil n'a pas pu être créée : \(error.localizedDescription)"
            }
        }
    }

    private func rejoindre(_ invitation: Invitation) async {
        guard case let .appareil(compte, appareil) = invitation else {
            erreur = "Ce code est une clé, pas une réponse : c'est l'autre téléphone qui doit le lire."
            return
        }
        enCours = true
        defer { enCours = false }
        do {
            try await session.rejoindre(compte: compte, appareil: appareil)
            fermer()
        } catch {
            self.erreur = error.messageAnnuaire
        }
    }
}
