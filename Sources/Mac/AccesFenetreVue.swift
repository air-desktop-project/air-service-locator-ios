import SwiftUI

/// Les accès : ce que j'ai accordé, ce qu'on m'a accordé — en entier, avec
/// l'identifiant complet de l'autre compte —, et le geste d'accorder.
///
/// L'annuaire ne connaît ni nom ni courriel : ce qu'on peut montrer de
/// l'autre compte est son identifiant, et — pour ce qu'on a accordé —
/// l'étiquette qu'on a posée soi-même (`POST /v1/autorisations` l'exige).
struct AccesFenetreVue: View {
    @Environment(Session.self) private var session
    @Environment(Donnees.self) private var donnees
    @State private var accorde = false
    @State private var beneficiaire = ""
    @State private var portee: Choix = .tout
    @State private var machineChoisie: Identifiant?
    @State private var etiquette = ""
    @State private var aRevoquer: Autorisation?
    @State private var erreur: String?
    @State private var enCours = false

    enum Choix: Hashable { case tout, machine }

    private var moi: Identifiant? { session.compte?.identifiant }
    private var accordees: [Autorisation] { donnees.autorisations.filter { $0.accordeePar == moi } }
    private var recues: [Autorisation] { donnees.autorisations.filter { $0.accordeeA == moi } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let erreur { Text(erreur).font(.callout).foregroundStyle(.red) }
                HStack(alignment: .firstTextBaseline) {
                    Titre("Accordés par moi")
                    Spacer()
                    Button { accorde.toggle() } label: { Label("Accorder un accès", systemImage: "plus") }.controlSize(.small)
                }
                if accorde { formulaire }
                liste(accordees, sens: .accordee, vide: "Vous n'avez accordé aucun accès.")
                Text("Retirer suffit : il n'y a aucun jeton à récupérer. Les accès révoqués restent visibles, barrés.")
                    .font(.caption).foregroundStyle(.secondary)
                Titre("Accordés à moi")
                liste(recues, sens: .recue, vide: "Personne ne vous a encore accordé d'accès.")
                Text("Utiliser un service hébergé ailleurs, c'est laisser une trace chez son propriétaire : c'est son annuaire qui journalise vos résolutions, pendant quatre-vingt-dix jours.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Accès")
        .confirmationDialog("Révoquer cet accès ?", isPresented: Binding(get: { aRevoquer != nil }, set: { if !$0 { aRevoquer = nil } }), titleVisibility: .visible) {
            Button("Révoquer", role: .destructive) { if let aRevoquer { Task { await revoquer(aRevoquer) } } }
        } message: {
            Text("Effet immédiat. L'accès reste dans la liste, barré.")
        }
    }

