import Foundation
import Testing
@testable import AirServiceLocator

/// Les refus de `docs/protocole.md` §2, tenus par le banc.
struct AnnuaireSimuleEssais {
    private func annuaireAvecCompte() async throws -> (AnnuaireSimule, Compte) {
        let annuaire = AnnuaireSimule(horloge: { Date(timeIntervalSince1970: 1_700_000_000) })
        let compte = try await annuaire.ouvrirCompte(avec: CleLogicielle())
        return (annuaire, compte)
    }

    /// Un signataire qui présente une clé et signe avec une AUTRE : sa preuve
    /// ne vérifie pas, et le banc doit le dire.
    private struct Usurpateur: Signataire {
        let presentee = CleLogicielle()
        let signe = CleLogicielle()
        var clePublique: [UInt8] { presentee.clePublique }
        func signer(_ message: [UInt8]) async throws -> [UInt8] { try await signe.signer(message) }
    }

    /// Un signataire dont le porteur ne confirme jamais.
    private struct Refus: Signataire {
        let cle = CleLogicielle()
        var clePublique: [UInt8] { cle.clePublique }
        func signer(_ message: [UInt8]) async throws -> [UInt8] { throw CleAppareil.Erreur.signature("annulé") }
    }

    @Test func ouvrirUnCompteExigeUnePreuveSousLaClePresentee() async throws {
        let annuaire = AnnuaireSimule()
        await #expect(throws: ErreurAnnuaire.preuveInvalide) { try await annuaire.ouvrirCompte(avec: Usurpateur()) }
        await #expect(throws: ErreurAnnuaire.nonConfirme) { try await annuaire.ouvrirCompte(avec: Refus()) }
        let compte = try await annuaire.ouvrirCompte(avec: CleLogicielle())
        #expect(compte.identifiant.genre == .utilisateur)
        // Une seconde ouverture rend le même compte, sans redemander de preuve.
        #expect(try await annuaire.ouvrirCompte(avec: Refus()) == compte)
    }

    @Test func unAppareilNeSeRevoquePasLuiMeme() async throws {
        let (annuaire, _) = try await annuaireAvecCompte()
        let moi = try #require(try await annuaire.appareils().first { $0.estCeluiCi })
        await #expect(throws: ErreurAnnuaire.interdit) { try await annuaire.revoquerAppareil(moi.id) }
    }

    @Test func unAppareilRevoqueResteMarque() async throws {
        let (annuaire, _) = try await annuaireAvecCompte()
        let autre = Appareil(id: Identifiant(genre: .appareil, octets: [UInt8](repeating: 7, count: 16)), nom: "autre",
                             biometrie: .empreinte, enroleLe: .now, revoqueLe: nil, estCeluiCi: false)
        await annuaire.poser(autre)
        try await annuaire.revoquerAppareil(autre.id)
        let liste = try await annuaire.appareils()
        #expect(liste.count == 2)
        #expect(liste.first { $0.id == autre.id }?.estRevoque == true)
    }

    @Test func unAliasPrisRendConflit() async throws {
        let (annuaire, _) = try await annuaireAvecCompte()
        await annuaire.inscrireAutreCompte(Identifiant(genre: .utilisateur, octets: [UInt8](repeating: 9, count: 16)), alias: "vero")
        await #expect(throws: ErreurAnnuaire.aliasPris) { try await annuaire.definirAlias("VERO") }
        try await annuaire.definirAlias("thierry")
        #expect(try await annuaire.compte()?.alias == "thierry")
        try await annuaire.definirAlias(nil)
        #expect(try await annuaire.compte()?.alias == nil)
    }

    @Test func declarerRendUnCodeEtPasDeCle() async throws {
        let (annuaire, _) = try await annuaireAvecCompte()
        let machine = try await annuaire.declarerMachine(nom: "grenier", capacites: [.annonce])
        guard case let .attendue(.some(code)) = machine.cle else { Issue.record("une machine déclarée attend son code"); return }
        #expect(code.symboles.count == 10)
        #expect(code.estValide(a: Date(timeIntervalSince1970: 1_700_000_599)))
        #expect(!code.estValide(a: Date(timeIntervalSince1970: 1_700_000_600)))
    }

    @Test func leCodePrecedentMeurtALemissionDuSuivant() async throws {
        let (annuaire, _) = try await annuaireAvecCompte()
        let machine = try await annuaire.declarerMachine(nom: "grenier", capacites: [])
        let second = try await annuaire.emettreCode(pour: machine.id)
        let relue = try #require(try await annuaire.machines().first)
        #expect(relue.cle == .attendue(code: second))
    }

