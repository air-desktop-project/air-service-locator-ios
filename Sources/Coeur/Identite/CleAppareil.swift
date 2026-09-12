import CryptoKit
import Foundation
import LocalAuthentication

/// Ce qu'une clé d'appareil sait faire — et la seule chose que les écrans en
/// voient. La Secure Enclave la met en œuvre sur un appareil ; une clé
/// logicielle la met en œuvre dans un essai.
protocol Signataire: Sendable {
    /// La clé publique, SEC1 compressée : `02` ou `03` ‖ x — 33 octets.
    var clePublique: [UInt8] { get }
    /// Signe en ECDSA P-256 sur SHA-256, et rend `r ‖ s` — 64 octets. C'est
    /// ici que la biométrie est demandée, et c'est pourquoi c'est `async`.
    func signer(_ message: [UInt8]) async throws -> [UInt8]
}

extension Signataire {
    /// La preuve de possession de `POST /v1/comptes` : la clé signe le message
    /// qui la contient.
    func prouverLaPossession(defi: [UInt8], liaison: [UInt8]) async throws -> [UInt8] {
        try await signer(Messages.dePossession(cle: clePublique, defi: defi, liaison: liaison))
    }

    /// La signature d'authentification d'un appareil enrôlé.
    func authentifier(appareil: Identifiant, defi: [UInt8], liaison: [UInt8]) async throws -> [UInt8] {
        try await signer(Messages.aSigner(appareil: appareil, defi: defi, liaison: liaison))
    }
}

/// La clé P-256 de cet appareil, dans la Secure Enclave, sous contrôle
/// biométrique.
///
/// # La biométrie est une condition d'usage de la clé, appliquée par le matériel
///
/// `kSecAccessControlBiometryCurrentSet` : la clé ne signe qu'après une
/// confirmation Face ID ou Touch ID, et devient inutilisable si le jeu de
/// visages ou d'empreintes change. Ce n'est pas un booléen que le code
/// transporte — c'est la Secure Enclave qui refuse de signer sans. Le serveur
/// ne verra jamais que la signature.
///
/// **La partie privée ne sort jamais.** Ce que l'application garde est une
/// représentation chiffrée que seule cette enclave sait ouvrir — inutile sur
/// tout autre appareil, et c'est voulu : un compte est un jeu d'appareils, pas
/// une clé qui voyage.
///
/// # Dans un fichier, et non dans le Keychain — et pourquoi
///
/// Le Keychain est l'endroit habituel, et il a été essayé : sans identité de
/// signature (le simulateur, la CI), il refuse (`errSecMissingEntitlement`),
/// et un chemin qui marche sur l'appareil mais pas sur le banc est un chemin
/// qu'on n'éprouve pas. Le fichier n'ôte rien : la représentation est déjà
/// chiffrée par l'enclave, et elle est en plus posée sous protection complète,
/// exclue des sauvegardes. Il apporte une chose : **désinstaller l'application
/// efface la clé**, là où un secret du Keychain survit à la réinstallation —
/// et un appareil réinstallé qui se croirait encore enrôlé serait une faute.
///
/// # Le simulateur, et ce qu'il ne sait pas faire
///
/// Il émule une enclave, mais refuse d'y lier une clé à la biométrie
/// (`LAError -1020`, « not supported on iOS Simulator »). Sur simulateur, la
/// clé est donc créée sans cette condition, et c'est un `LAContext` qui
/// demande Face ID avant chaque signature — le même geste, au même moment,
/// mais tenu par le code et non par le matériel. La différence est dite ici,
/// bornée par `#if targetEnvironment(simulator)`, et n'existe pas sur un
/// appareil.
///
/// # P-256, et rien d'autre
///
/// La Secure Enclave ne fait que cette courbe. Les machines signent en Ed25519 ;
/// les appareils en ECDSA P-256, et c'est la clé rangée dans l'annuaire qui
/// dit, par sa forme, comment vérifier (`asl_cle::CleAppareil`).
struct CleAppareil: Signataire {
    private let cle: SecureEnclave.P256.Signing.PrivateKey

    enum Erreur: Error, Equatable {
        case enclaveIndisponible
        case controleAcces(OSStatus)
        case signature(String)
    }

    /// La raison affichée par le système au moment de poser le doigt.
    static let raison = "Signer avec la clé de cet appareil"

    var clePublique: [UInt8] { Array(cle.publicKey.compressedRepresentation) }