    private var formulaire: some View {
        Carte(fond: Color(nsColor: .controlBackgroundColor)) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Identifiant du bénéficiaire, u-…, ou son alias", text: $beneficiaire)
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                Picker("Portée", selection: $portee) {
                    Text("Tout mon compte").tag(Choix.tout)
                    Text("Une machine").tag(Choix.machine)
                }
                .pickerStyle(.segmented).frame(maxWidth: 320)
                if portee == .machine {
                    Picker("Machine", selection: $machineChoisie) {
                        Text("Choisir…").tag(Identifiant?.none)
                        ForEach(donnees.machines) { Text($0.nom).tag(Identifiant?.some($0.id)) }
                    }
                    .frame(maxWidth: 320)
                }
                TextField("Étiquette, pour vous — « Marie », « le NAS du bureau »", text: $etiquette).textFieldStyle(.roundedBorder)
                Text("L'étiquette est la seule chose qui vous dira, plus tard, à qui vous avez donné : l'annuaire ne connaît de l'autre que son identifiant.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Accorder") { Task { await accorder() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(enCours || etiquette.trimmingCharacters(in: .whitespaces).isEmpty || beneficiaire.trimmingCharacters(in: .whitespaces).isEmpty || (portee == .machine && machineChoisie == nil))
                    Button("Annuler") { accorde = false }
                    if enCours { ProgressView().controlSize(.small) }
                }
            }
            .padding(4)
        }
    }

    private func liste(_ autorisations: [Autorisation], sens: LigneAcces.Sens, vide: String) -> some View {
        Carte(marges: 0) {
            if autorisations.isEmpty {
                Text(vide).foregroundStyle(.secondary).padding(12)
            }
            ForEach(Array(autorisations.enumerated()), id: \.element.id) { indice, autorisation in
                if indice > 0 { Divider() }
                HStack(alignment: .top) {
                    LigneAcces(autorisation: autorisation, machines: donnees.machines, sens: sens)
                    Spacer()
                    if sens == .accordee, !autorisation.estRevoquee {
                        Button("Révoquer", role: .destructive) { aRevoquer = autorisation }.controlSize(.small)
                    }
                }
                .padding(12)
            }
        }
    }

    private func accorder() async {
        enCours = true
        defer { enCours = false }
        do {
            let texte = beneficiaire.trimmingCharacters(in: .whitespaces)
            let qui: Identifiant
            if let id = try? Identifiant.analyser(texte, genre: .utilisateur) {
                qui = id
            } else if let id = try await session.annuaire.identifiant(pourAlias: texte) {
                qui = id
            } else {
                erreur = "« \(texte) » n'est ni un identifiant ni un alias connu."
                return
            }
            guard try await session.annuaire.utilisateurExiste(qui) else {
                erreur = "Aucun compte ne porte l'identifiant \(qui.texte)."
                return
            }
            let quoi: Autorisation.Portee = portee == .tout ? .tout : .machine(machineChoisie!)
            _ = try await session.annuaire.accorder(a: qui, portee: quoi, etiquette: etiquette.trimmingCharacters(in: .whitespaces))
            accorde = false
            beneficiaire = ""
            etiquette = ""
            erreur = nil
            await donnees.recharger(session)
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func revoquer(_ autorisation: Autorisation) async {
        do {
            try await session.annuaire.revoquerAutorisation(autorisation.id)
            erreur = nil
            await donnees.recharger(session)
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

/// Une autorisation, en entier : l'étiquette, l'identifiant complet de
/// l'autre compte, la portée, la date.
struct LigneAcces: View {
    enum Sens { case accordee, recue }
    let autorisation: Autorisation
    let machines: [Machine]
    let sens: Sens

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(titre).font(.body.weight(.medium))
                    .strikethrough(autorisation.estRevoquee)
                    .foregroundStyle(autorisation.estRevoquee ? .secondary : .primary)
                if autorisation.estRevoquee {
                    Text("révoqué").font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(.secondary)
                }
            }
            Text(sousTitre).font(.caption).foregroundStyle(.secondary)
            Copiable(sens == .accordee ? autorisation.accordeeA.texte : autorisation.accordeePar.texte)
        }
    }

    private var titre: String {
        switch sens {
        case .accordee: autorisation.etiquette.isEmpty ? "Sans étiquette" : autorisation.etiquette
        case .recue: "Accordé par \(autorisation.accordeePar.abrege)"
        }
    }

    private var sousTitre: String {
        var morceaux = [portee, "accordé le \(autorisation.accordeeLe.jour)"]
        if let le = autorisation.revoqueeLe { morceaux.append("révoqué le \(le.jour)") }
        return morceaux.joined(separator: " · ")
    }

    private var portee: String {
        switch autorisation.portee {
        case .tout: sens == .accordee ? "tout mon compte" : "tout son compte"
        case let .machine(id): "la machine « \(machines.first { $0.id == id }?.nom ?? id.abrege) »"
        case let .service(id): "le service « \(machines.flatMap(\.services).first { $0.id == id }?.nom ?? id.abrege) »"
        }
    }
}
