import Foundation

/// Un annuaire en mémoire, qui tient les règles de `docs/protocole.md` §2 sans
/// aucun réseau.
///
/// # Pourquoi il existe, et ce qu'il n'est pas
///
/// Le transport de ce produit — HTTP/3 sur QUIC, authentification liée au
/// canal TLS — vit dans `asl-client` et n'est pas encore embarqué ici. Attendre
/// qu'il le soit pour écrire les écrans les aurait fait attendre ; les écrire
/// contre une interface qui ment aurait produit des écrans à jeter.
///
/// Ce type tient donc **les mêmes refus que le serveur** : un appareil ne se
/// révoque pas lui-même (`403`), un alias pris rend `409`, un objet absent et un
/// objet d'un autre compte rendent le même `404`, une nouvelle annonce du même
/// nom remplace la précédente. Il ne fait rien de plus, et surtout il **ne
/// vérifie aucune signature** : ce n'est pas un serveur, c'est un banc.
///
/// **Il part vide.** ``AnnuaireSimule/deDemonstration()`` le remplit de ce que
/// les maquettes montraient, pour qu'un écran ait quelque chose à afficher.
actor AnnuaireSimule: Annuaire {
    /// L'heure vient de l'extérieur : un essai la fixe, l'application la lit.
    typealias Horloge = @Sendable () -> Date

    private let horloge: Horloge
    private var compteLocal: Compte?
    private var parcMachines: [Machine] = []
    private var parcAppareils: [Appareil] = []
    private var aretes: [Autorisation] = []
    /// Les autres comptes que cet annuaire connaît : identifiant → alias.
    private var autresComptes: [Identifiant: String?] = [:]

    init(horloge: @escaping Horloge = { Date() }) {
        self.horloge = horloge
    }

    // MARK: - Compte

    /// Le défi en cours. Un seul, et consommé par la première preuve qui le
    /// couvre : un défi rejoué n'est plus un défi.
    private var defiEnCours: [UInt8]?

    func defi() async throws -> [UInt8] {
        let defi = (0..<Messages.defiOctets).map { _ in UInt8.random(in: .min ... .max) }
        defiEnCours = defi
        return defi
    }

    /// Il n'y a pas de canal : trente-deux zéros, et le banc le dit. Un
    /// transport réel dérive cette valeur de sa connexion TLS.
    func liaisonDeCanal() async throws -> [UInt8] { [UInt8](repeating: 0, count: Messages.liaisonOctets) }

    func ouvrirCompte(cle: [UInt8], preuve: [UInt8]) async throws -> Compte {
        if let compteLocal { return compteLocal }
        // Le banc vérifie la preuve comme le serveur le fera : sous la clé
        // présentée, sur le défi qu'il a émis. C'est la seule cryptographie
        // qu'il fait, et c'est celle qui éprouve la clé de l'appareil.
        guard let defi = defiEnCours else { throw ErreurAnnuaire.requeteInvalide("aucun défi en cours") }
        defiEnCours = nil
        let message = Messages.dePossession(cle: cle, defi: defi, liaison: try await liaisonDeCanal())
        guard VerificationAppareil.verifie(cle: cle, message: message, signature: preuve) else {
            throw ErreurAnnuaire.preuveInvalide
        }
        let compte = Compte(identifiant: Self.neuf(.utilisateur))
        compteLocal = compte
        parcAppareils = [Appareil(
            id: Self.neuf(.appareil), nom: "Cet appareil", biometrie: .visage,
            enroleLe: horloge(), revoqueLe: nil, estCeluiCi: true
        )]
        return compte
    }

    func compte() async throws -> Compte? { compteLocal }

    func definirAlias(_ alias: String?) async throws {
        guard compteLocal != nil else { throw ErreurAnnuaire.introuvable }
        if let alias {
            guard Self.aliasValide(alias) else { throw ErreurAnnuaire.requeteInvalide("alias") }
            if autresComptes.values.contains(where: { $0?.lowercased() == alias.lowercased() }) {
                throw ErreurAnnuaire.aliasPris
            }
        }
        compteLocal?.alias = alias
    }

    /// Un alias se compare : ASCII, minuscules, chiffres, tiret, 3 à 32.
    static func aliasValide(_ alias: String) -> Bool {
        (3...32).contains(alias.count)
            && alias.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    // MARK: - Machines

    func machines() async throws -> [Machine] { parcMachines }

    func declarerMachine(nom: String, capacites: Set<Capacite>) async throws -> Machine {
        guard compteLocal != nil else { throw ErreurAnnuaire.introuvable }
        guard Machine.nomValide(nom) else { throw ErreurAnnuaire.requeteInvalide("nom") }
        let machine = Machine(
            id: Self.neuf(.machine), nom: nom, capacites: capacites,
            cle: .attendue(code: Self.code(horloge())), services: []
        )
        parcMachines.append(machine)
        return machine
    }

    func modifierMachine(_ id: Identifiant, nom: String?, capacites: Set<Capacite>?) async throws -> Machine {
        guard nom != nil || capacites != nil else { throw ErreurAnnuaire.requeteInvalide("{}") }
        let indice = try indiceMachine(id)
        if let nom {
            guard Machine.nomValide(nom) else { throw ErreurAnnuaire.requeteInvalide("nom") }
            parcMachines[indice].nom = nom
        }
        if let capacites {
            // Retirer la capacité d'annonce ferme les connexions, donc fait
            // tomber les baux : les services partent, comme à un arrêt.
            if parcMachines[indice].capacites.contains(.annonce), !capacites.contains(.annonce) {
                fermerConnexions(indice)
            }
            parcMachines[indice].capacites = capacites
        }
        return parcMachines[indice]
    }

    func emettreCode(pour machine: Identifiant) async throws -> CodeEnrolement {
        let indice = try indiceMachine(machine)
        let code = Self.code(horloge())
        switch parcMachines[indice].cle {
        case .attendue: parcMachines[indice].cle = .attendue(code: code)
        case .enrolee: throw ErreurAnnuaire.requeteInvalide("la machine est déjà enrôlée")
        case let .revoquee(le, _): parcMachines[indice].cle = .revoquee(le: le, code: code)
        }
        return code
    }

    func revoquerCle(de machine: Identifiant) async throws {
        let indice = try indiceMachine(machine)
        guard case .enrolee = parcMachines[indice].cle else { throw ErreurAnnuaire.introuvable }
        parcMachines[indice].cle = .revoquee(le: horloge(), code: nil)
        fermerConnexions(indice)
    }

    private func indiceMachine(_ id: Identifiant) throws -> Int {
        guard let indice = parcMachines.firstIndex(where: { $0.id == id }) else {
            throw ErreurAnnuaire.introuvable
        }
        return indice
    }

    private func fermerConnexions(_ indice: Int) {
        let instant = horloge()
        for i in parcMachines[indice].services.indices {
            parcMachines[indice].services[i].etat = .parti(volontaire: false, le: instant)
            parcMachines[indice].services[i].joignabilite = [:]
        }
    }

    // MARK: - Appareils

    func appareils() async throws -> [Appareil] { parcAppareils }

    func revoquerAppareil(_ id: Identifiant) async throws {
        guard let indice = parcAppareils.firstIndex(where: { $0.id == id }) else {
            throw ErreurAnnuaire.introuvable
        }
        guard !parcAppareils[indice].estCeluiCi else { throw ErreurAnnuaire.interdit }
        parcAppareils[indice].revoqueLe = horloge()
    }

    // MARK: - Autorisations

    func autorisations() async throws -> [Autorisation] { aretes }

    func utilisateurExiste(_ id: Identifiant) async throws -> Bool {
        id == compteLocal?.identifiant || autresComptes[id] != nil
    }

    func identifiant(pourAlias alias: String) async throws -> Identifiant? {
        if let compteLocal, compteLocal.alias?.lowercased() == alias.lowercased() { return compteLocal.identifiant }
        return autresComptes.first { $0.value?.lowercased() == alias.lowercased() }?.key
    }

    func accorder(a beneficiaire: Identifiant, portee: Autorisation.Portee, etiquette: String) async throws -> Autorisation {
        guard let compteLocal else { throw ErreurAnnuaire.introuvable }
        guard try await utilisateurExiste(beneficiaire) else { throw ErreurAnnuaire.introuvable }
        switch portee {
        case .tout: break
        case let .machine(m): _ = try indiceMachine(m)
        case let .service(s):
            guard parcMachines.contains(where: { $0.services.contains { $0.id == s } }) else {
                throw ErreurAnnuaire.introuvable
            }
        }
        let arete = Autorisation(
            id: Self.neuf(.autorisation), accordeePar: compteLocal.identifiant, accordeeA: beneficiaire,
            portee: portee, etiquette: etiquette, accordeeLe: horloge(), revoqueeLe: nil
        )
        aretes.append(arete)
        return arete
    }

    func revoquerAutorisation(_ id: Identifiant) async throws {
        guard let indice = aretes.firstIndex(where: { $0.id == id && $0.accordeePar == compteLocal?.identifiant }) else {
            throw ErreurAnnuaire.introuvable
        }
        aretes[indice].revoqueeLe = horloge()
    }

    // MARK: - Ce qu'un annuaire de démonstration porte

    /// Fait arriver une annonce, comme un daemon le ferait. Une annonce du même
    /// nom **remplace** la précédente (`docs/modele.md` §2.4).
    func annoncer(sur machine: Identifiant, service: Service) throws {
        let indice = try indiceMachine(machine)
        guard parcMachines[indice].capacites.contains(.annonce) else { throw ErreurAnnuaire.interdit }
        if let existant = parcMachines[indice].services.firstIndex(where: { $0.nom == service.nom }) {
            parcMachines[indice].services[existant] = service
        } else {
            parcMachines[indice].services.append(service)
        }
    }

    /// Fait exister un autre compte, avec ou sans alias.
    func inscrireAutreCompte(_ id: Identifiant, alias: String?) {
        autresComptes[id] = .some(alias)
    }

    /// Reçoit une autorisation accordée par un autre compte.
    func recevoir(_ autorisation: Autorisation) { aretes.append(autorisation) }

    /// Pose une machine directement, enrôlée ou non — pour un banc.
    func poser(_ machine: Machine) { parcMachines.append(machine) }
    func poser(_ appareil: Appareil) { parcAppareils.append(appareil) }

    private static func neuf(_ genre: Genre) -> Identifiant {
        Identifiant(genre: genre, entropie: (0..<16).map { _ in UInt8.random(in: .min ... .max) })
    }

    private static func code(_ instant: Date) -> CodeEnrolement {
        CodeEnrolement(entropie: (0..<8).map { _ in UInt8.random(in: .min ... .max) }, emisLe: instant)
    }
}
