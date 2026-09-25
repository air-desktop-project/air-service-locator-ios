import AppKit
import SwiftUI

/// Le compte : l'identifiant en entier, l'alias, l'annuaire — et les
/// appareils, parce que c'est l'écran qu'on regarde pour vérifier qu'aucun
/// appareil de trop n'est entré.
struct CompteFenetreVue: View {
    @Environment(Session.self) private var session
    @Environment(Donnees.self) private var donnees
    @Environment(MachineDeCeMac.self) private var machineDeCeMac: MachineDeCeMac?
    @State private var editeAlias = false
    @State private var alias = ""
    @State private var erreur: String?
    @State private var enCours = false
    @State private var confirmeEffacement = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let erreur { Text(erreur).font(.callout).foregroundStyle(.red) }
                if let compte = session.compte {
                    Carte {
                        Champ("Identifiant public") { Copiable(compte.identifiant.texte) }
                        Champ("Alias public") {
                            if editeAlias {
                                HStack {
                                    TextField("alias", text: $alias).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                                    Button("Enregistrer") { Task { await definirAlias(alias.isEmpty ? nil : alias) } }.disabled(enCours)
                                    Button("Annuler") { editeAlias = false }
                                }
                            } else {
                                HStack(spacing: 8) {
                                    if let alias = compte.alias {
                                        Text(alias)
                                    } else {
                                        Text("aucun").foregroundStyle(.secondary)
                                        Text("— sans alias, seul l'identifiant vous rend trouvable").foregroundStyle(.secondary)
                                    }
                                    Button(compte.alias == nil ? "Choisir" : "Changer") { alias = compte.alias ?? ""; editeAlias = true }
                                        .buttonStyle(.link).font(.callout)
                                }
                            }
                        }
                        Champ("Annuaire") {
                            Text("\(session.annuaire.nom)\(versionDeLAnnuaire) — racines air-desktop-project")
                        }
                    }
                }
                AppareilsSection()
                NotificationsSection()
                // Le dernier acte d'une clé (`modele.md` §2.1) : tout en bas,
                // derrière une confirmation qui dit ce qui part. Sur le Mac,
                // l'identité de machine part avec — sa clé est révoquée.
                VStack(alignment: .leading, spacing: 8) {
                    Titre("Effacer le compte")
                    HStack(spacing: 12) {
                        Button("Effacer mon compte", role: .destructive) { confirmeEffacement = true }.disabled(enCours)
                        if enCours { ProgressView().controlSize(.small) }
                    }
                    Text("Tout part : vos appareils, vos machines et leurs services, vos accès donnés et reçus, votre alias — et l'identité de machine de ce Mac. Rien ne revient. Un compte dont le dernier appareil est révoqué s'efface de lui-même à trente jours.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Compte")
        .confirmationDialog("Effacer ce compte ?", isPresented: $confirmeEffacement, titleVisibility: .visible) {
            Button("Effacer mon compte", role: .destructive) { Task { await effacer() } }
        } message: {
            Text("Vos appareils, vos machines et leurs services, vos accès donnés et reçus, votre alias, l'identité de machine de ce Mac — tout part, et rien ne revient.")
        }
    }

