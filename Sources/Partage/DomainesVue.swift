import SwiftUI

/// Les domaines du compte — ceux qu'il possède, et ceux où il tient un droit.
///
/// Sobre, et le même sur l'iPhone et le Mac : une liste (l'alias en titre,
/// le `d-…` et l'hébergeur dessous), un champ pour en créer un.
struct DomainesVue: View {
    @Environment(Session.self) private var session
    @State private var domaines: [Domaine] = []
    @State private var nouvelAlias = ""
    @State private var erreur: String?
    @State private var enCours = false

    var body: some View {
        List {
            if let erreur {
                Section { Text(erreur).foregroundStyle(.red) }
            }
            Section {
                if domaines.isEmpty {
                    Text(TextesDomaines.aucunDomaine).foregroundStyle(.secondary)
                }
                ForEach(domaines) { domaine in
                    NavigationLink {
                        DomaineVue(id: domaine.id)
                    } label: {
                        LigneDomaine(domaine: domaine)
                    }
                }
            }
            Section {
                TextField(TextesDomaines.aliasFacultatif, text: $nouvelAlias)
                Button(TextesDomaines.creer) { Task { await creer() } }
                    .disabled(enCours || (!nouvelAlias.isEmpty && !NomsEtAlias.aliasDeDomaineValide(nouvelAlias)))
            }
        }
        .navigationTitle(TextesDomaines.domaines)
        .task { await charger() }
        .refreshable { await charger() }
    }

