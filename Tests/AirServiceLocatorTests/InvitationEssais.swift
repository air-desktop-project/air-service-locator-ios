import Foundation
import Testing
@testable import AirServiceLocator

/// Ce que deux téléphones s'échangent, et le base32 qui le porte.
struct InvitationEssais {
    @Test func leBase32FaitLAllerRetourSurTrenteTroisOctets() {
        let octets: [UInt8] = [0x02] + (1 ... 32).map { UInt8($0 &* 7) }
        let texte = Crockford.texte(octets)
        #expect(texte.count == 53)
        #expect(Crockford.octets(texte, compte: 33) == octets)
        // Un octet, deux octets : le bourrage change, le résultat non.
        for taille in 1 ... 40 {
            let quelconque = (0 ..< taille).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) }
            #expect(Crockford.octets(Crockford.texte(quelconque), compte: taille) == quelconque)
        }
    }

    @Test func leBase32RefuseCeQuiNestPasUnCode() {
        let texte = Crockford.texte([UInt8](repeating: 0xFF, count: 33))
        #expect(Crockford.octets(String(texte.dropLast()), compte: 33) == nil)
        #expect(Crockford.octets(texte + "0", compte: 33) == nil)
        #expect(Crockford.octets(String(repeating: "U", count: 53), compte: 33) == nil)
        // Un bit de bourrage à un : ce n'est pas l'écriture canonique.
        #expect(Crockford.octets("Z" + String(texte.dropFirst()), compte: 33) == nil)
        // La casse et les confusions de Crockford sont rattrapées.
        #expect(Crockford.octets(texte.lowercased(), compte: 33) == Crockford.octets(texte, compte: 33))
    }

    @Test func uneInvitationSeLitTelleQuElleSEcrit() throws {
        let cle = CleLogicielle().clePublique
        let montree = Invitation.cle(cle)
        #expect(montree.texte.hasPrefix("asl:cle:"))
        #expect(Invitation.analyser(montree.texte) == montree)
        #expect(Invitation.analyser(" " + montree.texte.lowercased() + "\n") == montree)
        // Un clavier a « corrigé » le préfixe : on lit quand même.
        #expect(Invitation.analyser(montree.texte.replacingOccurrences(of: "asl:cle:", with: "asl:clé:")) == montree)

        let compte = Identifiant(genre: .utilisateur, octets: [UInt8](repeating: 3, count: 16))
        let appareil = Identifiant(genre: .appareil, octets: [UInt8](repeating: 9, count: 16))
        let reponse = Invitation.appareil(compte: compte, appareil: appareil)
        #expect(reponse.texte == "asl:appareil:\(compte.texte):\(appareil.texte)")
        #expect(Invitation.analyser(reponse.texte) == reponse)

        // Un QR étranger, une clé hors forme, des genres inversés : rien.
        #expect(Invitation.analyser("https://example.org") == nil)
        #expect(Invitation.analyser("asl:cle:" + Crockford.texte([UInt8](repeating: 0x04, count: 33))) == nil)
        #expect(Invitation.analyser("asl:appareil:\(appareil.texte):\(compte.texte)") == nil)
    }

    @Test func leBancEnroleUnAppareilDePlusEtLeLaisseRejoindre() async throws {
        let annuaire = AnnuaireSimule()
        let nouveau = CleLogicielle()
        // Sans compte, rien à enrôler.
        await #expect(throws: ErreurAnnuaire.introuvable) { try await annuaire.enrolerAppareil(cle: nouveau.clePublique) }
        let compte = try await annuaire.ouvrirCompte(avec: CleLogicielle())
        let enrole = try await annuaire.enrolerAppareil(cle: nouveau.clePublique)
        #expect(enrole.id.genre == .appareil && !enrole.estCeluiCi)
        #expect(try await annuaire.appareils().count == 2)
        // Deux fois la même clé, non.
        await #expect(throws: ErreurAnnuaire.self) { try await annuaire.enrolerAppareil(cle: nouveau.clePublique) }

        // Rejoindre : le bon appareil sous la bonne clé, et la preuve tient.
        let rejoint = try await annuaire.rejoindre(compte: compte.identifiant, appareil: enrole.id, avec: nouveau)
        #expect(rejoint == compte)
        let appareils = try await annuaire.appareils()
        #expect(appareils.first { $0.id == enrole.id }?.estCeluiCi == true)
        #expect(appareils.filter(\.estCeluiCi).count == 1)

        // Une autre clé sous cet identifiant : introuvable, comme un 404 qui
        // ne dit pas pourquoi.
        await #expect(throws: ErreurAnnuaire.introuvable) {
            try await annuaire.rejoindre(compte: compte.identifiant, appareil: enrole.id, avec: CleLogicielle())
        }
    }
}
