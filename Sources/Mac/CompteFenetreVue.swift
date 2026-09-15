import AppKit
import SwiftUI

/// Le compte : l'identifiant en entier, l'alias, l'annuaire — et les
/// appareils, parce que c'est l'écran qu'on regarde pour vérifier qu'aucun
/// appareil de trop n'est entré.
struct CompteFenetreVue: View {
    @Environment(Session.self) private var session
    @Environment(Donnees.self) private var donnees
    @State private var editeAlias = false
    @State private var alias = ""
    @State private var erreur: String?
    @State private var enCours = false

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
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Compte")
    }

    private var versionDeLAnnuaire: String {
        switch donnees.versionAnnuaire {
        case .some(.some(let version)): " — version \(version)"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Titre("Appareils")
                Spacer()
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
                ForEach(Array(donnees.appareils.enumerated()), id: \.element.id) { indice, appareil in
                    if indice > 0 { Divider() }
                    ligne(appareil)
                }
                if donnees.appareils.isEmpty {
                    Text("Aucun appareil.").foregroundStyle(.secondary).padding(12)
                }
            }
            Text("L'annuaire ne connaît de chaque appareil que son identifiant : c'est lui qui dit si un appareil est bien l'un des vôtres. Un appareil que vous ne reconnaissez pas se révoque ; il reste dans la liste, marqué. Un appareil ne peut pas se révoquer lui-même.")
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
        switch appareil.attestation {
        case .apple: morceaux.append("attesté par Apple")
        case .google: morceaux.append("attesté par Google")
        case .aucune: morceaux.append("sans attestation")
        case nil: break
        }
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
