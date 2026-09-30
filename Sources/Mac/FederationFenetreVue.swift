import SwiftUI

// Mon annuaire local et l'administration des racines, sur le Mac : une
// tuile par annuaire, une tuile par demande. Ce que l'annuaire fixe se lit ;
// ce qui se change a son bouton en regard, et se saisit dans une feuille.

extension AnnuaireLocal.Etat {
    /// « Acceptée », « En attente »… : l'état en badge, avec sa couleur.
    @MainActor var badge: Badge {
        let texte = TextesDomaines.etat(self)
        let libelle = texte.prefix(1).uppercased() + texte.dropFirst()
        switch self {
        case .acceptee: return Badge(libelle, couleur: Couleurs.joignable, encre: Couleurs.Texte.joignable)
        case .attendue, .enAttente: return Badge(libelle, couleur: Couleurs.attention, encre: Couleurs.Texte.attention)
        case .refusee: return Badge(libelle, couleur: Couleurs.alerte, encre: Couleurs.Texte.alerte)
        case .retiree, .inconnu: return Badge(libelle, couleur: .secondary)
        }
    }
}

// MARK: - Mon annuaire local

extension EtatDeLAnnuaire {
    /// Vivant, parti, pas de nouvelles : en badge, avec sa couleur.
    @MainActor var badge: Badge {
        switch self {
        case .vivant: Badge(TextesDomaines.vivant, couleur: Couleurs.joignable, encre: Couleurs.Texte.joignable)
        case .parti: Badge(TextesDomaines.parti, couleur: Couleurs.attention, encre: Couleurs.Texte.attention)
        case .pasDeNouvelles: Badge(TextesDomaines.pasDeNouvelles, couleur: .secondary)
        }
    }
}

/// « Voie ouverte », « Voie tombée », ou « — » : la voie d'un membre vers
/// la racine qui répond.
struct EtiquetteDeVoie: View {
    let voie: AnnuaireLocal.Voie?

    var body: some View {
        HStack(spacing: 4) {
            switch voie {
            case .ouverte: PastilleMac(couleur: Couleurs.joignable)
            case .tombee: PastilleMac(couleur: Couleurs.attention)
            default: EmptyView()
            }
            Text(TextesDomaines.voie(voie)).foregroundStyle(couleur)
        }
        .font(.callout)
        .fixedSize()
    }

    /// Ouverte en vert, tombée en orange, inconnue en gris — la teinte
    /// lisible, puisque c'est un mot et non la pastille.
    private var couleur: Color {
        switch voie {
        case .ouverte: Couleurs.Texte.joignable
        case .tombee: Couleurs.Texte.attention
        default: .secondary
        }
    }
}

/// Les feuilles de l'annuaire local.
enum FeuilleAnnuaire: Identifiable {
    /// Déclarer un annuaire (`nil`) ou le second membre d'un titulaire.
    case declarer(titulaire: Identifiant?)
    case confier(annuaire: Identifiant)

    var id: String {
        switch self {
        case let .declarer(titulaire): "declarer-\(titulaire?.texte ?? "")"
        case let .confier(n): "confier-\(n.texte)"
        }
    }
}

struct AnnuaireLocalFenetreVue: View {
    @Environment(Session.self) private var session
    @Environment(Donnees.self) private var donnees
    @State private var locaux: [AnnuaireLocal] = []
    @State private var domaines: [Domaine] = []
    @State private var charge = false
    @State private var feuille: FeuilleAnnuaire?
    @State private var aRetirer: Identifiant?
    @State private var secondARetirer: (membre: Identifiant, annuaire: Identifiant)?
    @State private var erreur: String?

    /// Les titulaires, sauf ceux qu'on a retirés : une paire retirée ne se
    /// gère plus.
    private var titulaires: [AnnuaireLocal] { locaux.filter { $0.estTitulaire && $0.etat != .retiree } }
    /// Les déclarations dont la machine n'a pas encore présenté le code.
    private var declarations: [AnnuaireLocal] { locaux.filter { $0.membre == nil && $0.annuaire == nil && $0.etat == .attendue } }

