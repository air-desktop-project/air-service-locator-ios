import Foundation

/// Ce qu'un appareil signe, octet pour octet, tel que `asl-cle` le compose
/// côté serveur.
///
/// # Champs de longueur fixe, aucun préfixe de longueur, aucune ambiguïté
///
/// Les deux côtés doivent composer le même message ; un octet de différence et
/// aucune signature ne vérifie plus, sans qu'on sache pourquoi. Les domaines
/// séparent trois usages qui ne prouvent pas la même chose — s'authentifier,
/// prouver qu'on détient une clé, lier une attestation à cette clé — pour
/// qu'une signature faite pour l'un ne vaille jamais pour l'autre.
enum Messages {
    static let domaineAuthentification = Array("air-service-locator/v1/authentification-machine".utf8) + [0]
    static let domainePossession = Array("air-service-locator/v1/possession-de-cle".utf8) + [0]
    static let domaineAttestation = Array("air-service-locator/v1/attestation-d-appareil".utf8) + [0]

    static let defiOctets = 32
    static let liaisonOctets = 32
    static let cleOctets = 33
    static let signatureOctets = 64

    /// `domaine ‖ genre (ASCII) ‖ identifiant (16) ‖ défi (32) ‖ liaison (32)` —
    /// ce que signe un appareil enrôlé pour s'authentifier.
    static func aSigner(appareil: Identifiant, defi: [UInt8], liaison: [UInt8]) -> [UInt8] {
        precondition(appareil.genre == .appareil, "seul un appareil signe ici")
        precondition(defi.count == defiOctets && liaison.count == liaisonOctets)
        return domaineAuthentification + [UInt8(appareil.genre.rawValue.asciiValue!)] + appareil.octets + defi + liaison
    }

    /// `domaine ‖ clé (33) ‖ défi (32) ‖ liaison (32)` — ce que signe celui qui
    /// présente une clé, avant d'avoir un nom.
    static func dePossession(cle: [UInt8], defi: [UInt8], liaison: [UInt8]) -> [UInt8] {
        precondition(cle.count == cleOctets && defi.count == defiOctets && liaison.count == liaisonOctets)
        return domainePossession + cle + defi + liaison
    }

    /// Même dessin, sous un troisième domaine : ce dont App Attest hache le
    /// condensat, pour que l'attestation soit liée À LA clé présentée.
    static func dAttestation(cle: [UInt8], defi: [UInt8], liaison: [UInt8]) -> [UInt8] {
        precondition(cle.count == cleOctets && defi.count == defiOctets && liaison.count == liaisonOctets)
        return domaineAttestation + cle + defi + liaison
    }
}
