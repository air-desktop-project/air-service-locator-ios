import AppKit
import SwiftUI

/// Une machine, avec tout ce qu'on en sait — et rien de tronqué.
///
/// L'identifiant en entier, les capacités en toutes lettres, la clé et sa
/// date, le lien avec l'appareil quand cette machine est ce Mac, les
/// services avec leurs points, leur état et le verdict de la sonde, la
/// commande `asl` complète, et les gestes : renommer, changer les capacités,
/// émettre un code, révoquer la clé.
struct MachineFenetreVue: View {
    @Environment(Session.self) private var session
    @Environment(Donnees.self) private var donnees
    @Environment(MachineDeCeMac.self) private var machineDeCeMac: MachineDeCeMac?
    let machine: Machine

    @State private var renomme = false
    @State private var nouveauNom = ""
    @State private var changeCapacites = false
    @State private var annonce = false
    @State private var lecture = false
    @State private var confirmeRevocation = false
    @State private var erreur: String?
    @State private var enCours = false

    private var estCeMac: Bool { machine.id == machineDeCeMac?.identifiant }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                entete
                if let erreur { Text(erreur).font(.callout).foregroundStyle(.red) }
                Carte {
                    Champ("Identifiant") { Copiable(machine.id.texte) }
                    Champ("Nom, pour vous") {
                        if renomme {
                            HStack {
                                TextField("Nom", text: $nouveauNom).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                                Button("Enregistrer") { Task { await modifier(nom: nouveauNom, capacites: nil) } }
                                    .disabled(!Machine.nomValide(nouveauNom) || enCours)
                                Button("Annuler") { renomme = false }
                            }
                        } else {
                            Text(machine.nom)
                        }
                    }
                    Champ("Capacités") {
                        if changeCapacites {
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle("Annonce — ses daemons peuvent annoncer leurs ports", isOn: $annonce)
                                Toggle("Lecture — elle peut demander où joindre un service", isOn: $lecture)
                                HStack {
                                    Button("Enregistrer") { Task { await modifier(nom: nil, capacites: capacitesChoisies) } }.disabled(enCours)
                                    Button("Annuler") { changeCapacites = false }
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                if machine.capacites.contains(.annonce) { Text("annonce — ses daemons peuvent annoncer leurs ports") }
                                if machine.capacites.contains(.lecture) { Text("lecture — elle peut demander où joindre un service") }
                                if machine.capacites.isEmpty { Text("aucune").foregroundStyle(.secondary) }
                            }
                        }
                    }
                    Champ("Clé") {
                        HStack(spacing: 8) {
                            PastilleMac(couleur: couleurCle)
                            Text(texteCle)
                        }
                    }
                    if estCeMac, let moi = Carnet.appareilEnrole {
                        Champ("Aussi l'appareil") {
                            let description = donnees.appareils.first { $0.id == moi }?.description
                            Copiable(moi.texte, suite: description.map { " — \($0.modele) · \($0.plateforme.libelle)" } ?? "")
                        }
                    }
                }
                if case let .attendue(.some(code)) = machine.cle, code.estValide(a: .now) {
                    Carte(fond: Color(nsColor: .controlBackgroundColor)) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Code d'enrôlement — valable \(code.reste(a: .now).minutes)").font(.headline)
                            Text("Sur la machine, tapez :").font(.callout).foregroundStyle(.secondary)
                            Copiable(code.commande)
                            Text("Dix symboles, à usage unique, dix minutes. L'annuaire n'en garde que l'empreinte ; le code n'ouvre qu'une opération, lier une clé.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(4)
                    }
                }
                services
                if estCeMac, let dossier = MachineDeCeMac.dossierPourAsl {
                    VStack(alignment: .leading, spacing: 8) {
                        Titre("Pour l'utilitaire asl, dans un terminal")
                        Carte(fond: Color(nsColor: .controlBackgroundColor)) {
                            HStack(spacing: 10) {
                                Image(systemName: "terminal").foregroundStyle(.secondary)
                                Copiable("asl --etat \"\(dossier)\" annonce <service> tcp:<port>")
                            }
                            .padding(4)
                        }
                    }
                }
                gestes
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(machine.nom)
        .confirmationDialog("Révoquer la clé de « \(machine.nom) » ?", isPresented: $confirmeRevocation, titleVisibility: .visible) {
            Button("Révoquer la clé", role: .destructive) { Task { await revoquerCle() } }
        } message: {
            Text("Effet immédiat : ses connexions sont fermées, ses baux tombent. La machine reste — son nom, ses capacités, ses services — et un nouveau code la ré-enrôle.")
        }
    }

    private var entete: some View {
        HStack(spacing: 12) {
            PastilleMac(couleur: machine.couleur, taille: 10)
            Text(machine.nom).font(.title.weight(.bold))
            if estCeMac {
                Text("ce Mac").font(.caption.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Couleurs.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(Couleurs.accent)
            }
            Text(machine.capacitesTexte).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var services: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Titre("Services")
                Spacer()
                if let relu = donnees.reluA {
                    Text("relu \(relu.relatif) · les états viennent de l'annuaire").font(.caption).foregroundStyle(.secondary)
                }
            }
            Carte(marges: 0) {
                if machine.services.isEmpty {
                    Text("Aucun service annoncé. Sur la machine : asl annonce <service> tcp:<port>")
                        .font(.callout).foregroundStyle(.secondary).padding(12)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
                        GridRow {
                            Titre("Service"); Titre("Points d'écoute"); Titre("État"); Titre("Verdict de la sonde")
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        ForEach(machine.services) { service in
                            Divider().gridCellUnsizedAxes(.horizontal)
                            GridRow {
                                HStack(spacing: 8) {
                                    PastilleMac(couleur: couleurService(service))
                                    Text(service.nom).font(.system(.callout, design: .monospaced))
                                }
                                Text(service.pointsTexte).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                                Text(service.libelleEtat)
                                Text(service.detailEtat).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }

    private var gestes: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button("Renommer") { nouveauNom = machine.nom; renomme = true }
                Button("Changer les capacités") {
                    annonce = machine.capacites.contains(.annonce)
                    lecture = machine.capacites.contains(.lecture)
                    changeCapacites = true
                }
                Spacer()
                switch machine.cle {
                case .enrolee:
                    Button("Révoquer la clé", role: .destructive) { confirmeRevocation = true }
                case .attendue, .revoquee:
                    Button("Émettre un nouveau code") { Task { await emettreCode() } }
                }
                if enCours { ProgressView().controlSize(.small) }
            }
            .disabled(enCours)
            Text(texteGeste).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Ce que l'on montre

    private var couleurCle: Color {
        switch machine.cle {
        case .enrolee: Couleurs.joignable
        case .attendue: Couleurs.parti
        case .revoquee: Couleurs.attention
        }
    }

    private var texteCle: String {
        switch machine.cle {
        case let .enrolee(le): (le.map { "enrôlée le \($0.jour)" } ?? "enrôlée") + " — Ed25519, générée sur la machine"
        case let .attendue(code): code.map { $0.estValide(a: .now) ? "attendue — un code est valable" : "attendue — le code a expiré" } ?? "attendue — pas de code en cours"
        case let .revoquee(le, _): "révoquée le \(le.jour) — un nouveau code la ré-enrôle"
        }
    }

    private var texteGeste: String {
        switch machine.cle {
        case .enrolee: "Révoquer la clé ferme ses connexions et fait tomber ses baux, tout de suite. La machine reste — son nom, ses capacités, ses services — et un nouveau code la ré-enrôle."
        case .attendue, .revoquee: "Un code neuf tue le précédent. Il est à usage unique et vaut dix minutes."
        }
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

    private var capacitesChoisies: Set<Capacite> {
        var choisies: Set<Capacite> = []
        if annonce { choisies.insert(.annonce) }
        if lecture { choisies.insert(.lecture) }
        return choisies
    }

    // MARK: - Les gestes

    private func modifier(nom: String?, capacites: Set<Capacite>?) async {
        enCours = true
        defer { enCours = false }
        do {
            _ = try await session.annuaire.modifierMachine(machine.id, nom: nom, capacites: capacites)
            renomme = false
            changeCapacites = false
            erreur = nil
            await donnees.recharger(session)
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func emettreCode() async {
        enCours = true
        defer { enCours = false }
        do {
            _ = try await session.annuaire.emettreCode(pour: machine.id)
            erreur = nil
            await donnees.recharger(session)
        } catch {
            erreur = error.messageAnnuaire
        }
    }

    private func revoquerCle() async {
        enCours = true
        defer { enCours = false }
        do {
            try await session.annuaire.revoquerCle(de: machine.id)
            erreur = nil
            await donnees.recharger(session)
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

extension TimeInterval {
    /// « 9 min », « 40 s » — le temps qui reste à un code.
    var minutes: String {
        self >= 60 ? "\(Int(self / 60)) min" : "\(Int(self)) s"
    }
}

extension Appareil.Plateforme {
    var libelle: String {
        switch self {
        case .ios: "iOS"
        case .android: "Android"
        case .macos: "macOS"
        }
    }
}
