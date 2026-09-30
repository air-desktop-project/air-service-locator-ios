import SwiftUI

// Les domaines, sur le Mac : une tuile par domaine, entière et lisible, et
// le détail d'un domaine. Ce qu'on lit est dans les tuiles ; ce qu'on
// modifie a son bouton en regard, et se saisit dans une feuille.

/// Les feuilles de saisie des domaines.
enum FeuilleDomaine: Identifiable {
    case creer
    case nom(Domaine)
    case hebergement(Domaine)
    case ranger(Domaine)

    var id: String {
        switch self {
        case .creer: "creer"
        case let .nom(d): "nom-\(d.id.texte)"
        case let .hebergement(d): "hebergement-\(d.id.texte)"
        case let .ranger(d): "ranger-\(d.id.texte)"
        }
    }
}

/// Ce que les deux pages des domaines relisent : les domaines avec leur
/// détail (pour les machines rangées), les annuaires locaux (pour les
/// adresses et le geste de confier), et si la racine sait confier.
@MainActor
@Observable
final class LectureDesDomaines {
    private(set) var domaines: [Domaine] = []
    private(set) var locaux: [AnnuaireLocal] = []
    private(set) var confierPossible = false
    private(set) var charge = false
    var erreur: String?

    /// Les titulaires acceptés de ce compte : à qui l'on peut confier.
    var titulaires: [AnnuaireLocal] { locaux.filter { $0.estTitulaire && $0.etat == .acceptee } }

    func charger(_ session: Session) async {
        do {
            let liste = try await session.annuaire.domaines()
            var details: [Domaine] = []
            for domaine in liste { details.append((try? await session.annuaire.domaine(domaine.id)) ?? domaine) }
            domaines = details
            confierPossible = (try? await session.annuaire.version())??.porteLesAnnuairesLocaux ?? false
            locaux = confierPossible ? ((try? await session.annuaire.annuairesLocaux()) ?? []) : []
            erreur = nil
        } catch {
            erreur = error.messageAnnuaire
        }
        charge = true
    }

    func domaine(_ id: Identifiant) -> Domaine? { domaines.first { $0.id == id } }
}

// MARK: - La liste

struct DomainesFenetreVue: View {
    @Environment(Session.self) private var session
    @Environment(Donnees.self) private var donnees
    @State private var lecture = LectureDesDomaines()
    @State private var feuille: FeuilleDomaine?

    var body: some View {
        PageFenetre(introduction: "Les domaines que vous possédez, et ceux où l'un de vos groupes tient un droit.") {
            if let erreur = lecture.erreur { Text(erreur).foregroundStyle(Couleurs.Texte.alerte) }
            if lecture.charge && lecture.domaines.isEmpty {
                ContentUnavailableView("Aucun domaine", systemImage: "square.stack.3d.up",
                                       description: Text("Un domaine range vos machines ; créez-en un avec « Créer un domaine… »."))
            }
            ForEach(lecture.domaines) { domaine in
                TuileDomaine(domaine: domaine, lecture: lecture, feuille: $feuille)
            }
        }
        .navigationTitle(TextesDomaines.domaines)
        .navigationDestination(for: Identifiant.self) { id in
            DomaineFenetreVue(id: id, lecture: lecture)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { feuille = .creer } label: { Label("Créer un domaine…", systemImage: "plus") }
                    .labelStyle(.titleAndIcon)
                    .help("Créer un domaine")
            }
        }
        .sheet(item: $feuille) { feuille in
            FeuilleDomaineVue(feuille: feuille, lecture: lecture)
                .environment(session).environment(donnees)
        }
        .task(id: donnees.reluA) { await lecture.charger(session) }
    }
}

/// Un domaine dans la liste : son nom et son rôle, puis chaque donnée
/// entière avec le geste qui la change.
private struct TuileDomaine: View {
    @Environment(Session.self) private var session
    let domaine: Domaine
    let lecture: LectureDesDomaines
    @Binding var feuille: FeuilleDomaine?

    private var estAMoi: Bool { domaine.proprietaire == session.compte?.identifiant }
    // Confier suppose de posséder un domaine ordinaire : le domaine racine,
    // même à son propriétaire, ne donne que « administrer » — il reste aux
    // racines, et le geste ne s'offre pas.

