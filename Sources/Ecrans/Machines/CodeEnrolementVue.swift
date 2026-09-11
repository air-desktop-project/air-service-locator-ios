import SwiftUI

/// Le code à taper sur la machine : `asl enrole 4K9M2-P7R1T`.
struct CodeEnrolementVue: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var fermer
    let machine: Machine
    var premiereFois = false
    let apres: () async -> Void

    @State private var code: CodeEnrolement?
    @State private var erreur: String?

    var body: some View {
        VStack(spacing: 28) {
            if let code {
                TimelineView(.periodic(from: .now, by: 1)) { contexte in
                    VStack(spacing: 6) {
                        Text(code.texteGroupe)
                            .font(.system(size: 44, weight: .bold, design: .monospaced))
                            .tracking(4)
                            .foregroundStyle(code.estValide(a: contexte.date) ? .primary : .secondary)
                            .textSelection(.enabled)
                        Label(
                            code.estValide(a: contexte.date)
                                ? "Valable encore \(Duration.seconds(code.reste(a: contexte.date)).formatted(.time(pattern: .minuteSecond)))"
                                : "Expiré",
                            systemImage: "clock"
                        )
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sur la machine, tapez :").font(.footnote).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Image(systemName: "terminal").foregroundStyle(.secondary)
                        Text(code.commande).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button {
                            UIPasteboard.general.string = code.commande
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .accessibilityLabel("Copier la commande")
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                }

                Text("Le code ne sert qu'une fois et n'ouvre qu'une seule opération : lier la clé que la machine génère sur place à ce compte. La clé privée ne quitte jamais la machine.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else if let erreur {
                Text(erreur).foregroundStyle(.red)
            } else {
                ProgressView()
            }

            Spacer()

            VStack(spacing: 10) {
                if let erreur, code != nil {
                    Text(erreur).font(.footnote).foregroundStyle(.red)
                }
                Button {
                    Task { await emettre() }
                } label: {
                    Text("Émettre un nouveau code").frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)
                Text("Le code précédent meurt à l'émission du suivant.")
                    .font(.footnote).foregroundStyle(.secondary)
                if premiereFois {
                    Button {
                        fermer()
                    } label: {
                        Text("Terminé").frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Enrôler \(machine.nom)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(premiereFois)
        .task {
            // Le code émis à la déclaration est encore bon : on ne le remplace
            // pas pour rien. Un code absent ou expiré, lui, appelle le suivant.
            switch machine.cle {
            case let .attendue(existant), let .revoquee(_, .some(existant)):
                if existant.estValide(a: Date()) { code = existant; return }
            case .revoquee, .enrolee:
                break
            }
            await emettre()
        }
    }

    private func emettre() async {
        do {
            code = try await session.annuaire.emettreCode(pour: machine.id)
            erreur = nil
            await apres()
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}
