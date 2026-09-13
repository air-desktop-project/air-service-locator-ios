import CryptoKit
import Foundation
import Testing
@testable import AirServiceLocator

/// Ce qu'un appareil signe, et comment — octet pour octet comme `asl-cle`.
struct MessagesEssais {
    private let appareil = Identifiant(genre: .appareil, octets: (0..<16).map { UInt8($0) })
    private let defi = [UInt8](repeating: 0xAA, count: 32)
    private let liaison = [UInt8](repeating: 0xBB, count: 32)

    @Test func lesDomainesSontCeuxDuServeurTerminesParUnZero() {
        #expect(Messages.domaineAuthentification == Array("air-service-locator/v1/authentification-machine".utf8) + [0])
        #expect(Messages.domainePossession == Array("air-service-locator/v1/possession-de-cle".utf8) + [0])
        #expect(Messages.domaineAttestation == Array("air-service-locator/v1/attestation-d-appareil".utf8) + [0])
        // Trois domaines distincts, ou une signature faite pour l'un vaudrait pour l'autre.
        #expect(Set([Messages.domaineAuthentification, Messages.domainePossession, Messages.domaineAttestation]).count == 3)
    }

    @Test func leMessageDauthentificationEstDomaineGenreIdentifiantDefiLiaison() {
        let message = Messages.aSigner(appareil: appareil, defi: defi, liaison: liaison)
        let d = Messages.domaineAuthentification
        #expect(message.count == d.count + 1 + 16 + 32 + 32)
        #expect(Array(message[0..<d.count]) == d)
        #expect(message[d.count] == UInt8(ascii: "a"))
        #expect(Array(message[(d.count + 1)..<(d.count + 17)]) == appareil.octets)
        #expect(Array(message[(d.count + 17)..<(d.count + 49)]) == defi)
        #expect(Array(message[(d.count + 49)...]) == liaison)
    }

    @Test func leMessageDePossessionPorteLaCleEtNonUnNom() {
        let cle = CleLogicielle().clePublique
        let message = Messages.dePossession(cle: cle, defi: defi, liaison: liaison)
        let d = Messages.domainePossession
        #expect(message.count == d.count + 33 + 32 + 32)
        #expect(Array(message[d.count..<(d.count + 33)]) == cle)
    }
}

struct SignatureAppareilEssais {
    @Test func laClePubliqueEstSEC1CompresseeSurTrenteTroisOctets() {
        let cle = CleLogicielle().clePublique
        #expect(cle.count == 33)
        #expect(cle[0] == 0x02 || cle[0] == 0x03)
    }

    @Test func uneSignatureEstRSSurSoixanteQuatreOctetsEtVerifieSousLaCle() async throws {
        let cle = CleLogicielle()
        let message = Array("un message quelconque".utf8)
        let signature = try await cle.signer(message)
        #expect(signature.count == 64)
        #expect(VerificationAppareil.verifie(cle: cle.clePublique, message: message, signature: signature))
        // Un autre message, une autre clé, une signature tronquée : rien ne passe.
        #expect(!VerificationAppareil.verifie(cle: cle.clePublique, message: message + [0], signature: signature))
        #expect(!VerificationAppareil.verifie(cle: CleLogicielle().clePublique, message: message, signature: signature))
        #expect(!VerificationAppareil.verifie(cle: cle.clePublique, message: message, signature: Array(signature.dropLast())))
    }

    /// Le serveur vérifie avec `p256` en hachant le message en SHA-256 : on
    /// s'assure ici que CryptoKit fait de même, en vérifiant la signature
    /// contre le condensat explicite.
    @Test func laSignatureCouvreLeSHA256DuMessage() async throws {
        let cle = CleLogicielle()
        let message = Array("air-service-locator".utf8)
        let signature = try await cle.signer(message)
        let publique = try P256.Signing.PublicKey(compressedRepresentation: Data(cle.clePublique))
        let ecdsa = try P256.Signing.ECDSASignature(rawRepresentation: Data(signature))
        #expect(publique.isValidSignature(ecdsa, for: SHA256.hash(data: Data(message))))
    }

    @Test func uneCleDepuisLaMemeEntropieDonneLaMemeClePublique() throws {
        let entropie = (1...32).map { UInt8($0) }
        #expect(try CleLogicielle(entropie: entropie).clePublique == CleLogicielle(entropie: entropie).clePublique)
        #expect(throws: (any Error).self) { try CleLogicielle(entropie: [UInt8](repeating: 0, count: 32)) }
    }

    /// La Secure Enclave, quand l'environnement en a une (le simulateur en
    /// émule une). Signer demande la biométrie : cet essai ne fait que créer,
    /// lire la clé publique, et effacer.
    @Test func laSecureEnclaveDonneUneClePubliqueStable() throws {
        guard SecureEnclave.isAvailable else { return }
        try CleAppareil.effacer()
        let premiere = try CleAppareil.ouOuvrir().clePublique
        let relue = try CleAppareil.ouOuvrir().clePublique
        #expect(premiere.count == 33)
        #expect(premiere == relue)
        try CleAppareil.effacer()
        #expect(try CleAppareil.ouOuvrir().clePublique != premiere)
        try CleAppareil.effacer()
    }
}
