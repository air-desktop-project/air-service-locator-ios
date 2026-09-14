import CAsl
import Foundation
import Observation
import OSLog

/// Ce Mac, en tant que MACHINE — la seconde identité d'un même boîtier.
///
/// # Deux identités, et pourquoi ce n'est pas une de trop
///
/// Un Mac qui fait tourner cette application est un **appareil**
/// (`modele.md` §2.2) : il administre le compte, sa clé P-256 vit dans la
/// Secure Enclave et signe sous Touch ID. Le même Mac peut aussi héberger des
/// daemons — il est alors une **machine** (§2.3) : une clé Ed25519 qui signe
/// SANS PERSONNE, toutes les dix secondes, pour tenir un bail. On ne peut pas
/// demander Touch ID à un keepalive, et on ne doit pas laisser une clé qui
/// signe sans témoin administrer le compte. Deux rôles, deux clés — donc deux
/// identifiants, puisque l'identité est la clé. Et deux visibilités : `m-…`
/// se donne à qui doit joindre un service ; `a-…` ne sort pas du compte.
///
/// Ce que le modèle ne dit pas, et que ce fichier apporte, c'est **le lien** :
/// ce Mac sait qu'il est la machine `m-…`, parce que c'est lui qui l'a
/// déclarée et enrôlée, en un geste. Le lien vit ici, dans son conteneur, et
/// n'en sort pas — un autre appareil du compte n'a pas à savoir que la machine
/// « bureau » est aussi ton Mac.
///
/// # Le même chemin qu'`asl enrole`, sans terminal — et le même fichier
///
/// L'application embarque `asl-client`, qui porte les deux voies : celle des
/// téléphones (`asl_appareil_*`) et celle des daemons (`asl_client_*`). Cette
/// classe emprunte la seconde, exactement comme l'utilitaire `asl` sur un
/// Linux : un client, l'annuaire, les racines, `asl_enroler` avec le code —
/// et l'identité rendue (l'identifiant, et la graine dont la clé se dérive)
/// est rangée **dans le format d'`asl`**, un fichier `identite` à deux lignes
/// (`machine = m-…`, `graine = <hexa>`), en mode 0600, dans un dossier `asl/`
/// du conteneur. Ainsi ce Mac n'a QU'UNE identité de machine, et l'utilitaire
/// la lit tel quel : `asl --etat <ce dossier> annonce …`. C'est le seul
/// justificatif durable de cette machine.
@MainActor
@Observable
final class MachineDeCeMac {
    /// L'identité rendue par l'enrôlement, telle qu'on la conserve.
    private struct Identite {
        let machine: String
        let graine: Data
    }

    enum Erreur: Error, LocalizedError {
        case natif(Int32, String)
        case identifiant(String)

        var errorDescription: String? {
            switch self {
            case let .natif(code, quoi): "\(quoi) : \(String(cString: asl_faute_texte(code))) (\(code))"
            case let .identifiant(texte): "l'annuaire a rendu un identifiant illisible : \(texte)"
            }
        }
    }

    private nonisolated static let journal = Logger(subsystem: "org.airdesktop.servicelocator", category: "machine")
    private let reglages: AnnuaireReel.Reglages

    /// La machine que ce Mac est, s'il en est une. `nil` tant qu'il n'a pas
    /// été enrôlé depuis ici.
    private(set) var identifiant: Identifiant?

    init(reglages: AnnuaireReel.Reglages) {
        self.reglages = reglages
        if let texte = Self.lire()?.machine { identifiant = try? Identifiant.analyser(texte, genre: .machine) }
    }

    /// Présente le code à l'annuaire, et rend l'identifiant de machine obtenu
    /// — qui doit être celui que `POST /v1/machines` a rendu à l'appareil.
    ///
    /// L'appel bloque le temps d'une connexion QUIC ; il tourne sur son propre
    /// fil, avec une pile large : le natif y déroule sa pile TLS.
    func enroler(code: CodeEnrolement) async throws -> Identifiant {
        let reglages = reglages
        let (texte, graine): (String, Data) = try await withCheckedThrowingContinuation { suite in
            let fil = Thread {
                suite.resume(with: Result { try Self.enrolerBloquant(code: code.texteGroupe, reglages: reglages) })
            }
            fil.stackSize = 8 << 20
            fil.name = "org.airdesktop.servicelocator.machine"
            fil.start()
        }
        let identifiant = try Identifiant.analyser(texte, genre: .machine)
        try Self.ecrire(Identite(machine: texte, graine: graine))
        self.identifiant = identifiant
        Self.journal.notice("ce Mac est la machine \(texte, privacy: .public)")
        return identifiant
    }

    /// Oublie l'identité de machine de ce Mac. L'annuaire, lui, garde la
    /// machine : c'est une révocation de clé qu'il faut faire à côté.
    func oublier() throws {
        let chemin = try Self.chemin
        if FileManager.default.fileExists(atPath: chemin.path) { try FileManager.default.removeItem(at: chemin) }
        identifiant = nil
    }

