import SwiftUI

/// Mon annuaire local : le déclarer, présenter son code sur la machine,
/// suivre l'inscription, déclarer le second membre, le retirer.
struct AnnuaireLocalVue: View {
    @Environment(Session.self) private var session
    @State private var annuaires: [AnnuaireLocal] = []
    @State private var adresse = ""
    @State private var adresseSecond = ""
    @State private var code: CodeInscription?
    @State private var aRetirer: Identifiant?
    @State private var erreur: String?
    @State private var enCours = false

    /// Le titulaire accepté, s'il y en a un : c'est à lui qu'on déclare un
    /// second membre.
    private var titulaireAccepte: Identifiant? {
        annuaires.first { $0.estTitulaire && $0.etat == .acceptee }?.annuaire
    }

    var body: some View {
        List {
            if let erreur {
                Section { Text(erreur).foregroundStyle(.red) }
            }
            if let code {
                Section {
                    Text(code.code).font(.title2.monospaced()).textSelection(.enabled)
                    Text(TextesDomaines.commande(code: code.code, racine: session.annuaireChoisi?.pourLaLigneDeCommande ?? session.annuaire.nom))
                        .font(.footnote.monospaced()).textSelection(.enabled)
                    Text("Expire \(code.expireLe.relatif).").font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text(TextesDomaines.codeTitre)
                } footer: {
                    Text(TextesDomaines.codeAide)
                }
            }
            Section {
                if annuaires.isEmpty {
                    Text(TextesDomaines.aucunAnnuaire).foregroundStyle(.secondary)
                }
                ForEach(annuaires) { annuaire in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(annuaire.membre?.texte ?? annuaire.adresse)
                            // Sur le titulaire : l'état de toute la paire, tel
                            // que la racine qui répond le voit.
                            if annuaire.estTitulaire, annuaire.etat == .acceptee {
                                Spacer()
                                Text(TextesDomaines.etat(EtatDeLAnnuaire(membres: annuaires.filter { $0.annuaire == annuaire.annuaire })))
                                    .font(.footnote.weight(.semibold))
                            }
                        }
                        Text("\(annuaire.adresse) · \(TextesDomaines.etat(annuaire.etat))")
                            .font(.footnote).foregroundStyle(.secondary)
                        if annuaire.etat == .acceptee {
                            Text(TextesDomaines.voie(annuaire.voie)).font(.footnote).foregroundStyle(.secondary)
                            if annuaire.paire == .reglee {
                                Label(TextesDomaines.paireReglee, systemImage: "checkmark.circle.fill")
                                    .font(.footnote).foregroundStyle(Couleurs.joignable)
                            } else if let faute = TextesDomaines.paireFautive(annuaire.paire, membre: annuaire.membre?.abrege ?? annuaire.adresse) {
                                Label("\(TextesDomaines.paireMalReglee) — \(faute)", systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote).foregroundStyle(.red)
                            }
                        }
                        if annuaire.estTitulaire, annuaire.etat != .retiree, let n = annuaire.annuaire {
                            Button(TextesDomaines.retirer, role: .destructive) { aRetirer = n }
                                .buttonStyle(.borderless).font(.footnote)
                        }
                    }
                }
            }
            Section {
                champAdresse($adresse)
                Button(TextesDomaines.declarer) { Task { await declarer() } }
                    .disabled(enCours || !NomsEtAlias.adresseValide(adresse))
            } footer: {
                Text(TextesDomaines.adresseAide)
            }
            if let titulaire = titulaireAccepte {
                Section {
                    champAdresse($adresseSecond)
                    Button(TextesDomaines.secondMembre) { Task { await declarerSecond(de: titulaire) } }
                        .disabled(enCours || !NomsEtAlias.adresseValide(adresseSecond))
                }
            }
        }
        .navigationTitle(TextesDomaines.annuaireLocal)
        .confirmationDialog(TextesDomaines.retirer, isPresented: Binding(get: { aRetirer != nil }, set: { if !$0 { aRetirer = nil } }), titleVisibility: .visible) {
            Button(TextesDomaines.retirer, role: .destructive) {
                if let aRetirer { Task { await retirer(aRetirer) } }
            }
        } message: {
            Text(TextesDomaines.confirmerRetrait)
        }
        .task { await charger() }
        .refreshable { await charger() }
    }

    @ViewBuilder private func champAdresse(_ texte: Binding<String>) -> some View {
        TextField(TextesDomaines.adresse, text: texte)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif
    }

    private func charger() async {
        do {
            annuaires = try await session.annuaire.annuairesLocaux()
            erreur = nil
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func declarer() async {
        enCours = true
        defer { enCours = false }
        do {
            code = try await session.annuaire.declarerAnnuaire(adresse: adresse)
            adresse = ""
            await charger()
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func declarerSecond(de titulaire: Identifiant) async {
        enCours = true
        defer { enCours = false }
        do {
            code = try await session.annuaire.declarerSecondMembre(de: titulaire, adresse: adresseSecond)
            adresseSecond = ""
            await charger()
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func retirer(_ annuaire: Identifiant) async {
        do {
            try await session.annuaire.retirerAnnuaire(annuaire)
            await charger()
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

/// Les inscriptions qui attendent la décision des racines — visible
/// seulement pour qui les administre (`GET /v1/inscriptions` en `200`).
struct AdministrationVue: View {
    @Environment(Session.self) private var session
    @State private var inscriptions: [Inscription] = []
    @State private var aDecider: (Inscription, Bool)?
    @State private var erreur: String?

    var body: some View {
        List {
            if let erreur {
                Section { Text(erreur).foregroundStyle(.red) }
            }
            if inscriptions.isEmpty {
                Text(TextesDomaines.aucuneInscription).foregroundStyle(.secondary)
            }
            ForEach(inscriptions) { inscription in
                VStack(alignment: .leading, spacing: 4) {
                    Text(inscription.membre.texte).font(.body.monospaced())
                    Text("\(inscription.adresse) · \(inscription.proprietaire.texte)").font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        Button(TextesDomaines.accepter) { aDecider = (inscription, true) }
                        Button(TextesDomaines.refuser, role: .destructive) { aDecider = (inscription, false) }
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .navigationTitle(TextesDomaines.administration)
        // Une confirmation explicite, qui dit ce qu'on accepte ou refuse.
        .confirmationDialog(aDecider.map { $0.1 ? TextesDomaines.accepter : TextesDomaines.refuser } ?? "",
                            isPresented: Binding(get: { aDecider != nil }, set: { if !$0 { aDecider = nil } }),
                            titleVisibility: .visible) {
            if let (inscription, accepte) = aDecider {
                Button(accepte ? TextesDomaines.accepter : TextesDomaines.refuser, role: accepte ? nil : .destructive) {
                    Task { await decider(inscription, accepte) }
                }
            }
        } message: {
            if let (inscription, accepte) = aDecider {
                Text(accepte
                     ? TextesDomaines.confirmerAcceptation(membre: inscription.membre.texte, adresse: inscription.adresse, proprietaire: inscription.proprietaire.texte)
                     : TextesDomaines.confirmerRefus)
            }
        }
        .task { await charger() }
        .refreshable { await charger() }
    }

    private func charger() async {
        do {
            inscriptions = try await session.annuaire.inscriptions() ?? []
            erreur = nil
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func decider(_ inscription: Inscription, _ accepte: Bool) async {
        do {
            try await session.annuaire.decider(inscription: inscription.membre, accepte: accepte)
            await charger()
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}