    private func charger() async {
        do {
            domaines = try await session.annuaire.domaines()
            erreur = nil
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func creer() async {
        enCours = true
        defer { enCours = false }
        do {
            _ = try await session.annuaire.creerDomaine(alias: nouvelAlias.isEmpty ? nil : nouvelAlias)
            nouvelAlias = ""
            await charger()
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

struct LigneDomaine: View {
    let domaine: Domaine

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(domaine.titre)
            Text("\(domaine.id.texte) · \(TextesDomaines.heberge(domaine.hebergePar))")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

extension TextesDomaines {
    static func heberge(_ hebergeur: Domaine.Hebergeur) -> String {
        switch hebergeur {
        case .racines: hebergeRacines
        case let .annuaire(n): hebergeAnnuaire(n.texte)
        }
    }
}

/// Un domaine : son alias, qui le sert, les machines qui y sont rangées, et
/// les gestes de son propriétaire.
struct DomaineVue: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var fermer
    let id: Identifiant

    @State private var domaine: Domaine?
    @State private var alias = ""
    /// Les annuaires locaux acceptés à qui confier ce domaine (≥ 0.27.0).
    @State private var titulaires: [Identifiant] = []
    @State private var annuairesPossibles = false
    @State private var confirmeSuppression = false
    @State private var erreur: String?

    private var estAMoi: Bool { domaine?.proprietaire == session.compte?.identifiant }

    var body: some View {
        List {
            if let erreur {
                Section { Text(erreur).foregroundStyle(.red) }
            }
            if let domaine {
                Section {
                    LabeledContent("Identifiant", value: domaine.id.texte)
                    Text(TextesDomaines.heberge(domaine.hebergePar)).foregroundStyle(.secondary)
                    if domaine.peut("administrer") {
                        TextField(TextesNoms.alias, text: $alias)
                        HStack {
                            Button("Enregistrer") { Task { await poserAlias(alias) } }
                                .disabled(!NomsEtAlias.aliasDeDomaineValide(alias) || NomsEtAlias.nfc(alias) == domaine.alias)
                            Spacer()
                            if domaine.alias != nil {
                                Button("Retirer", role: .destructive) { Task { await poserAlias(nil) } }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Section(TextesDomaines.machinesRangees) {
                    if domaine.machines.isEmpty {
                        Text(TextesDomaines.aucuneMachine).foregroundStyle(.secondary)
                    }
                    ForEach(domaine.machines) { machine in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(machine.titre)
                            Text(machine.proprietaire == session.compte?.identifiant ? machine.id.texte : "\(machine.id.texte) · \(machine.proprietaire.abrege)")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                // Confier le domaine à son annuaire local, ou le rendre aux
                // racines : le propriétaire seul, et seulement vers un
                // annuaire accepté de ce compte.
                if estAMoi && annuairesPossibles {
                    Section {
                        if case .annuaire = domaine.hebergePar {
                            Button(TextesDomaines.rendreAuxRacines) { Task { await confier(a: nil) } }
                        }
                        ForEach(titulaires.filter { domaine.hebergePar != .annuaire($0) }, id: \.self) { n in
                            Button("\(TextesDomaines.confier) — \(n.abrege)") { Task { await confier(a: n) } }
                        }
                    }
                }

                if estAMoi {
                    Section {
                        Button(TextesDomaines.supprimer, role: .destructive) { confirmeSuppression = true }
                    }
                }
            }
        }
        .navigationTitle(domaine?.titre ?? "")
        .confirmationDialog(TextesDomaines.supprimer, isPresented: $confirmeSuppression, titleVisibility: .visible) {
            Button(TextesDomaines.supprimer, role: .destructive) { Task { await supprimer() } }
        } message: {
            Text(TextesDomaines.confirmerSuppression)
        }
        .task { await charger() }
    }

    private func charger() async {
        do {
            let lu = try await session.annuaire.domaine(id)
            domaine = lu
            alias = lu.alias ?? ""
            annuairesPossibles = (try? await session.annuaire.version())??.porteLesAnnuairesLocaux ?? false
            if annuairesPossibles {
                titulaires = ((try? await session.annuaire.annuairesLocaux()) ?? [])
                    .filter { $0.estTitulaire && $0.etat == .acceptee }.compactMap(\.annuaire)
            }
            erreur = nil
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func poserAlias(_ texte: String?) async {
        do {
            try await session.annuaire.definirAliasDeDomaine(id, alias: texte)
            await charger()
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func confier(a annuaire: Identifiant?) async {
        do {
            try await session.annuaire.confier(domaine: id, a: annuaire)
            await charger()
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func supprimer() async {
        do {
            try await session.annuaire.supprimerDomaine(id)
            fermer()
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

/// Le domaine d'une de MES machines, sur son écran : où elle est rangée, et
/// le geste pour la ranger ailleurs ou l'en retirer.
struct RangementDeMachine: View {
    @Environment(Session.self) private var session
    let machine: Identifiant
    /// Le Mac met l'étiquette dans sa propre colonne.
    var avecEtiquette = true

    @State private var domaines: [Domaine] = []
    @State private var actuel: Domaine?
    @State private var erreur: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if avecEtiquette {
                    Text(TextesDomaines.domaineDeLaMachine)
                    Spacer()
                }
                Menu(actuel?.titre ?? TextesDomaines.aucun) {
                    ForEach(domaines.filter { $0.peut("rattacher") || $0.proprietaire == session.compte?.identifiant }) { domaine in
                        Button(domaine.titre) { Task { await ranger(dans: domaine.id) } }
                    }
                    if actuel != nil {
                        Divider()
                        Button(TextesDomaines.retirerDuDomaine, role: .destructive) { Task { await ranger(dans: nil) } }
                    }
                }
                .fixedSize()
            }
            if let erreur { Text(erreur).font(.footnote).foregroundStyle(.red) }
        }
        .task { await charger() }
    }

    /// L'annuaire ne dit pas, dans l'objet machine, où elle est rangée : on
    /// le retrouve dans le détail des domaines.
    private func charger() async {
        do {
            let liste = try await session.annuaire.domaines()
            var details: [Domaine] = []
            for domaine in liste { details.append((try? await session.annuaire.domaine(domaine.id)) ?? domaine) }
            domaines = details
            actuel = details.first { $0.machines.contains { $0.id == machine } }
            erreur = nil
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func ranger(dans domaine: Identifiant?) async {
        do {
            try await session.annuaire.ranger(machine: machine, dans: domaine)
            await charger()
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}