    @Test func unPatchVideEstRefuse() async throws {
        let (annuaire, _) = try await annuaireAvecCompte()
        let machine = try await annuaire.declarerMachine(nom: "grenier", capacites: [])
        await #expect(throws: ErreurAnnuaire.requeteInvalide("{}")) {
            try await annuaire.modifierMachine(machine.id, nom: nil, capacites: nil)
        }
        let renommee = try await annuaire.modifierMachine(machine.id, nom: "cave", capacites: nil)
        #expect(renommee.nom == "cave")
        #expect(renommee.capacites.isEmpty)
    }

    @Test func retirerLannonceFaitTomberLesBaux() async throws {
        let (annuaire, _) = try await annuaireAvecCompte()
        var machine = Machine(id: Identifiant(genre: .machine, octets: [UInt8](repeating: 3, count: 16)), nom: "nas",
                              capacites: [.annonce, .lecture], cle: .enrolee(le: .now), services: [])
        machine.services = []
        await annuaire.poser(machine)
        let service = Service(id: Identifiant(genre: .service, octets: [UInt8](repeating: 4, count: 16)), nom: "partage",
                              points: [PointEcoute(protocole: .tcp, port: 445)], etat: .annonce(depuis: .now),
                              joignabilite: [PointEcoute(protocole: .tcp, port: 445): .enCours], candidats: [])
        try await annuaire.annoncer(sur: machine.id, service: service)
        let apres = try await annuaire.modifierMachine(machine.id, nom: nil, capacites: [.lecture])
        guard case .parti(volontaire: false, _) = apres.services[0].etat else {
            Issue.record("les baux doivent tomber quand l'annonce est retirée"); return
        }
    }

    @Test func uneAnnonceDuMemeNomRemplaceLaPrecedente() async throws {
        let (annuaire, _) = try await annuaireAvecCompte()
        let machine = Machine(id: Identifiant(genre: .machine, octets: [UInt8](repeating: 3, count: 16)), nom: "nas",
                              capacites: [.annonce], cle: .enrolee(le: .now), services: [])
        await annuaire.poser(machine)
        func annonce(port: UInt16) -> Service {
            Service(id: Identifiant(genre: .service, octets: [UInt8](repeating: 4, count: 16)), nom: "partage",
                    points: [PointEcoute(protocole: .tcp, port: port)], etat: .annonce(depuis: .now), joignabilite: [:], candidats: [])
        }
        try await annuaire.annoncer(sur: machine.id, service: annonce(port: 445))
        try await annuaire.annoncer(sur: machine.id, service: annonce(port: 4_450))
        let relue = try #require(try await annuaire.machines().first)
        #expect(relue.services.count == 1)
        #expect(relue.services[0].points[0].port == 4_450)
    }

    @Test func accorderExigeQueLeBeneficiaireExiste() async throws {
        let (annuaire, _) = try await annuaireAvecCompte()
        let inconnu = Identifiant(genre: .utilisateur, octets: [UInt8](repeating: 0xAB, count: 16))
        await #expect(throws: ErreurAnnuaire.introuvable) {
            try await annuaire.accorder(a: inconnu, portee: .tout, etiquette: "")
        }
        await annuaire.inscrireAutreCompte(inconnu, alias: nil)
        let arete = try await annuaire.accorder(a: inconnu, portee: .tout, etiquette: "ami")
        try await annuaire.revoquerAutorisation(arete.id)
        let liste = try await annuaire.autorisations()
        #expect(liste.count == 1)
        #expect(liste[0].estRevoquee)
    }

    @Test func revoquerUneAutorisationRecueRendLeMeme404() async throws {
        let (annuaire, compte) = try await annuaireAvecCompte()
        let autre = Identifiant(genre: .utilisateur, octets: [UInt8](repeating: 0xCD, count: 16))
        let recue = Autorisation(id: Identifiant(genre: .autorisation, octets: [UInt8](repeating: 0xEF, count: 16)),
                                 accordeePar: autre, accordeeA: compte.identifiant, portee: .tout, etiquette: "",
                                 accordeeLe: .now, revoqueeLe: nil)
        await annuaire.recevoir(recue)
        await #expect(throws: ErreurAnnuaire.introuvable) { try await annuaire.revoquerAutorisation(recue.id) }
    }
}