    var body: some View {
        Tuile {
            HStack(spacing: 10) {
                Text(domaine.titre).font(.title3.weight(.semibold)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if domaine.estRacine { Badge(TextesDomaines.domaineRacine, couleur: .secondary) }
                BadgeDeRole(domaine: domaine)
                if domaine.peut("administrer") {
                    Button("Renommer…") { feuille = .nom(domaine) }
                }
                NavigationLink(value: domaine.id) { Text("Ouvrir") }
                    .buttonStyle(.borderedProminent)
            }
            LigneAGeste("Identifiant") { TexteFixe(domaine.id.texte) } geste: { BoutonCopier(domaine.id.texte) }
            LigneAGeste("Hébergé par") {
                ValeurHebergement(domaine: domaine, lecture: lecture)
            } geste: {
                if estAMoi && !domaine.estRacine && domaine.peut("rattacher") && lecture.confierPossible { Button("Changer…") { feuille = .hebergement(domaine) } }
            }
            LigneAGeste(TextesDomaines.machinesRangees) {
                MachinesEnLigne(machines: domaine.machines)
            }
        }
    }
}

/// « Propriétaire », « Administrer », ou les droits tenus.
struct BadgeDeRole: View {
    @Environment(Session.self) private var session
    let domaine: Domaine

    var body: some View {
        if domaine.proprietaire == session.compte?.identifiant {
            Badge("Propriétaire", couleur: Couleurs.accent)
        } else if domaine.peut("administrer") {
            Badge("Administrer", couleur: Couleurs.attention, encre: Couleurs.Texte.attention)
        } else {
            Badge(domaine.droits.joined(separator: " · "), couleur: .secondary)
        }
    }
}

/// Qui sert le domaine, et chacune de ses adresses sur sa ligne.
struct ValeurHebergement: View {
    @Environment(Session.self) private var session
    let domaine: Domaine
    let lecture: LectureDesDomaines

    var body: some View {
        let hebergement = Hebergement(domaine.hebergePar, racines: session.annuaires, locaux: lecture.locaux)
        VStack(alignment: .leading, spacing: 3) {
            switch domaine.hebergePar {
            case .racines:
                Text("Les racines")
                ForEach(hebergement.serveurs) { serveur in
                    TexteFixe("\(serveur.nom) — \(serveur.adresses.joined(separator: " · "))", secondaire: true)
                }
            case let .annuaire(n):
                HStack(spacing: 6) {
                    Text(lecture.locaux.contains { $0.annuaire == n } ? "Mon annuaire local" : "L'annuaire local")
                    TexteFixe(n.texte, secondaire: true)
                }
                ForEach(hebergement.serveurs) { serveur in
                    ForEach(serveur.adresses, id: \.self) { TexteFixe($0, secondaire: true) }
                }
            }
        }
    }
}

/// Les machines d'un domaine, en ligne, chacune avec sa puce.
private struct MachinesEnLigne: View {
    @Environment(Donnees.self) private var donnees
    let machines: [Domaine.MachineRangee]

    var body: some View {
        if machines.isEmpty {
            Text(TextesDomaines.aucuneMachine).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(machines) { machine in
                    HStack(spacing: 6) {
                        PastilleMac(couleur: donnees.machine(machine.id)?.couleur ?? Couleurs.parti)
                        Text(machine.titre)
                    }
                }
            }
        }
    }
}

// MARK: - Le détail

struct DomaineFenetreVue: View {
    @Environment(Session.self) private var session
    @Environment(Donnees.self) private var donnees
    @Environment(\.dismiss) private var retour
    let id: Identifiant
    let lecture: LectureDesDomaines

    @State private var feuille: FeuilleDomaine?
    @State private var aRetirer: Domaine.MachineRangee?
    @State private var confirmeSuppression = false
    @State private var erreur: String?
    /// Les services des machines d'autres comptes (``ServicesDuDomaine``) ;
    /// ceux des miennes viennent de ``Donnees``.
    @State private var servicesDesAutres: [Identifiant: [Service]] = [:]

    private var domaine: Domaine? { lecture.domaine(id) }
    private var moi: Identifiant? { session.compte?.identifiant }

    var body: some View {
        PageFenetre {
            if let erreur { Text(erreur).foregroundStyle(Couleurs.Texte.alerte) }
            if let domaine {
                contenu(domaine)
            } else {
                ContentUnavailableView("Ce domaine n'est plus dans l'annuaire", systemImage: "square.stack.3d.up")
            }
        }
        .navigationTitle(domaine?.titre ?? id.texte)
        .sheet(item: $feuille) { feuille in
            FeuilleDomaineVue(feuille: feuille, lecture: lecture)
                .environment(session).environment(donnees)
        }
        .confirmationDialog("Retirer cette machine du domaine ?", isPresented: Binding(get: { aRetirer != nil }, set: { if !$0 { aRetirer = nil } }), titleVisibility: .visible) {
            if let machine = aRetirer {
                Button("Retirer « \(machine.titre) »", role: .destructive) { Task { await ranger(machine.id, dans: nil) } }
            }
        } message: {
            Text("La machine reste à vous, hors de tout domaine ; ses services ne se résolvent plus sous celui-ci.")
        }
        .confirmationDialog(TextesDomaines.supprimer, isPresented: $confirmeSuppression, titleVisibility: .visible) {
            Button(TextesDomaines.supprimer, role: .destructive) { Task { await supprimer() } }
        } message: {
            Text(TextesDomaines.confirmerSuppression)
        }
        .task(id: domaine) {
            guard let domaine else { return }
            servicesDesAutres = await ServicesDuDomaine.charger(domaine, moi: moi, aussiLesMiennes: false, annuaire: session.annuaire)
        }
    }