    /// Le dossier que l'utilitaire `asl` prend en `--etat` pour parler au nom
    /// de cette machine — à montrer, pour qu'on le copie.
    static var dossierPourAsl: String? { (try? dossier)?.path }

    // MARK: - Le natif

    private nonisolated static func enrolerBloquant(code: String, reglages: AnnuaireReel.Reglages) throws -> (String, Data) {
        var client: OpaquePointer?
        try exiger(asl_client_neuf(&client), "asl_client_neuf")
        guard let client else { throw Erreur.natif(ASL_INTERNE, "asl_client_neuf") }
        defer { asl_client_libere(client) }
        for adresse in try AnnuaireReel.adressesLitterales(reglages.adresse) {
            try exiger(asl_client_annuaire(client, adresse, reglages.nom), "asl_client_annuaire")
        }
        try reglages.racinesPEM.withUnsafeBytes { pem in
            try exiger(asl_client_racines(client, pem.bindMemory(to: UInt8.self).baseAddress, pem.count), "asl_client_racines")
        }
        var machine = [CChar](repeating: 0, count: Int(ASL_IDENTIFIANT_OCTETS))
        var graine = [UInt8](repeating: 0, count: Int(ASL_GRAINE_OCTETS))
        try exiger(asl_enroler(client, code, &machine, &graine), "asl_enroler")
        let texte = String(decoding: machine.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return (texte, Data(graine))
    }

    private nonisolated static func exiger(_ code: Int32, _ quoi: String) throws {
        journal.notice("\(quoi, privacy: .public) → \(code)")
        guard code == ASL_OK else { throw Erreur.natif(code, quoi) }
    }

    // MARK: - Le fichier, au format d'`asl`

    /// `Application Support/asl/` dans le conteneur du bac à sable — le
    /// pendant de `~/.config/asl` sur un Linux, et ce qu'on donne à
    /// `asl --etat`. La graine est la clé : ce dossier ne se partage pas, ne
    /// se sauvegarde pas.
    private static var dossier: URL {
        get throws {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return support.appendingPathComponent("asl", isDirectory: true)
        }
    }

    /// `identite`, le nom qu'`asl` cherche.
    private static var chemin: URL {
        get throws { try dossier.appendingPathComponent("identite", isDirectory: false) }
    }

    /// Le format d'`asl` (`crates/asl-cli/src/etat.rs` du dépôt client) : des
    /// lignes `clé = valeur`, les commentaires en `#`, la graine en
    /// hexadécimal. Lu ici avec la même tolérance qu'il l'écrit.
    private static func lire() -> Identite? {
        guard let chemin = try? chemin, let contenu = try? String(contentsOf: chemin, encoding: .utf8) else { return nil }
        var machine: String?
        var graine: Data?
        for ligne in contenu.split(whereSeparator: \.isNewline) {
            let ligne = ligne.trimmingCharacters(in: .whitespaces)
            guard !ligne.isEmpty, !ligne.hasPrefix("#"), let egal = ligne.firstIndex(of: "=") else { continue }
            let cle = ligne[..<egal].trimmingCharacters(in: .whitespaces)
            let valeur = ligne[ligne.index(after: egal)...].trimmingCharacters(in: .whitespaces)
            switch cle {
            case "machine": machine = valeur
            case "graine": graine = depuisHexa(valeur)
            default: break
            }
        }
        guard let machine, let graine, graine.count == Int(ASL_GRAINE_OCTETS) else { return nil }
        return Identite(machine: machine, graine: graine)
    }

    /// Mode 0600 dès la création, comme `asl` : une clé lisible par d'autres
    /// n'est plus une clé — et `asl` refuserait de la lire.
    private static func ecrire(_ identite: Identite) throws {
        let dossier = try dossier
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var chemin = try chemin
        let contenu = """
        # asl — l'identité de cette machine, écrite par l'application Service Locator.
        #
        # LA MOITIÉ PRIVÉE D'UNE PAIRE DE CLÉS. Elle n'a jamais quitté ce disque,
        # et elle ne le doit pas : l'annuaire ne connaît que la moitié publique.
        # Ne la copiez pas sur une autre machine — enrôlez-la, c'est gratuit.
        machine = \(identite.machine)
        graine = \(enHexa(identite.graine))

        """
        try Data(contenu.utf8).write(to: chemin, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: chemin.path)
        var valeurs = URLResourceValues()
        valeurs.isExcludedFromBackup = true
        try chemin.setResourceValues(valeurs)
    }

    private static func enHexa(_ octets: Data) -> String {
        octets.map { String(format: "%02x", $0) }.joined()
    }

    private static func depuisHexa(_ texte: String) -> Data? {
        let caracteres = Array(texte.utf8)
        guard caracteres.count % 2 == 0 else { return nil }
        var octets = Data(capacity: caracteres.count / 2)
        var i = 0
        while i < caracteres.count {
            guard let octet = UInt8(String(decoding: caracteres[i..<i + 2], as: UTF8.self), radix: 16) else { return nil }
            octets.append(octet)
            i += 2
        }
        return octets
    }
}
