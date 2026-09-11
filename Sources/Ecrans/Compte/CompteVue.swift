import SwiftUI

/// Le compte : son identifiant public, son alias, ses appareils, son annuaire.
struct CompteVue: View {
    @Environment(Session.self) private var session
    @State private var appareils: [Appareil] = []
    @State private var aRevoquer: Appareil?
    @State private var erreur: String?

    var body: some View {
        List {
            if let erreur {
                Section { Text(erreur).foregroundStyle(.red) }
            }
            if let compte = session.compte {
                Section {
                    LigneIdentifiant(titre: "Identifiant public", identifiant: compte.identifiant, partageable: true)
                    NavigationLink {
                        AliasVue()
                    } label: {
                        LabeledContent("Alias public", value: compte.alias ?? "aucun")
                    }
                } header: {
                    Text("Identité")
                } footer: {
                    Text("À donner à qui doit vous accorder un accès. Un alias est public et devinable ; sans alias, seul l'identifiant vous rend trouvable.")
                }
            }

            Section {
                ForEach(appareils) { appareil in
                    LigneAppareil(appareil: appareil)
                        .swipeActions {
                            if !appareil.estRevoque && !appareil.estCeluiCi {
                                Button("Révoquer", role: .destructive) { aRevoquer = appareil }
                            }
                        }
                }
                NavigationLink {
                    EnrolerAppareilVue()
                } label: {
                    Label("Enrôler un autre appareil", systemImage: "plus").foregroundStyle(Couleurs.accent)
                }
            } header: {
                Text("Appareils")
            } footer: {
                Text("Un appareil ne peut pas se révoquer lui-même ; révoqué, il reste dans la liste. Un compte sur un seul appareil est un compte qu'un téléphone perdu ferme.")
            }

            Section("Annuaire") {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Annuaire")
                    Text("racines air-desktop-project").font(.footnote).foregroundStyle(.secondary)
                }
                NavigationLink {
                    ExpositionsVue()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ce qui est exposé de moi")
                        Text("Par relation entre annuaires, et ce que vous en retirez.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Compte")
        .confirmationDialog("Révoquer \(aRevoquer?.nom ?? "cet appareil") ?", isPresented: Binding(get: { aRevoquer != nil }, set: { if !$0 { aRevoquer = nil } }), titleVisibility: .visible) {
            Button("Révoquer", role: .destructive) {
                if let aRevoquer { Task { await revoquer(aRevoquer) } }
            }
        } message: {
            Text("Cet appareil ne pourra plus administrer le compte. Il reste dans la liste, marqué.")
        }
        .task { await charger() }
        .refreshable { await charger() }
    }

    private func charger() async {
        do {
            appareils = try await session.annuaire.appareils()
            await session.rafraichirCompte()
            erreur = nil
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func revoquer(_ appareil: Appareil) async {
        do {
            try await session.annuaire.revoquerAppareil(appareil.id)
            await charger()
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

private struct LigneAppareil: View {
    let appareil: Appareil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: appareil.biometrie == .visage ? "faceid" : "touchid")
                .foregroundStyle(appareil.estRevoque ? .tertiary : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                // L'annuaire ne connaît aucun nom : celui de cet appareil vient
                // du téléphone lui-même.
                Text(appareil.estCeluiCi ? UIDevice.current.name : appareil.nom)
                    .foregroundStyle(appareil.estRevoque ? .secondary : .primary)
                Text(sousTitre).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if appareil.estCeluiCi {
                Text("cet appareil").foregroundStyle(.secondary)
            }
        }
    }

    private var sousTitre: String {
        if let le = appareil.revoqueLe { return "Révoqué le \(le.jour)" }
        return "Enrôlé le \(appareil.enroleLe.jour) · \(appareil.biometrie == .visage ? "Face ID" : "empreinte")"
    }
}

/// L'alias public — la seule donnée que l'utilisateur nous confie.
struct AliasVue: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var fermer
    @State private var alias = ""
    @State private var erreur: String?

    var body: some View {
        Form {
            Section {
                TextField("alias", text: $alias)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } footer: {
                Text("Lettres, chiffres et tirets, de 3 à 32. Il est public par construction : quiconque peut essayer un alias et découvrir qu'il existe. Il ne rend rien d'autre que votre identifiant.")
            }
            if let erreur {
                Section { Text(erreur).foregroundStyle(.red) }
            }
            if session.compte?.alias != nil {
                Section {
                    Button("Retirer l'alias", role: .destructive) { Task { await definir(nil) } }
                }
            }
        }
        .navigationTitle("Alias public")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Enregistrer") { Task { await definir(alias) } }
                .disabled(!AnnuaireSimule.aliasValide(alias) || alias == session.compte?.alias)
        }
        .onAppear { alias = session.compte?.alias ?? "" }
    }

    private func definir(_ valeur: String?) async {
        do {
            try await session.definirAlias(valeur)
            fermer()
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

/// `POST /v1/appareils` : un appareil déjà enrôlé apporte la clé du nouveau,
/// lue d'un code affiché à l'écran. **Le geste n'est pas encore écrit** — ni
/// la clé matérielle, ni l'échange entre les deux téléphones.
struct EnrolerAppareilVue: View {
    var body: some View {
        ContentUnavailableView(
            "Pas encore possible",
            systemImage: "iphone.gen3.badge.plus",
            description: Text("L'enrôlement d'un second appareil demande la clé matérielle et l'échange d'un code entre les deux téléphones. Ce sera écrit avec le transport.")
        )
        .navigationTitle("Enrôler un appareil")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// `GET /v1/expositions` rend `501` aujourd'hui, et c'est exact : la table des
/// relations entre annuaires n'est pas écrite. Dire « rien n'est exposé »
/// serait pire.
struct ExpositionsVue: View {
    var body: some View {
        ContentUnavailableView(
            "L'annuaire ne sait pas encore le dire",
            systemImage: "arrow.triangle.branch",
            description: Text("Ce qui est exposé de vous, relation par relation, apparaîtra ici quand la fédération entre annuaires sera écrite. Vous pourrez alors en retirer votre compte, ou telle de vos machines.")
        )
        .navigationTitle("Expositions")
        .navigationBarTitleDisplayMode(.inline)
    }
}
