import SwiftUI

/// Le premier écran : ouvrir un compte. Pas de mot de passe, pas de formulaire
/// — un geste biométrique, et un identifiant public en retour.
struct AccueilVue: View {
    @Environment(Session.self) private var session
    @State private var enCours = false
    @State private var erreur: String?
    @State private var rejoindre = false

    var body: some View {
        let etat = session.identite.etat()
        VStack(spacing: 0) {
            List {
                Section {
                    VStack(spacing: 12) {
                        Logo(taille: 84)
                        Text("Service Locator").font(.title.weight(.bold))
                        Text("Vos machines, leurs daemons, et le port où les joindre.")
                            .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                Section {
                    Argument(icone: icone(pour: etat), titre: "Aucun mot de passe",
                             texte: "Votre compte est cet appareil. \(nom(pour: etat)) confirme que c'est vous, ici, et rien ne quitte l'appareil.")
                    Argument(icone: "key", titre: "Une clé dans la Secure Enclave",
                             texte: "Elle signe vos demandes et ne peut pas en sortir.")
                    Argument(icone: "eye.slash", titre: "Aucune donnée personnelle",
                             texte: "Ni courriel, ni numéro, ni nom. Vous recevez un identifiant public, c'est tout.")
                }
                Section {
                    LabeledContent("Annuaire", value: "Racines air-desktop-project")
                } header: {
                    Text("Annuaire")
                } footer: {
                    Text("Vous pourrez désigner votre propre annuaire, ou celui de votre organisation.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))

            VStack(spacing: 10) {
                if let erreur {
                    Text(erreur).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                Button {
                    Task { await ouvrir() }
                } label: {
                    Label("Ouvrir un compte avec \(nom(pour: etat))", systemImage: icone(pour: etat))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .disabled(enCours || !peutOuvrir(etat))
                Button("Rejoindre un compte existant") { rejoindre = true }
                    .font(.subheadline)
                    .disabled(enCours || !peutOuvrir(etat))
                Text(pied(pour: etat))
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .sheet(isPresented: $rejoindre) {
            NavigationStack { RejoindreVue() }
        }
    }

    private func ouvrir() async {
        enCours = true
        defer { enCours = false }
        do {
            try await session.ouvrirCompte()
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func peutOuvrir(_ etat: IdentiteLocale.Etat) -> Bool {
        switch etat {
        case .visage, .empreinte: true
        case .rienEnrole, .indisponible: false
        }
    }

    private func nom(pour etat: IdentiteLocale.Etat) -> String {
        switch etat {
        case .visage: "Face ID"
        case .empreinte: "Touch ID"
        case .rienEnrole, .indisponible: "la biométrie"
        }
    }

    private func icone(pour etat: IdentiteLocale.Etat) -> String {
        switch etat {
        case .visage: "faceid"
        case .empreinte, .rienEnrole, .indisponible: "touchid"
        }
    }

    /// Ce qui exclut l'application se dit ici, tout de suite, plutôt qu'au
    /// moment de la première connexion.
    private func pied(pour etat: IdentiteLocale.Etat) -> String {
        switch etat {
        case .visage, .empreinte:
            "Un compte sur un seul appareil est un compte qu'un téléphone perdu ferme. Vous pourrez en enrôler un second."
        case .rienEnrole:
            "Aucune biométrie n'est enrôlée sur cet appareil. Enrôlez un visage ou une empreinte dans les Réglages, puis revenez."
        case let .indisponible(raison):
            "Cet appareil ne peut pas confirmer l'identité de son porteur, et cette application ne peut donc pas y ouvrir de compte. \(raison)"
        }
    }
}

private struct Argument: View {
    let icone: String
    let titre: String
    let texte: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icone).font(.title3).foregroundStyle(Couleurs.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(titre)
                Text(texte).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// PROVISOIRE : aucun logo « Air » n'existe encore. Une pastille, en attendant.
struct Logo: View {
    let taille: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: taille * 0.22, style: .continuous)
            .fill(Couleurs.accent)
            .frame(width: taille, height: taille)
            .overlay {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: taille * 0.42, weight: .light))
                    .foregroundStyle(.white)
            }
    }
}