    private func effacer() async {
        enCours = true
        defer { enCours = false }
        do {
            let machine = machineDeCeMac
            try await session.effacerCompte { try machine?.oublier() }
            erreur = nil
            await donnees.recharger(session)
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private var versionDeLAnnuaire: String {
        switch donnees.versionAnnuaire {
        case .some(.some(let annuaire)): " — version \(annuaire.version)"
        case .some(.none): " — version inconnue"
        case .none: ""
        }
    }

    private func definirAlias(_ alias: String?) async {
        enCours = true
        defer { enCours = false }
        do {
            try await session.definirAlias(alias)
            editeAlias = false
            erreur = nil
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

/// La page Appareils : la même liste que sous le compte, seule.
struct AppareilsFenetreVue: View {
    @Environment(Session.self) private var session
    @Environment(Donnees.self) private var donnees

    var body: some View {
        ScrollView {
            AppareilsSection()
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Appareils")
    }
}

/// Les appareils du compte, chacun avec son `a-…` en entier : c'est lui qui
/// identifie, l'étiquette (modèle, plate-forme) ne fait que reconnaître.
struct AppareilsSection: View {
    @Environment(Session.self) private var session
    @Environment(Donnees.self) private var donnees
    @Environment(GestesDuPanneau.self) private var gestes
    @Environment(MachineDeCeMac.self) private var machineDeCeMac: MachineDeCeMac?
    @State private var aRevoquer: Appareil?
    @State private var erreur: String?
    /// Les révoqués ne s'affichent pas par défaut : ils restent dans
    /// l'annuaire, marqués, mais une liste qui les mêle aux vivants dit mal
    /// combien d'appareils tiennent le compte. Le réglage est retenu.
    @AppStorage("appareils.revoques.visibles") private var revoquesVisibles = false

    /// Ce qu'on montre : tous, ou les vivants seulement.
    private var appareilsMontres: [Appareil] {
        revoquesVisibles ? donnees.appareils : donnees.appareils.filter { !$0.estRevoque }
    }

    private var nombreDeRevoques: Int { donnees.appareils.filter(\.estRevoque).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Titre("Appareils")
                Spacer()
                if nombreDeRevoques > 0 {
                    Toggle(isOn: $revoquesVisibles) {
                        Text("Voir les révoqués (\(nombreDeRevoques))")
                    }
                    .toggleStyle(.switch).controlSize(.small)
                }
                Button {
                    gestes.enCours = gestes.enCours == .enrolerAppareil ? nil : .enrolerAppareil
                } label: {
                    Label("Enrôler un autre appareil", systemImage: "plus")
                }
                .controlSize(.small)
            }
            if gestes.enCours == .enrolerAppareil {
                Carte(fond: Color(nsColor: .controlBackgroundColor)) {
                    EnrolerAppareilVueMac { await donnees.recharger(session) }
                }
            }
            if let erreur { Text(erreur).font(.callout).foregroundStyle(.red) }
            Carte(marges: 0) {
                ForEach(Array(appareilsMontres.enumerated()), id: \.element.id) { indice, appareil in
                    if indice > 0 { Divider() }
                    ligne(appareil)
                }
                if appareilsMontres.isEmpty {
                    Text("Aucun appareil.").foregroundStyle(.secondary).padding(12)
                }
            }
            Text("L'annuaire ne connaît de chaque appareil que son identifiant : c'est lui qui dit si un appareil est bien l'un des vôtres. Un appareil que vous ne reconnaissez pas se révoque ; il reste dans l'annuaire, marqué, et « Voir les révoqués » le montre. Un appareil ne peut pas se révoquer lui-même.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog("Révoquer \(aRevoquer?.titre ?? "cet appareil") ?", isPresented: Binding(get: { aRevoquer != nil }, set: { if !$0 { aRevoquer = nil } }), titleVisibility: .visible) {
            Button("Révoquer", role: .destructive) { if let aRevoquer { Task { await revoquer(aRevoquer) } } }
        } message: {
            Text("Cet appareil ne pourra plus administrer le compte. Il reste dans la liste, marqué.")
        }
    }

    private func ligne(_ appareil: Appareil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icone(appareil)).font(.title3)
                .foregroundStyle(appareil.estRevoque ? Color.secondary : Couleurs.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(appareil.estCeluiCi ? (Host.current().localizedName ?? appareil.titre) : appareil.titre)
                        .font(.body.weight(.medium))
                        .foregroundStyle(appareil.estRevoque ? .secondary : .primary)
                    if appareil.estCeluiCi { Text("cet appareil").font(.caption).foregroundStyle(.secondary) }
                    if appareil.estRevoque {
                        Text("révoqué").font(.caption.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(sousTitre(appareil)).font(.caption).foregroundStyle(.secondary)
                Copiable(appareil.id.texte)
            }
            Spacer()
            if !appareil.estRevoque && !appareil.estCeluiCi {
                Button("Révoquer", role: .destructive) { aRevoquer = appareil }.controlSize(.small)
            }
        }
        .padding(12)
    }

    private func icone(_ appareil: Appareil) -> String {
        switch appareil.estCeluiCi ? .macos : appareil.description?.plateforme {
        case .macos: "laptopcomputer"
        case .android: "candybarphone"
        case .ios, nil: "iphone.gen3"
        }
    }

    private func sousTitre(_ appareil: Appareil) -> String {
        if appareil.estRevoque { return appareil.revoqueLe.map { "révoqué le \($0.jour)" } ?? "révoqué" }
        var morceaux = [appareil.enroleLe.map { "enrôlé le \($0.jour)" } ?? "enrôlé"]
        if appareil.estCeluiCi { morceaux.append("Touch ID") }
        if let attestation = appareil.attestation { morceaux.append(attestation.libelle) }
        if let plateforme = appareil.description?.plateforme { morceaux.append(plateforme.libelle) }
        if appareil.estCeluiCi, let machine = donnees.machine(machineDeCeMac?.identifiant ?? appareil.id) {
            morceaux.append("aussi la machine « \(machine.nom) »")
        }
        return morceaux.joined(separator: " · ")
    }

    private func revoquer(_ appareil: Appareil) async {
        do {
            try await session.annuaire.revoquerAppareil(appareil.id)
            erreur = nil
            await donnees.recharger(session)
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

/// Les notifications de ce Mac : ce qu'elles sont, et le geste qui les
/// active — le seul endroit où la permission se demande
/// (``NotificationsMac``).
struct NotificationsSection: View {
    @Environment(Donnees.self) private var donnees

    private var notifications: NotificationsMac { donnees.notifications }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Titre("Notifications")
            Carte {
                HStack(spacing: 12) {
                    switch notifications.etat {
                    case .inconnu:
                        ProgressView().controlSize(.small)
                    case .aDemander:
                        Button("Activer") { Task { await notifications.activer() } }
                        Text("Désactivées").foregroundStyle(.secondary)
                    case .enAttente:
                        Label("En attente de votre réponse", systemImage: "hourglass").foregroundStyle(Couleurs.attention)
                        Text("— macOS affiche une demande en haut à droite de l'écran").foregroundStyle(.secondary)
                    case .autorisees:
                        Label("Activées", systemImage: "bell.badge").foregroundStyle(Couleurs.accent)
                    case .refusees:
                        Label("Refusées", systemImage: "bell.slash").foregroundStyle(.secondary)
                        Text("— se réactivent dans Réglages Système › Notifications").foregroundStyle(.secondary)
                    }
                }
            }
            Text(TextesNouveautes.explication).font(.caption).foregroundStyle(.secondary)
        }
        .task { await notifications.relireEtat() }
        // Un « Autoriser » cliqué dans la bannière, ou un réglage changé dans
        // Réglages Système, se voit au retour dans l'application — sans la
        // relancer.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await notifications.relireEtat() }
        }
    }
}