    /// Ouvre la clé de cet appareil, ou la crée si elle n'existe pas encore.
    ///
    /// Créer ne demande pas la biométrie ; signer, si. C'est le moment de la
    /// première signature — la preuve de possession — que l'utilisateur
    /// confirme.
    static func ouOuvrir(contexte: LAContext = LAContext()) throws -> CleAppareil {
        guard SecureEnclave.isAvailable else { throw Erreur.enclaveIndisponible }
        if let existante = try lire() {
            return CleAppareil(cle: try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: existante, authenticationContext: contexte))
        }
        #if targetEnvironment(simulator)
        let drapeaux: SecAccessControlCreateFlags = [.privateKeyUsage]
        #else
        let drapeaux: SecAccessControlCreateFlags = [.privateKeyUsage, .biometryCurrentSet]
        #endif
        var erreur: Unmanaged<CFError>?
        guard let controle = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, drapeaux, &erreur
        ) else {
            throw Erreur.controleAcces(OSStatus((erreur?.takeRetainedValue() as Error?).map { ($0 as NSError).code } ?? -1))
        }
        let neuve = try SecureEnclave.P256.Signing.PrivateKey(accessControl: controle, authenticationContext: contexte)
        try ecrire(neuve.dataRepresentation)
        return CleAppareil(cle: neuve)
    }

    func signer(_ message: [UInt8]) async throws -> [UInt8] {
        #if targetEnvironment(simulator)
        // Le simulateur ne lie pas la clé à la biométrie : on la demande ici.
        let contexte = LAContext()
        contexte.localizedCancelTitle = "Annuler"
        do {
            guard try await contexte.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: Self.raison) else {
                throw Erreur.signature("identité non confirmée")
            }
        } catch let erreur as LAError {
            throw Erreur.signature("identité non confirmée (\(erreur.code.rawValue) : \(erreur.localizedDescription))")
        }
        #endif
        do {
            // CryptoKit hache en SHA-256 et rend déjà `r ‖ s` : rien à déplier.
            return Array(try cle.signature(for: Data(message)).rawRepresentation)
        } catch {
            throw Erreur.signature(error.localizedDescription)
        }
    }

    // MARK: - Le fichier, pour la représentation opaque

    private static var chemin: URL {
        get throws {
            let dossier = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return dossier.appendingPathComponent("cle-appareil.p256", isDirectory: false)
        }
    }

    private static func lire() throws -> Data? {
        let chemin = try chemin
        guard FileManager.default.fileExists(atPath: chemin.path) else { return nil }
        return try Data(contentsOf: chemin)
    }

    private static func ecrire(_ donnees: Data) throws {
        var chemin = try chemin
        try donnees.write(to: chemin, options: [.atomic, .completeFileProtection])
        var valeurs = URLResourceValues()
        valeurs.isExcludedFromBackup = true
        try chemin.setResourceValues(valeurs)
    }

    /// Efface la clé de cet appareil. Sans retour : l'annuaire refusera la
    /// prochaine authentification, et il faudra ré-enrôler.
    static func effacer() throws {
        let chemin = try chemin
        if FileManager.default.fileExists(atPath: chemin.path) {
            try FileManager.default.removeItem(at: chemin)
        }
    }
}

/// Une clé P-256 logicielle, pour les essais et les bancs — jamais sur un
/// appareil : elle n'est protégée par rien.
struct CleLogicielle: Signataire {
    private let cle: P256.Signing.PrivateKey

    init() { cle = P256.Signing.PrivateKey() }

    init(entropie: [UInt8]) throws { cle = try P256.Signing.PrivateKey(rawRepresentation: Data(entropie)) }

    var clePublique: [UInt8] { Array(cle.publicKey.compressedRepresentation) }

    func signer(_ message: [UInt8]) async throws -> [UInt8] {
        Array(try cle.signature(for: Data(message)).rawRepresentation)
    }
}

/// Ce que le serveur fait d'une signature d'appareil, reproduit ici pour les
/// essais et le banc : `asl_cle::CleAppareil::verifie`.
enum VerificationAppareil {
    static func verifie(cle: [UInt8], message: [UInt8], signature: [UInt8]) -> Bool {
        guard cle.count == Messages.cleOctets, signature.count == Messages.signatureOctets,
              let publique = try? P256.Signing.PublicKey(compressedRepresentation: Data(cle)),
              let ecdsa = try? P256.Signing.ECDSASignature(rawRepresentation: Data(signature))
        else { return false }
        return publique.isValidSignature(ecdsa, for: Data(message))
    }
}
