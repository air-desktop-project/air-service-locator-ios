import AppKit
import SwiftUI

/// Le panneau sous l'icône : le compte, les machines et leurs services, les
/// appareils — et les trois gestes qu'un Mac fait pour ce produit : enrôler
/// ce Mac, déclarer une machine, enrôler un autre appareil.
///
/// Tout passe par l'interface `Annuaire`, comme sur iPhone. Ce qui diffère
/// est l'idiome : pas d'onglets, pas de caméra — un panneau qui se relit à
/// chaque ouverture, des champs où l'on colle.
struct PanneauVue: View {
    @Environment(Session.self) private var session
    @State private var machines: [Machine] = []
    @State private var appareils: [Appareil] = []
    @State private var erreur: String?
    @State private var enCours = false
    @State private var geste: Geste?

    /// Le geste en cours, s'il y en a un : un seul à la fois, dans un panneau.
    enum Geste: Hashable {
        case rejoindre, declarer, enrolerAppareil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let erreur = erreur ?? session.erreurDeRelecture {
                        Text(erreur).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    }
                    if session.premiereRelectureEnCours {
                        Text("Relecture du compte à l'annuaire — Touch ID prouve la clé de ce Mac.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else if session.compte == nil {
                        sansCompte
                    } else {
                        avecCompte
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 560)
            Divider()
            pied
        }
        .task { await recharger() }
    }

    // MARK: - En-tête et pied

