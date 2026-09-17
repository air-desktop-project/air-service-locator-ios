import SwiftUI

/// Le compte : son identifiant public, son alias, ses appareils, son annuaire.
struct CompteVue: View {
    @Environment(Session.self) private var session
    @State private var appareils: [Appareil] = []
    /// Ce que `GET /v1/version` a rendu : `nil` tant qu'on n'a pas demandé,
    /// `.some(nil)` si l'annuaire ne sait pas le dire.
    @State private var versionAnnuaire: String??
    @State private var aRevoquer: Appareil?
    @State private var erreur: String?
    /// Les révoqués ne s'affichent pas par défaut : ils restent dans
    /// l'annuaire, marqués, mais une liste qui les mêle aux vivants dit mal
    /// combien d'appareils tiennent le compte. Le réglage est retenu.
    @AppStorage("appareils.revoques.visibles") private var revoquesVisibles = false

    private var appareilsMontres: [Appareil] {
        revoquesVisibles ? appareils : appareils.filter { !$0.estRevoque }
    }

    private var nombreDeRevoques: Int { appareils.filter(\.estRevoque).count }

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
                ForEach(appareilsMontres) { appareil in
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
                if nombreDeRevoques > 0 {
                    Toggle("Voir les appareils révoqués (\(nombreDeRevoques))", isOn: $revoquesVisibles)
                }
            } header: {
                Text("Appareils")
            } footer: {
                Text("L'annuaire ne connaît de chaque appareil que son identifiant : c'est lui qui dit si un appareil est bien l'un des vôtres — comparez-le à celui que l'autre appareil affiche pour lui-même. Un appareil que vous ne reconnaissez pas se révoque. Un appareil ne peut pas se révoquer lui-même ; révoqué, il reste dans l'annuaire, marqué, et « Voir les appareils révoqués » le montre. Un compte sur un seul appareil est un compte qu'un téléphone perdu ferme.")
            }

            Section("Annuaire") {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Annuaire")
                    Text("racines air-desktop-project").font(.footnote).foregroundStyle(.secondary)
                }
                // Les deux versions, l'application et l'annuaire, lisibles ici
                // parce que c'est l'écran où l'on va quand quelque chose ne va
                // pas — et qu'un écart entre les deux est souvent la réponse.
                LabeledContent("Version de l'application") {
                    Text(Version.texte).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                }
                LabeledContent("Version de l'annuaire") {
                    switch versionAnnuaire {
                    case .some(.some(let version)): Text(version).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    case .some(.none): Text("ne la dit pas").foregroundStyle(.secondary)
                    case .none: Text("…").foregroundStyle(.tertiary)
                    }
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
            // La version de l'annuaire ne conditionne rien : si elle manque,
            // l'écran le dit, sans en faire une erreur de la page.
            versionAnnuaire = .some(try? await session.annuaire.version())
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
            Image(systemName: icone)
                .foregroundStyle(appareil.estRevoque ? .tertiary : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                // Le nom que l'utilisateur a donné à CE téléphone reste ici, où
                // il est né ; les autres portent le modèle qu'ils ont déclaré
                // à l'annuaire, ou le repli s'ils ne l'ont pas encore fait.
                Text(appareil.estCeluiCi ? UIDevice.current.name : appareil.titre)
                    .foregroundStyle(appareil.estRevoque ? .secondary : .primary)
                Text(sousTitre).font(.footnote).foregroundStyle(.secondary)
                // L'identifiant est la seule chose que l'annuaire sait d'un
                // appareil, et la seule qui permette de le reconnaître d'un
                // écran à l'autre : « Autre appareil » ne dit rien, `a-…` dit
                // lequel.
                Text(appareil.id.texte)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            if appareil.estCeluiCi {
                Text("cet appareil").foregroundStyle(.secondary)
            }
        }
    }

    /// La biométrie quand on la connaît (cet appareil), sinon la plate-forme
    /// déclarée, sinon un téléphone.
    private var icone: String {
        switch (appareil.biometrie, appareil.description?.plateforme) {
        case (.visage, _): "faceid"
        case (.empreinte, _): "touchid"
        case (nil, .macos): "laptopcomputer"
        case (nil, .android): "candybarphone"
        case (nil, .ios), (nil, nil): "iphone.gen3"
        }
    }

    /// Ce que l'on sait, et rien de plus : une date quand cet appareil l'a
    /// vue, l'attestation quand l'annuaire l'a rendue.
    private var sousTitre: String {
        if appareil.estRevoque { return appareil.revoqueLe.map { "Révoqué le \($0.jour)" } ?? "Révoqué" }
        var morceaux = [appareil.enroleLe.map { "Enrôlé le \($0.jour)" } ?? "Enrôlé"]
        switch appareil.biometrie {
        case .visage: morceaux.append("Face ID")
        case .empreinte: morceaux.append("empreinte")
        case nil: break
        }
        switch appareil.attestation {
        case .apple: morceaux.append("attesté par Apple")
        case .android: morceaux.append("clé attestée (Android)")
        case .invitation: morceaux.append("sur invitation")
        case .aucune: morceaux.append("sans attestation")
        case nil: break
        }
        switch appareil.description?.plateforme {
        case .ios: morceaux.append("iOS")
        case .android: morceaux.append("Android")
        case .macos: morceaux.append("macOS")
        case nil: break
        }
        return morceaux.joined(separator: " · ")
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
