import SwiftUI

// Les gestes — déclarer, faire de ce Mac une machine, rejoindre, enrôler un
// autre appareil. Ils vivaient dans le panneau ; ils vivent dans la fenêtre,
// et leur état dans `GestesDuPanneau`, qui survit à tout.

/// `POST /v1/machines` : un nom, des capacités, et le code à taper là-bas.
struct DeclarerVueMac: View {
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

/// Ce Mac devient une machine, en un geste : Touch ID la déclare
/// (`POST /v1/machines`), et le code rendu est consommé sur place par la voie
/// des daemons d'`asl-client` — l'utilisateur ne le voit jamais.
struct CeMacMachineVueMac: View {
    @Environment(Session.self) private var session
    @Environment(GestesDuPanneau.self) private var gestes
    let machineDeCeMac: MachineDeCeMac
    let apres: () async -> Void
    @State private var annonce = true
    @State private var lecture = true
    @State private var erreur: String?
    @State private var enCours = false

    var body: some View {
        @Bindable var gestes = gestes
        VStack(alignment: .leading, spacing: 8) {
            Text("Ce Mac administre déjà le compte. Il peut aussi héberger des daemons : c'est une seconde identité, une clé qui signe sans vous — celle d'une machine.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Nom, pour vous", text: $gestes.nomDeCeMac).textFieldStyle(.roundedBorder)
            Toggle("Annonce — ses daemons peuvent annoncer leurs ports", isOn: $annonce).font(.caption)
            Toggle("Lecture — il peut demander où joindre un service", isOn: $lecture).font(.caption)
            if let erreur { Text(erreur).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Déclarer et enrôler ce Mac") { Task { await faire() } }
                    .disabled(enCours || !Machine.nomValide(gestes.nomDeCeMac))
                if enCours { ProgressView().controlSize(.small) }
            }
        }
        .padding(.top, 6)
    }

    private func faire() async {
        enCours = true
        defer { enCours = false }
        var capacites: Set<Capacite> = []
        if annonce { capacites.insert(.annonce) }
        if lecture { capacites.insert(.lecture) }
        do {
            let machine = try await session.annuaire.declarerMachine(nom: gestes.nomDeCeMac, capacites: capacites)
            guard case let .attendue(.some(code)) = machine.cle else {
                erreur = "L'annuaire n'a pas rendu de code d'enrôlement."
                return
            }
            let enrolee = try await machineDeCeMac.enroler(code: code)
            // L'identifiant que le code a ouvert doit être celui de la machine
            // déclarée : sinon, ce n'est pas ce Mac qu'on vient d'enrôler.
            guard enrolee == machine.id else {
                try? machineDeCeMac.oublier()
                erreur = "L'enrôlement a rendu \(enrolee.abrege), la déclaration \(machine.id.abrege) : ce n'est pas la même machine."
                return
            }
            erreur = nil
            gestes.enCours = nil
            await apres()
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

/// Rejoindre, depuis ce Mac : montrer sa clé — en QR pour la caméra du
/// téléphone, en texte pour le presse-papiers —, coller la réponse.
struct RejoindreVueMac: View {
    @Environment(Session.self) private var session
    @Environment(GestesDuPanneau.self) private var gestes
    @State private var cle: [UInt8]?
    @State private var erreur: String?
    @State private var enCours = false

    var body: some View {
        @Bindable var gestes = gestes
        VStack(alignment: .leading, spacing: 8) {
            if let cle {
                Text("1. Sur le téléphone déjà enrôlé : Compte › Enrôler un autre appareil, et lisez ce code à la caméra — ou collez-lui la clé.").font(.caption)
                CodeQRMac(texte: Invitation.cle(cle).texte)
                LigneCopiableMac(titre: "La clé publique de ce Mac", texte: Invitation.cle(cle).texte)
                Text("2. Collez ici sa réponse ; Touch ID prouvera la clé.").font(.caption)
                TextField("asl:appareil:…", text: $gestes.reponseCollee).textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
                if let erreur { Text(erreur).font(.caption).foregroundStyle(.red) }
                Button("Rejoindre") { Task { await rejoindre() } }
                    .disabled(enCours || Invitation.analyser(gestes.reponseCollee) == nil)
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
        guard case let .appareil(compte, appareil)? = Invitation.analyser(gestes.reponseCollee) else {
            erreur = "Ce code est une clé, pas une réponse."
            return
        }
        enCours = true
        defer { enCours = false }
        do {
            try await session.rejoindre(compte: compte, appareil: appareil)
            gestes.reponseCollee = ""
            gestes.enCours = nil
            erreur = nil
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}

/// `POST /v1/appareils`, depuis ce Mac : coller la clé du nouveau, lui rendre
/// la réponse — en QR, qu'il lit à sa caméra, et en texte.
struct EnrolerAppareilVueMac: View {
    @Environment(Session.self) private var session
    @Environment(GestesDuPanneau.self) private var gestes
    let apres: () async -> Void
    @State private var erreur: String?

    var body: some View {
        @Bindable var gestes = gestes
        VStack(alignment: .leading, spacing: 8) {
            if let reponse = gestes.reponseRendue {
                Text("L'appareil est enrôlé. Rendez-lui ce code — à sa caméra, ou collé : il rejoindra le compte en prouvant sa clé, là-bas.").font(.caption)
                CodeQRMac(texte: reponse.texte)
                LigneCopiableMac(titre: "La réponse à lui donner", texte: reponse.texte)
                Button("Terminé") { gestes.reponseRendue = nil; gestes.cleAEnroler = "" }
            } else {
                Text("Sur le nouveau téléphone : « Rejoindre un compte existant ». Collez ici la clé qu'il montre.").font(.caption)
                TextField("asl:cle:…", text: $gestes.cleAEnroler).textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
                if let erreur { Text(erreur).font(.caption).foregroundStyle(.red) }
                Button("Enrôler") { Task { await enroler() } }
                    .disabled(Invitation.analyser(gestes.cleAEnroler) == nil)
            }
        }
        .padding(.top, 6)
    }

    private func enroler() async {
        guard case let .cle(octets)? = Invitation.analyser(gestes.cleAEnroler), let compte = session.compte else {
            erreur = "Ce code est une réponse, pas une clé."
            return
        }
        do {
            let appareil = try await session.annuaire.enrolerAppareil(cle: octets)
            gestes.reponseRendue = .appareil(compte: compte.identifiant, appareil: appareil.id)
            erreur = nil
            await apres()
        } catch {
            erreur = error.messageAnnuaire
        }
    }
}
