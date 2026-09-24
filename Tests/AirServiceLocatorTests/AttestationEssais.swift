import Foundation
import Testing
@testable import AirServiceLocator

/// Sous quoi un appareil est entré — le mot du fil, et le mot de l'écran.
struct AttestationEssais {
    /// Les valeurs sont celles que l'annuaire écrit, à la lettre
    /// (`docs/modele.md` §2.2). Une faute de frappe ici rendrait `nil`, et
    /// l'écran dirait « inconnu » d'un appareil parfaitement attesté.
    @Test func lesValeursDuFilSeLisentTellesQuelles() {
        #expect(Appareil.Attestation(rawValue: "aucune") == .aucune)
        #expect(Appareil.Attestation(rawValue: "apple") == .apple)
        #expect(Appareil.Attestation(rawValue: "android") == .android)
        #expect(Appareil.Attestation(rawValue: "invitation") == .invitation)
        #expect(Appareil.Attestation(rawValue: "attendue") == .attendue)
    }

    /// `google` a été rendue puis abandonnée (C19), et l'annuaire ne l'a
    /// jamais servie : elle ne doit pas se relire en douce.
    @Test func uneValeurInconnueNeSeDevinePas() {
        #expect(Appareil.Attestation(rawValue: "google") == nil)
        #expect(Appareil.Attestation(rawValue: "") == nil)
        #expect(Appareil.Attestation(rawValue: "Attendue") == nil)
    }

    /// L'étiquette vient du `Coeur`, une seule fois pour les deux
    /// applications : c'est ce qui empêche l'iPhone et le Mac de diverger.
    @Test func chaqueValeurSeDitEnFrancais() {
        #expect(Appareil.Attestation.aucune.libelle == "sans attestation")
        #expect(Appareil.Attestation.apple.libelle == "attesté par Apple")
        #expect(Appareil.Attestation.android.libelle == "clé attestée (Android)")
        #expect(Appareil.Attestation.invitation.libelle == "sur invitation")
        #expect(Appareil.Attestation.attendue.libelle == "en attente d'attestation")
    }

    /// **`attendue` est vivante.** Un appareil que personne n'a encore prouvé
    /// n'est pas révoqué : il se compte, il s'affiche, il se révoque comme un
    /// autre — et un compte dont c'est le seul appareil n'est pas orphelin,
    /// il est en train de rejoindre (`protocole.md` §2.2).
    @Test func unAppareilEnAttenteCompteParmiLesVivants() {
        let attendu = Appareil(id: Identifiant(genre: .appareil, entropie: [UInt8](repeating: 1, count: 16)),
                               nom: "Autre appareil", attestation: .attendue)
        let revoque = Appareil(id: Identifiant(genre: .appareil, entropie: [UInt8](repeating: 2, count: 16)),
                               nom: "Ancien", attestation: .android,
                               revoqueLe: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(!attendu.estRevoque)
        #expect(revoque.estRevoque)
        #expect([attendu, revoque].filter { !$0.estRevoque }.count == 1)
    }
}
