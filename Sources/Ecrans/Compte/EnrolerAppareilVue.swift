import SwiftUI

/// `POST /v1/appareils`, **depuis l'appareil déjà enrôlé** : lire la clé que
/// le nouveau téléphone montre, la poster, et lui rendre l'invitation.
///
/// Deux temps sur un même écran, parce que l'utilisateur tient les deux
/// téléphones : d'abord lire, puis montrer. Rien de secret ne s'affiche — une
/// clé publique, deux identifiants — et c'est le nouveau téléphone qui devra
/// prouver sa clé, sur sa propre connexion.
struct EnrolerAppareilVue: View {
    @Environment(Session.self) private var session
    @State private var enCours = false
    @State private var erreur: String?
    @State private var reponse: Invitation?

    var body: some View {
        List {
            if let reponse {
                Section {
                    VStack(spacing: 12) {
                        CodeQR(texte: reponse.texte)
                        Text("Sur le nouveau téléphone, lisez ce code en retour. Il rejoindra le compte en prouvant sa clé — un geste, là-bas.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    LigneCopiable(titre: "Ou envoyez-lui ce texte", texte: reponse.texte)
                } header: {
                    Text("L'appareil est enrôlé")
                } footer: {
                    Text("Il apparaît dans la liste des appareils. Tant qu'il n'a pas lu ce code, il ne peut rien faire ; un code lu par un autre téléphone ne lui sert à rien sans la clé.")
                }
            } else {
                Section {
                    Text("Sur le nouveau téléphone, ouvrez l'application et choisissez « Rejoindre un compte existant ». Il affiche un code : lisez-le ici.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ReceptionInvitation(attendu: "Le code commence par « asl:cle: » et porte la clé publique du nouveau téléphone — rien de secret.") { invitation in
                    Task { await enroler(invitation) }
                }
                if enCours {
                    Section { ProgressView("Enrôlement…") }
                }
                if let erreur {
                    Section { Text(erreur).foregroundStyle(.red) }
                }
            }
        }
        .navigationTitle("Enrôler un appareil")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(reponse != nil)
    }

    private func enroler(_ invitation: Invitation) async {
        guard case let .cle(cle) = invitation else {
            erreur = "Ce code est une réponse, pas une clé : c'est l'autre téléphone qui doit le lire."
            return
        }
        guard let compte = session.compte else { return }
        enCours = true
        defer { enCours = false }
        do {
            let appareil = try await session.annuaire.enrolerAppareil(cle: cle)
            reponse = .appareil(compte: compte.identifiant, appareil: appareil.id)
            erreur = nil
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

/// Un texte long en police fixe, avec le bouton pour le copier.
struct LigneCopiable: View {
    let titre: String
    let texte: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(.footnote).foregroundStyle(.secondary)
            HStack(alignment: .top) {
                Text(texte).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button {
                    UIPasteboard.general.string = texte
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copier")
            }
        }
    }
}
