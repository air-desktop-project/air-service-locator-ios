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
/// # Le même chemin qu'`asl enrole`, sans terminal
///
/// L'application embarque `asl-client`, qui porte les deux voies : celle des
/// téléphones (`asl_appareil_*`) et celle des daemons (`asl_client_*`). Cette
/// classe emprunte la seconde, exactement comme l'utilitaire `asl` sur un
/// Linux : un client, l'annuaire, les racines, `asl_enroler` avec le code —
/// et l'identité rendue (l'identifiant, et la graine dont la clé se dérive)
/// est rangée dans un fichier du conteneur, comme `asl` la range dans le sien.
/// C'est le seul justificatif durable de cette machine.
@MainActor
@Observable
final class MachineDeCeMac {
    /// L'identité rendue par l'enrôlement, telle qu'on la conserve.
    private struct Identite: Codable {
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

    // MARK: - Le fichier

    /// Dans le conteneur du bac à sable, protégé par lui et par la session
    /// de l'utilisateur — comme `~/.config/asl` sur un Linux. La graine est
    /// la clé : ce fichier ne se partage pas, ne se sauvegarde pas.
    private static var chemin: URL {
        get throws {
            let dossier = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return dossier.appendingPathComponent("machine-de-ce-mac.json", isDirectory: false)
        }
    }

    private static func lire() -> Identite? {
        guard let chemin = try? chemin, let donnees = try? Data(contentsOf: chemin) else { return nil }
        return try? JSONDecoder().decode(Identite.self, from: donnees)
    }

    private static func ecrire(_ identite: Identite) throws {
        var chemin = try chemin
        try JSONEncoder().encode(identite).write(to: chemin, options: [.atomic, .completeFileProtection])
        var valeurs = URLResourceValues()
        valeurs.isExcludedFromBackup = true
        try chemin.setResourceValues(valeurs)
    }
}