    /// Les services d'une machine rangée : les miens, de la dernière
    /// relecture ; ceux d'un autre, si le domaine les montre.
    private func services(de machine: Domaine.MachineRangee) -> [Service]? {
        machine.proprietaire == moi ? donnees.machine(machine.id)?.services : servicesDesAutres[machine.id]
    }

    @ViewBuilder private func contenu(_ domaine: Domaine) -> some View {
        let estAMoi = domaine.proprietaire == moi
        Carte(marges: 16) {
            VStack(alignment: .leading, spacing: 12) {
                LigneAGeste("Nom") {
                    if let alias = domaine.alias {
                        Text(alias).fontWeight(.semibold).textSelection(.enabled)
                    } else {
                        Text(TextesDomaines.pasDAlias).foregroundStyle(.secondary)
                    }
                } geste: {
                    if domaine.peut("administrer") { Button("Modifier…") { feuille = .nom(domaine) } }
                }
                Divider()
                LigneAGeste("Identifiant") { TexteFixe(domaine.id.texte) } geste: { BoutonCopier(domaine.id.texte) }
                Divider()
                LigneAGeste(TextesDomaines.proprietaire) {
                    HStack(spacing: 6) {
                        TexteFixe(domaine.proprietaire.texte)
                        if estAMoi { Text("(\(TextesDomaines.vous))").foregroundStyle(.secondary) }
                    }
                } geste: { BoutonCopier(domaine.proprietaire.texte) }
                Divider()
                LigneAGeste("Hébergé par") {
                    ValeurHebergement(domaine: domaine, lecture: lecture)
                } geste: {
                    if estAMoi && !domaine.estRacine && domaine.peut("rattacher") && lecture.confierPossible { Button("Changer…") { feuille = .hebergement(domaine) } }
                }
                Divider()
                LigneAGeste("Mes droits") {
                    HStack(spacing: 6) { ForEach(domaine.droits, id: \.self) { Badge($0, couleur: Couleurs.accent) } }
                } geste: {
                    Text("tenus par vos groupes").font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        HStack {
            Titre(TextesDomaines.machinesRangees)
            Spacer()
            if domaine.recoitDesMachines {
                Button("Ranger une machine ici…") { feuille = .ranger(domaine) }.controlSize(.small)
            }
        }
        .padding(.top, 8)
        Carte(marges: 0) {
            if domaine.machines.isEmpty {
                Text(TextesDomaines.aucuneMachine).foregroundStyle(.secondary).padding(14)
            }
            ForEach(Array(domaine.machines.enumerated()), id: \.element.id) { indice, machine in
                if indice > 0 { Divider() }
                HStack(spacing: 12) {
                    PastilleMac(couleur: donnees.machine(machine.id)?.couleur ?? Couleurs.parti)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(machine.titre)
                        TexteFixe(machine.proprietaire == moi ? "\(machine.id.texte) · à vous" : "\(machine.id.texte) · \(machine.proprietaire.texte)", secondaire: true)
                        EtatDEchoVue(echo: machine.echo, compact: true).padding(.top, 2)
                        ServicesRangesVue(services: services(de: machine)).padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if machine.proprietaire == moi {
                        Button("Retirer du domaine…") { aRetirer = machine }.controlSize(.small)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }

        if estAMoi && !domaine.estRacine {
            PiedDestructif(explication: "Supprimer détache ses machines ; son alias et ses groupes disparaissent. Votre dernier domaine ne se supprime pas.",
                           titre: "\(TextesDomaines.supprimer)…") { confirmeSuppression = true }
        }
    }

    private func ranger(_ machine: Identifiant, dans domaine: Identifiant?) async {
        do {
            try await session.annuaire.ranger(machine: machine, dans: domaine)
            await lecture.charger(session)
            erreur = nil
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func supprimer() async {
        do {
            try await session.annuaire.supprimerDomaine(id)
            await lecture.charger(session)
            retour()
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

// MARK: - Les feuilles

struct FeuilleDomaineVue: View {
    @Environment(Session.self) private var session
    @Environment(Donnees.self) private var donnees
    @Environment(\.dismiss) private var fermer
    let feuille: FeuilleDomaine
    let lecture: LectureDesDomaines

    @State private var alias = ""
    @State private var hebergeur: Identifiant?
    @State private var machine: Identifiant?
    @State private var enCours = false
    @State private var erreur: String?

    var body: some View {
        switch feuille {
        case .creer:
            FeuilleDeSaisie(titre: "Créer un domaine",
                            explication: "Un domaine range vos machines. Son alias est public et n'est pas unique ; il est facultatif.",
                            action: "Créer", actionPermise: alias.isEmpty || NomsEtAlias.aliasDeDomaineValide(alias),
                            enCours: enCours, erreur: erreur) {
                champAlias
            } valider: {
                faire { _ = try await session.annuaire.creerDomaine(alias: alias.isEmpty ? nil : alias) }
            }
        case let .nom(domaine):
            FeuilleDeSaisie(titre: "Modifier le nom du domaine",
                            explication: "L'alias est public et n'est pas unique : deux domaines peuvent le porter. Espaces et lettres accentuées sont admis.",
                            action: "Enregistrer",
                            actionPermise: NomsEtAlias.aliasDeDomaineValide(alias) && NomsEtAlias.nfc(alias) != domaine.alias,
                            enCours: enCours, erreur: erreur) {
                VStack(alignment: .leading, spacing: 10) {
                    champAlias
                    LigneAGeste("Domaine") { TexteFixe(domaine.id.texte, secondaire: true) }
                }
            } gauche: {
                if domaine.alias != nil {
                    BoutonDestructif("Retirer l'alias") {
                        faire { try await session.annuaire.definirAliasDeDomaine(domaine.id, alias: nil) }
                    }
                }
            } valider: {
                faire { try await session.annuaire.definirAliasDeDomaine(domaine.id, alias: alias) }
            }
            .onAppear { alias = domaine.alias ?? "" }
        case let .hebergement(domaine):
            FeuilleDeSaisie(titre: "Qui sert « \(domaine.titre) » ?",
                            explication: "Les racines, ou l'un de vos annuaires locaux acceptés. Le changement vaut tout de suite pour les machines du domaine.",
                            action: "Enregistrer", actionPermise: hebergeur != hebergeurActuel(domaine), enCours: enCours, erreur: erreur) {
                Picker("Hébergé par", selection: $hebergeur) {
                    Text("Les racines").tag(Identifiant?.none)
                    ForEach(lecture.titulaires) { local in
                        if let n = local.annuaire {
                            Text("Mon annuaire local — \(n.texte) · \(local.adresse)").tag(Identifiant?.some(n))
                        }
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            } valider: {
                faire { try await session.annuaire.confier(domaine: domaine.id, a: hebergeur) }
            }
            .onAppear { hebergeur = hebergeurActuel(domaine) }
        case let .ranger(domaine):
            let candidates = donnees.machines.filter { m in !domaine.machines.contains { $0.id == m.id } }
            FeuilleDeSaisie(titre: "Ranger une machine dans « \(domaine.titre) »",
                            explication: "Une machine n'est rangée que dans un domaine à la fois : la ranger ici la retire de l'autre.",
                            action: "Ranger", actionPermise: machine != nil, enCours: enCours, erreur: erreur) {
                if candidates.isEmpty {
                    Text("Toutes vos machines sont déjà rangées ici.").foregroundStyle(.secondary)
                } else {
                    Picker("Machine", selection: $machine) {
                        ForEach(candidates) { m in Text(m.titre).tag(Identifiant?.some(m.id)) }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    // Le domaine d'un autre compte : ce que le rangement
                    // ouvre se lit AVANT « Ranger ».
                    if domaine.appartientAUnAutre(que: session.compte?.identifiant) {
                        Label(TextesDomaines.ceQueLeRangementOuvre, systemImage: "eye")
                            .foregroundStyle(Couleurs.Texte.attention)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } valider: {
                if let machine { faire { try await session.annuaire.ranger(machine: machine, dans: domaine.id) } }
            }
        }
    }

    private var champAlias: some View {
        LigneAGeste(TextesNoms.alias) {
            TextField(TextesDomaines.aliasFacultatif, text: $alias).textFieldStyle(.roundedBorder)
        }
    }

    private func hebergeurActuel(_ domaine: Domaine) -> Identifiant? {
        if case let .annuaire(n) = domaine.hebergePar { return n }
        return nil
    }

    /// Le geste, puis la relecture ; la feuille se ferme s'il a réussi,
    /// et dit l'erreur sinon.
    private func faire(_ geste: @escaping @MainActor () async throws -> Void) {
        Task {
            enCours = true
            defer { enCours = false }
            do {
                try await geste()
                await lecture.charger(session)
                await donnees.recharger(session)
                fermer()
            } catch {
                erreur = error.messageAnnuaire
            }
        }
    }
}