    private var entete: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Service Locator").font(.headline)
                Text(session.compte.map { "compte \($0.identifiant.abrege)" } ?? (session.premiereRelectureEnCours ? "relecture…" : "aucun compte sur ce Mac"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if enCours { ProgressView().controlSize(.small) }
            Button {
                Task { await recharger() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Relire l'annuaire")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var pied: some View {
        HStack {
            Text("Annuaire : nitrogen.air-desktop.org").font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Button("Quitter") { NSApp.terminate(nil) }
                .buttonStyle(.borderless).font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Sans compte

    private var sansCompte: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ce Mac n'est enrôlé sur aucun compte.").font(.callout)
            Text("Un compte est un jeu d'appareils, sans mot de passe. La clé de ce Mac vit dans sa Secure Enclave et signe sous Touch ID ; rien d'autre ne quitte la machine.")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                Task { await ouvrirCompte() }
            } label: {
                Label("Ouvrir un compte avec Touch ID", systemImage: "touchid").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(enCours)
            Depliant("Rejoindre un compte existant", ouvert: lien(.rejoindre)) {
                RejoindreVueMac()
            }
        }
    }

    // MARK: - Avec compte

    private var avecCompte: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let compte = session.compte {
                Titre("Compte")
                LigneCopiableMac(titre: "Identifiant public", texte: compte.identifiant.texte)
                if let alias = compte.alias { LabeledContent("Alias public", value: alias).font(.callout) }
            }

            Titre("Machines")
            if machines.isEmpty {
                Text("Aucune machine. Déclarez-en une pour obtenir son code d'enrôlement.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(machines) { machine in
                MachineVueMac(machine: machine)
            }
            Depliant("Déclarer une machine", ouvert: lien(.declarer)) {
                DeclarerVueMac { await recharger() }
            }

            Titre("Appareils")
            ForEach(appareils) { appareil in
                AppareilVueMac(appareil: appareil)
            }
            Depliant("Enrôler un autre appareil", ouvert: lien(.enrolerAppareil)) {
                EnrolerAppareilVueMac { await recharger() }
            }
        }
    }

    private func lien(_ quel: Geste) -> Binding<Bool> {
        Binding(get: { geste == quel }, set: { geste = $0 ? quel : nil })
    }

    // MARK: - Actions

    private func recharger() async {
        enCours = true
        defer { enCours = false }
        await session.rafraichirCompte()
        guard session.compte != nil else { return }
        do {
            machines = try await session.annuaire.machines()
            appareils = try await session.annuaire.appareils()
            erreur = nil
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func ouvrirCompte() async {
        enCours = true
        defer { enCours = false }
        do {
            try await session.ouvrirCompte()
            erreur = nil
            await recharger()
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

// MARK: - Les morceaux

/// Un titre qu'on clique pour déplier ce qu'il annonce. Toute la ligne
/// répond, pas seulement un triangle : dans un panneau de barre de menus, la
/// cible doit être large.
private struct Depliant<Contenu: View>: View {
    let titre: String
    @Binding var ouvert: Bool
    @ViewBuilder let contenu: () -> Contenu

    init(_ titre: String, ouvert: Binding<Bool>, @ViewBuilder contenu: @escaping () -> Contenu) {
        self.titre = titre
        _ouvert = ouvert
        self.contenu = contenu
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { ouvert.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(ouvert ? 90 : 0))
                    Text(titre).font(.callout)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if ouvert { contenu() }
        }
    }
}

private struct Titre: View {
    let texte: String
    init(_ texte: String) { self.texte = texte }
    var body: some View {
        Text(texte.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
    }
}

/// Un texte en police fixe, avec le bouton pour le copier.
struct LigneCopiableMac: View {
    let titre: String
    let texte: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titre).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top) {
                Text(texte).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(texte, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copier")
            }
        }
    }
}

private struct PastilleMac: View {
    let couleur: Color
    var body: some View { Circle().fill(couleur).frame(width: 8, height: 8) }
}

private struct MachineVueMac: View {
    let machine: Machine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                PastilleMac(couleur: couleur)
                Text(machine.nom).font(.callout.weight(.semibold))
                Spacer()
                Text(cle).font(.caption).foregroundStyle(.secondary)
            }
            if !machine.capacitesTexte.isEmpty {
                Text(machine.capacitesTexte).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(machine.services) { service in
                HStack(spacing: 8) {
                    PastilleMac(couleur: couleurService(service)).padding(.leading, 16)
                    Text(service.nom).font(.system(.caption, design: .monospaced))
                    Text(service.pointsTexte).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(service.libelleEtat) — \(service.detailEtat)").font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            if case let .attendue(.some(code)) = machine.cle, code.estValide(a: .now) {
                LigneCopiableMac(titre: "Sur la machine, tapez", texte: code.commande)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }

    private var couleur: Color {
        if machine.unServiceOscille { return Couleurs.attention }
        if machine.services.contains(where: { if case .annonce = $0.etat { true } else { false } }) { return Couleurs.joignable }
        return Couleurs.parti
    }

    private func couleurService(_ service: Service) -> Color {
        switch service.etat {
        case .annonce:
            switch service.resume {
            case .joignable: Couleurs.joignable
            case .injoignable: Couleurs.attention
            default: Couleurs.accent
            }
        case .parti: Couleurs.parti
        }
    }

    private var cle: String {
        switch machine.cle {
        case let .enrolee(le): le.map { "enrôlée \($0.relatif)" } ?? "enrôlée"
        case let .attendue(code): code.map { $0.estValide(a: .now) ? "code valable" : "code expiré" } ?? "pas de clé"
        case let .revoquee(le, _): "révoquée \(le.relatif)"
        }
    }
}

private struct AppareilVueMac: View {
    let appareil: Appareil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: appareil.estCeluiCi ? "laptopcomputer" : "iphone.gen3")
                .foregroundStyle(appareil.estRevoque ? .tertiary : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(appareil.estCeluiCi ? Host.current().localizedName ?? "Ce Mac" : appareil.nom)
                    .font(.callout).foregroundStyle(appareil.estRevoque ? .secondary : .primary)
                Text(sousTitre).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if appareil.estCeluiCi { Text("ce Mac").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var sousTitre: String {
        if appareil.estRevoque { return appareil.revoqueLe.map { "révoqué le \($0.jour)" } ?? "révoqué" }
        var morceaux = [appareil.enroleLe.map { "enrôlé le \($0.jour)" } ?? "enrôlé"]
        switch appareil.attestation {
        case .apple: morceaux.append("attesté par Apple")
        case .google: morceaux.append("attesté par Google")
        case .aucune: morceaux.append("sans attestation")
        case nil: break
        }
        return morceaux.joined(separator: " · ")
    }
}

/// `POST /v1/machines` : un nom, des capacités, et le code à taper là-bas.
private struct DeclarerVueMac: View {
    @Environment(Session.self) private var session
    let apres: () async -> Void
    @State private var nom = ""
    @State private var annonce = true
    @State private var lecture = false
    @State private var erreur: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Nom, pour vous", text: $nom).textFieldStyle(.roundedBorder)
            Toggle("Annonce — ses daemons peuvent annoncer leurs ports", isOn: $annonce).font(.caption)
            Toggle("Lecture — elle peut demander où joindre un service", isOn: $lecture).font(.caption)
            if let erreur { Text(erreur).font(.caption).foregroundStyle(.red) }
            Button("Déclarer") { Task { await declarer() } }
                .disabled(!Machine.nomValide(nom))
        }
        .padding(.top, 6)
    }

    private func declarer() async {
        var capacites: Set<Capacite> = []
        if annonce { capacites.insert(.annonce) }
        if lecture { capacites.insert(.lecture) }
        do {
            _ = try await session.annuaire.declarerMachine(nom: nom, capacites: capacites)
            nom = ""
            erreur = nil
            await apres()
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

/// Rejoindre, depuis ce Mac : montrer sa clé, coller la réponse.
private struct RejoindreVueMac: View {
    @Environment(Session.self) private var session
    @State private var cle: [UInt8]?
    @State private var reponse = ""
    @State private var erreur: String?
    @State private var enCours = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cle {
                Text("1. Sur le téléphone déjà enrôlé : Compte › Enrôler un autre appareil, et collez-lui cette clé.").font(.caption)
                LigneCopiableMac(titre: "La clé publique de ce Mac", texte: Invitation.cle(cle).texte)
                Text("2. Collez ici sa réponse ; Touch ID prouvera la clé.").font(.caption)
                TextField("asl:appareil:…", text: $reponse).textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
                if let erreur { Text(erreur).font(.caption).foregroundStyle(.red) }
                Button("Rejoindre") { Task { await rejoindre() } }
                    .disabled(enCours || Invitation.analyser(reponse) == nil)
            } else if let erreur {
                Text(erreur).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.top, 6)
        .task {
            do { cle = try session.clePublique() } catch { erreur = "La clé de ce Mac n'a pas pu être créée : \(error.localizedDescription)" }
        }
    }

    private func rejoindre() async {
        guard case let .appareil(compte, appareil)? = Invitation.analyser(reponse) else {
            erreur = "Ce code est une clé, pas une réponse."
            return
        }
        enCours = true
        defer { enCours = false }
        do {
            try await session.rejoindre(compte: compte, appareil: appareil)
            erreur = nil
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

/// `POST /v1/appareils`, depuis ce Mac : coller la clé du nouveau, lui rendre
/// la réponse.
private struct EnrolerAppareilVueMac: View {
    @Environment(Session.self) private var session
    let apres: () async -> Void
    @State private var cle = ""
    @State private var reponse: Invitation?
    @State private var erreur: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reponse {
                Text("L'appareil est enrôlé. Rendez-lui ce code : il rejoindra le compte en prouvant sa clé, là-bas.").font(.caption)
                LigneCopiableMac(titre: "La réponse à lui donner", texte: reponse.texte)
                Button("Terminé") { self.reponse = nil; cle = "" }
            } else {
                Text("Sur le nouveau téléphone : « Rejoindre un compte existant ». Collez ici la clé qu'il montre.").font(.caption)
                TextField("asl:cle:…", text: $cle).textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
                if let erreur { Text(erreur).font(.caption).foregroundStyle(.red) }
                Button("Enrôler") { Task { await enroler() } }
                    .disabled(Invitation.analyser(cle) == nil)
            }
        }
        .padding(.top, 6)
    }

    private func enroler() async {
        guard case let .cle(octets)? = Invitation.analyser(cle), let compte = session.compte else {
            erreur = "Ce code est une réponse, pas une clé."
            return
        }
        do {
            let appareil = try await session.annuaire.enrolerAppareil(cle: octets)
            reponse = .appareil(compte: compte.identifiant, appareil: appareil.id)
            erreur = nil
            await apres()
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}