    var body: some View {
        PageFenetre(introduction: "Une machine de votre compte qui sert elle-même vos domaines, inscrite auprès des racines. Une paire tient au plus deux membres : le titulaire et son secours.") {
            if let erreur { Text(erreur).foregroundStyle(Couleurs.Texte.alerte) }
            if charge && titulaires.isEmpty && declarations.isEmpty {
                ContentUnavailableView("Aucun annuaire local", systemImage: "server.rack",
                                       description: Text("Déclarez-en un avec « Déclarer un annuaire local… » : l'application donne le code que la machine présentera aux racines."))
            }
            ForEach(titulaires) { titulaire in tuile(titulaire) }
            ForEach(declarations) { declaration in
                Tuile {
                    HStack {
                        Text("Déclaration en attente de présentation").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        declaration.etat.badge
                    }
                    LigneAGeste("Adresse") { TexteFixe(declaration.adresse) } geste: { BoutonCopier(declaration.adresse) }
                    if let expire = declaration.expireLe {
                        LigneAGeste("Code") { Text("expire \(expire.relatif)") }
                    }
                    Text("La machine n'a pas encore présenté son code. Un code perdu se remplace par une nouvelle déclaration.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(TextesDomaines.annuaireLocal)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { feuille = .declarer(titulaire: nil) } label: { Label("Déclarer un annuaire local…", systemImage: "plus") }
                    .labelStyle(.titleAndIcon)
                    .help("Déclarer un annuaire local — obtenir le code que la machine présentera")
            }
        }
        .sheet(item: $feuille) { feuille in
            FeuilleAnnuaireVue(feuille: feuille, domaines: domaines) { await charger() }
                .environment(session).environment(donnees)
        }
        .confirmationDialog(TextesDomaines.retirer, isPresented: Binding(get: { aRetirer != nil }, set: { if !$0 { aRetirer = nil } }), titleVisibility: .visible) {
            Button(TextesDomaines.retirer, role: .destructive) {
                if let aRetirer { Task { await faire { try await session.annuaire.retirerAnnuaire(aRetirer) } } }
            }
        } message: {
            Text(TextesDomaines.confirmerRetrait)
        }
        .confirmationDialog("Retirer le second membre ?", isPresented: Binding(get: { secondARetirer != nil }, set: { if !$0 { secondARetirer = nil } }), titleVisibility: .visible) {
            Button("Retirer le second membre", role: .destructive) {
                if let second = secondARetirer { Task { await faire { try await session.annuaire.retirerMembre(second.membre, de: second.annuaire) } } }
            }
        } message: {
            Text("La paire reste, servie par son titulaire seul, sans secours.")
        }
        .task(id: donnees.reluA) { await charger() }
    }

    @ViewBuilder private func tuile(_ titulaire: AnnuaireLocal) -> some View {
        let n = titulaire.annuaire ?? titulaire.membre
        let seconds = locaux.filter { $0.annuaire == n && $0.membre != n && $0.etat != .retiree }
        let servis = domaines.filter { n.map { .annuaire($0) } == $0.hebergePar }
        let membres = [titulaire] + seconds
        let etat = EtatDeLAnnuaire(membres: membres)
        let fautes = membres.compactMap(TextesDomaines.paireFautive)
        Tuile {
            HStack(spacing: 10) {
                Image(systemName: "server.rack").foregroundStyle(.secondary)
                Text("Titulaire de la paire").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                // L'annuaire, tel que la racine qui répond le voit ; puis
                // l'inscription du titulaire.
                if titulaire.etat == .acceptee { etat.badge }
                titulaire.etat.badge
            }
            if let membre = titulaire.membre {
                LigneAGeste("Identifiant") { TexteFixe(membre.texte) } geste: { BoutonCopier(membre.texte) }
            }
            LigneAGeste("Adresse") {
                HStack(spacing: 10) {
                    TexteFixe(titulaire.adresse)
                    if titulaire.etat == .acceptee { EtiquetteDeVoie(voie: titulaire.voie) }
                }
            } geste: { BoutonCopier(titulaire.adresse) }
            LigneAGeste("Second membre") {
                if seconds.isEmpty {
                    Text("aucun — la paire n'a pas de secours").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(seconds) { second in
                            HStack(spacing: 8) {
                                TexteFixe(second.membre?.texte ?? second.adresse)
                                second.etat.badge
                            }
                            if second.membre != nil {
                                HStack(spacing: 10) {
                                    TexteFixe(second.adresse, secondaire: true)
                                    if second.etat == .acceptee { EtiquetteDeVoie(voie: second.voie) }
                                }
                            }
                        }
                    }
                }
            } geste: {
                if let n, titulaire.etat == .acceptee {
                    if let second = seconds.first(where: { $0.membre != nil }), let membre = second.membre {
                        Button("Retirer…") { secondARetirer = (membre, n) }
                    } else if seconds.isEmpty {
                        Button("Déclarer…") { feuille = .declarer(titulaire: n) }
                    }
                }
            }
            // La paire : réglée, ou mal réglée — dit, avec quoi faire. Rien
            // pour un titulaire seul, ni tant que la racine n'en sait rien.
            if !fautes.isEmpty {
                LigneAGeste("Paire") {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(TextesDomaines.paireMalReglee, systemImage: "exclamationmark.triangle.fill").fontWeight(.semibold)
                        ForEach(fautes, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
                    }
                    .foregroundStyle(Couleurs.Texte.alerte)
                }
            } else if membres.contains(where: { $0.paire == .reglee }) {
                LigneAGeste("Paire") {
                    Label(TextesDomaines.paireReglee, systemImage: "checkmark").font(.callout).foregroundStyle(.secondary)
                }
            }
            LigneAGeste("Domaines servis") {
                if servis.isEmpty {
                    Text("aucun").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 3) { ForEach(servis) { Text($0.titre) } }
                }
            } geste: {
                if let n, titulaire.etat == .acceptee { Button("Confier un domaine…") { feuille = .confier(annuaire: n) } }
            }
            Text("L'identifiant et l'adresse sont ceux que la machine a présentés à l'inscription : l'annuaire ne les laisse pas modifier. Changer de machine ou d'adresse, c'est retirer l'annuaire puis en déclarer un nouveau ; entre-temps, ses domaines reviennent aux racines.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let n {
                PiedDestructif(explication: TextesDomaines.confirmerRetrait, titre: "\(TextesDomaines.retirer)…") { aRetirer = n }
            }
        }
    }

