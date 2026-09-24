import Foundation
import Testing
@testable import AirServiceLocator

/// Le code qu'un invité recopie, et la posture qui décide s'il faut le
/// demander.
struct CodeInvitationEssais {
    /// Ce que l'annuaire écrit, à la lettre (`docs/protocole.md` §2.1). Une
    /// faute ici rendrait `nil`, et l'écran ne demanderait jamais de code sur
    /// une racine qui en exige un — l'ouverture échouerait sans qu'on
    /// comprenne.
    @Test func lesPosturesDuFilSeLisentTellesQuelles() {
        #expect(PostureAnnuaire(rawValue: "required") == .required)
        #expect(PostureAnnuaire(rawValue: "optional") == .optional)
        #expect(PostureAnnuaire(rawValue: "invitation") == .invitation)
    }

    /// **Le cas qui compte le plus le jour du déploiement** : nos racines ont
    /// servi 0.15.0 sans dire leur posture, et une version future pourrait en
    /// nommer une que ce code ignore. Dans les deux cas, on ne demande rien.
    @Test func unePostureAbsenteOuInconnueNeDemandeRien() {
        #expect(PostureAnnuaire(rawValue: "cheval") == nil)
        #expect(VersionAnnuaire(version: "0.15.0", posture: nil).exigeUneInvitation == false)
        #expect(VersionAnnuaire(version: "0.16.0", posture: .optional).exigeUneInvitation == false)
        #expect(VersionAnnuaire(version: "0.16.0", posture: .required).exigeUneInvitation == false)
    }

    /// La seule posture qui ouvre le champ.
    @Test func seuleLInvitationDemandeUnCode() {
        #expect(VersionAnnuaire(version: "0.16.0", posture: .invitation).exigeUneInvitation)
    }

    /// Le tiret est affiché, donc il sera tapé : le refuser serait punir
    /// quelqu'un d'avoir recopié ce qu'on lui a montré. La casse et les
    /// confusions de Crockford se rattrapent comme pour un identifiant.
    @Test func laSaisieHumaineSeRattrape() throws {
        let canonique = try CodeInvitation(saisie: "4K9M2P7R1T")
        #expect(try CodeInvitation(saisie: "4K9M2-P7R1T") == canonique)
        #expect(try CodeInvitation(saisie: "4k9m2-p7r1t") == canonique)
        #expect(try CodeInvitation(saisie: " 4K9M2-P7R1T ") == canonique)
        // `I` et `L` valent `1`, `O` vaut `0` : c'est la raison d'être de cet
        // alphabet, et elle vaut ici autant qu'ailleurs.
        #expect(try CodeInvitation(saisie: "4K9M2-P7RIT") == canonique)
        #expect(try CodeInvitation(saisie: "4K9M2-P7RLT") == canonique)
        #expect(try CodeInvitation(saisie: "0O0O0-00000") == (try CodeInvitation(saisie: "0000000000")))
    }

    /// Ce qui part sur le fil : **dix octets, pas un de plus**. L'annuaire
    /// refuse `400` si la case n'en porte pas exactement dix, et c'est ici que
    /// le tiret disparaît — pas là-bas.
    @Test func dixOctetsExactementPartentSurLeFil() throws {
        let code = try CodeInvitation(saisie: "4K9M2-P7R1T")
        #expect(code.octets.count == 10)
        #expect(code.symboles == "4K9M2P7R1T")
        #expect(code.octets == Array("4K9M2P7R1T".utf8))
        #expect(code.texteGroupe == "4K9M2-P7R1T")
    }

    /// Une saisie qui n'est pas un code n'en devient pas un.
    @Test func ceQuiNEstPasUnCodeEstRefuse() {
        #expect(CodeInvitation.essai("4K9M2") == nil)
        #expect(CodeInvitation.essai("4K9M2-P7R1T9") == nil)
        #expect(CodeInvitation.essai("") == nil)
        // `U` n'est pas dans l'alphabet de Crockford, et ne se rattrape pas.
        #expect(CodeInvitation.essai("4K9M2-P7R1U") == nil)
    }

    /// Le bouton ne s'active qu'une fois le code complet : `essai` dit non
    /// sans crier tant qu'on tape.
    @Test func unCodeIncompletNeLevePasDErreur() {
        #expect(CodeInvitation.essai("4K9") == nil)
        #expect(CodeInvitation.essai("4K9M2P7R1T") != nil)
    }
}

/// Ce que le banc fait d'une invitation — la règle du serveur, tenue en
/// mémoire : sous `invitation` un code est exigé, ailleurs il n'a rien à
/// recevoir.
@MainActor
struct OuvertureSurInvitationEssais {
    /// Une racine en `invitation` refuse un compte sans code, et le dit d'une
    /// seule phrase : ni « faux », ni « expiré », ni « déjà servi » — le
    /// serveur rend le même `403` pour les trois.
    @Test func sansCodeUneRacineSurInvitationRefuse() async throws {
        let annuaire = AnnuaireSimule()
        annuaire.posture = .invitation
        await #expect(throws: ErreurAnnuaire.invitationRefusee) {
            try await annuaire.ouvrirCompte(avec: CleLogicielle(), invitation: nil)
        }
    }

    /// Un mauvais code est refusé comme une absence de code : c'est le même
    /// refus, et l'écran dit la même chose.
    @Test func unMauvaisCodeEstRefuseCommeUneAbsence() async throws {
        let annuaire = AnnuaireSimule()
        annuaire.posture = .invitation
        let mauvais = try CodeInvitation(saisie: "00000-00000")
        await #expect(throws: ErreurAnnuaire.invitationRefusee) {
            try await annuaire.ouvrirCompte(avec: CleLogicielle(), invitation: mauvais)
        }
    }

    /// Le bon code ouvre le compte.
    @Test func leBonCodeOuvreLeCompte() async throws {
        let annuaire = AnnuaireSimule()
        annuaire.posture = .invitation
        let bon = try CodeInvitation(saisie: AnnuaireSimule.invitationAttendue)
        let compte = try await annuaire.ouvrirCompte(avec: CleLogicielle(), invitation: bon)
        #expect(compte.identifiant.genre == .utilisateur)
    }

    /// Et la posture voyage bien jusqu'à l'écran, par la même lecture que la
    /// version : c'est ce qui décide du champ.
    @Test func laPostureSeLitAvecLaVersion() async throws {
        let annuaire = AnnuaireSimule()
        annuaire.posture = .invitation
        #expect(try await annuaire.version()?.exigeUneInvitation == true)
        annuaire.posture = .optional
        #expect(try await annuaire.version()?.exigeUneInvitation == false)
        annuaire.posture = nil
        #expect(try await annuaire.version()?.exigeUneInvitation == false)
    }
}