    private func charger() async {
        do {
            locaux = try await session.annuaire.annuairesLocaux()
            domaines = (try? await session.annuaire.domaines()) ?? []
            erreur = nil
        } catch {
            erreur = error.messageAnnuaire
        }
        charge = true
    }

    private func faire(_ geste: @MainActor () async throws -> Void) async {
        do {
            try await geste()
            await charger()
            await donnees.recharger(session)
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

/// Déclarer (un annuaire, ou le second membre) puis montrer le code et la
/// commande ; ou confier un domaine à cet annuaire.
private struct FeuilleAnnuaireVue: View {
    @Environment(Session.self) private var session
    @Environment(Donnees.self) private var donnees
    @Environment(\.dismiss) private var fermer
    let feuille: FeuilleAnnuaire
    let domaines: [Domaine]
    let relire: @MainActor () async -> Void

    @State private var adresse = ""
    @State private var code: CodeInscription?
    @State private var domaine: Identifiant?
    @State private var enCours = false
    @State private var erreur: String?

    var body: some View {
        switch feuille {
        case let .declarer(titulaire):
            if let code {
                codeObtenu(code)
            } else {
                FeuilleDeSaisie(titre: titulaire == nil ? "Déclarer un annuaire local" : "Déclarer le second membre de la paire",
                                explication: titulaire == nil
                                    ? "L'application demande aux racines un code d'inscription, que la machine présentera avec sa clé d'identité."
                                    : "Le secours de la paire : une seconde machine, qui présentera ce code avec SA clé.",
                                action: "Déclarer", actionPermise: NomsEtAlias.adresseValide(adresse), enCours: enCours, erreur: erreur) {
                    VStack(alignment: .leading, spacing: 4) {
                        LigneAGeste(TextesDomaines.adresse) {
                            TextField("[2001:db8::1]:6630", text: $adresse).textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }
                        Text(TextesDomaines.adresseAide).font(.caption).foregroundStyle(.secondary).padding(.leading, 144)
                    }
                } valider: {
                    Task { await declarer(titulaire) }
                }
            }
        case let .confier(n):
            // Jamais le domaine racine : il ne se confie pas.
            let candidats = domaines.filter { $0.proprietaire == session.compte?.identifiant && !$0.estRacine && $0.hebergePar != .annuaire(n) }
            FeuilleDeSaisie(titre: "Confier un domaine à cet annuaire",
                            explication: "Il servira le domaine choisi à la place des racines ; le rendre aux racines se fait depuis le domaine.",
                            action: "Confier", actionPermise: domaine != nil, enCours: enCours, erreur: erreur) {
                if candidats.isEmpty {
                    Text("Tous vos domaines sont déjà servis par cet annuaire.").foregroundStyle(.secondary)
                } else {
                    Picker("Domaine", selection: $domaine) {
                        ForEach(candidats) { Text($0.titreComplet).tag(Identifiant?.some($0.id)) }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
            } valider: {
                guard let domaine else { return }
                Task {
                    enCours = true
                    defer { enCours = false }
                    do {
                        try await session.annuaire.confier(domaine: domaine, a: n)
                        await relire()
                        fermer()
                    } catch {
                        erreur = error.messageAnnuaire
                    }
                }
            }
        }
    }

    private func codeObtenu(_ code: CodeInscription) -> some View {
        let commande = TextesDomaines.commande(code: code.code, racine: session.annuaireChoisi?.pourLaLigneDeCommande ?? session.annuaire.nom)
        return VStack(alignment: .leading, spacing: 14) {
            Text(TextesDomaines.codeTitre).font(.title3.weight(.semibold))
            Carte(marges: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(code.code).font(.system(size: 26, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                        Spacer()
                        Text("expire \(code.expireLe.relatif)").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(commande).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        BoutonCopier(commande).controlSize(.small)
                    }
                    .padding(8)
                    .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    Text(TextesDomaines.codeAide).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack { Spacer(); Button("Fermer") { fermer() }.keyboardShortcut(.defaultAction) }
        }
        .padding(22)
        .frame(width: 560)
    }

    private func declarer(_ titulaire: Identifiant?) async {
        enCours = true
        defer { enCours = false }
        do {
            if let titulaire {
                code = try await session.annuaire.declarerSecondMembre(de: titulaire, adresse: adresse)
            } else {
                code = try await session.annuaire.declarerAnnuaire(adresse: adresse)
            }
            erreur = nil
            await relire()
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

// MARK: - L'administration des racines

struct AdministrationFenetreVue: View {
    @Environment(Session.self) private var session
    @Environment(Donnees.self) private var donnees
    @State private var inscriptions: [Inscription] = []
    @State private var charge = false
    @State private var aDecider: (Inscription, Bool)?
    @State private var erreur: String?

    var body: some View {
        Group {
            if charge && inscriptions.isEmpty && erreur == nil {
                ContentUnavailableView("Aucune inscription en attente", systemImage: "checkmark.shield",
                                       description: Text("Quand un annuaire local demande à être inscrit auprès des racines, sa demande apparaît ici pour être acceptée ou refusée."))
            } else {
                PageFenetre(introduction: "Les annuaires locaux qui demandent à être inscrits auprès des racines. Chaque décision demande confirmation.") {
                    if let erreur { Text(erreur).foregroundStyle(Couleurs.Texte.alerte) }
                    ForEach(inscriptions) { tuile($0) }
                }
            }
        }
        .navigationTitle(TextesDomaines.administration)
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
        .task(id: donnees.reluA) { await charger() }
    }

    private func tuile(_ inscription: Inscription) -> some View {
        let titulaire = inscription.membre == inscription.annuaire
        return Tuile {
            HStack {
                Text(titulaire ? "Titulaire d'une nouvelle paire" : "Second membre d'une paire").font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                AnnuaireLocal.Etat.enAttente.badge
            }
            LigneAGeste("Membre") { TexteFixe(inscription.membre.texte) } geste: { BoutonCopier(inscription.membre.texte) }
            if !titulaire {
                LigneAGeste("Titulaire") { TexteFixe(inscription.annuaire.texte) } geste: { BoutonCopier(inscription.annuaire.texte) }
            }
            LigneAGeste("Adresse") { TexteFixe(inscription.adresse) } geste: { BoutonCopier(inscription.adresse) }
            LigneAGeste("Demandé par") { TexteFixe(inscription.proprietaire.texte) } geste: { BoutonCopier(inscription.proprietaire.texte) }
            Divider()
            HStack(spacing: 8) {
                Spacer()
                BoutonDestructif("\(TextesDomaines.refuser)…") { aDecider = (inscription, false) }
                Button("\(TextesDomaines.accepter)…") { aDecider = (inscription, true) }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func charger() async {
        do {
            inscriptions = try await session.annuaire.inscriptions() ?? []
            donnees.inscriptionsRelues(inscriptions.count)
            erreur = nil
        } catch {
            erreur = error.messageAnnuaire
        }
        charge = true
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
