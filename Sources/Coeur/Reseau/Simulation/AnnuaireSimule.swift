import Foundation

/// Un annuaire en mémoire, qui tient les règles de `docs/protocole.md` §2 sans
/// aucun réseau.
///
/// # Pourquoi il existe, et ce qu'il n'est pas
///
/// Le transport de ce produit — HTTP/3 sur QUIC, authentification liée au
/// canal TLS — vit dans `asl-client` et c'est `AnnuaireReel` qui l'embarque.
/// Les écrans ont été écrits avant lui, contre ce banc : les écrire contre une
/// interface qui ment aurait produit des écrans à jeter. Il reste pour les
/// essais, et pour faire tourner l'application sans annuaire sous la main.
///
/// Ce type tient donc **les mêmes refus que le serveur** : un appareil ne se
/// révoque pas lui-même (`403`), un alias pris rend `409`, un objet absent et un
/// objet d'un autre compte rendent le même `404`, une nouvelle annonce du même
/// nom remplace la précédente. Il ne fait rien de plus, et la seule
/// cryptographie qu'il fait est de vérifier la preuve de possession : ce n'est
/// pas un serveur, c'est un banc.
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
    /// La clé sous laquelle chaque appareil enrôlé d'ici est entré — ce que
    /// ``rejoindre(compte:appareil:avec:)`` recoupe.
    private var clesEnrolees: [Identifiant: [UInt8]] = [:]
    private var aretes: [Autorisation] = []
    /// Les autres comptes que cet annuaire connaît : identifiant → alias.
    private var autresComptes: [Identifiant: String?] = [:]

    init(horloge: @escaping Horloge = { Date() }, posture: PostureAnnuaire? = .optional) {
        self.horloge = horloge
        self.posture = posture
    }

    // MARK: - Compte

    /// Le défi en cours. Un seul, et consommé par la première preuve qui le
    /// couvre : un défi rejoué n'est plus un défi.
    private var defiEnCours: [UInt8]?

    /// Il n'y a pas de canal : trente-deux zéros, et le banc le dit. Un
    /// transport réel dérive cette valeur de sa connexion TLS.
    static let liaisonDeCanal = [UInt8](repeating: 0, count: Messages.liaisonOctets)

    /// La posture que ce banc annonce — posée à la construction, comme
    /// l'horloge : un acteur ne se règle pas de l'extérieur après coup, et
    /// un essai qui la changerait en cours de route décrirait un annuaire
    /// qui n'existe pas. Par défaut, celle des racines d'aujourd'hui.
    private let posture: PostureAnnuaire?

    /// Les codes d'invitation refusés, datés : la limite de débit du serveur
    /// (`protocole.md` §2.2) — cinq échecs par minute, puis `429`. Le banc
    /// n'a qu'une adresse, donc un seul compteur.
    private var echecsDInvitation: [Date] = []
    static let echecsParFenetre = 5
    static let fenetreDesEchecs: TimeInterval = 60

    func ouvrirCompte(avec signataire: any Signataire, invitation: CodeInvitation?) async throws -> Compte {
        if let compteLocal { return compteLocal }
        // Le banc tient la règle du serveur : sous `invitation`, un code est
        // exigé, et sous toute autre posture il n'a rien à recevoir.
        if posture == .invitation {
            // Sans code, la plate-forme n'est pas `3` : refusé, et pas compté.
            guard let invitation else { throw ErreurAnnuaire.invitationRefusee }
            // **LA LIMITE DE DÉBIT, AVANT DE REGARDER LE CODE**, comme le
            // serveur : cinq échecs dans la minute, et le sixième essai rend
            // `429` — même juste, il n'est pas examiné.
            let maintenant = horloge()
            echecsDInvitation.removeAll { maintenant.timeIntervalSince($0) >= Self.fenetreDesEchecs }
            guard echecsDInvitation.count < Self.echecsParFenetre else { throw ErreurAnnuaire.tropDEssais }
            guard invitation.symboles == Self.invitationAttendue else {
                echecsDInvitation.append(maintenant)
                throw ErreurAnnuaire.invitationRefusee
            }
        } else if invitation != nil {
            throw ErreurAnnuaire.requeteInvalide("cet annuaire n'attend pas d'invitation")
        }
        // Un défi neuf, à usage unique, puis la preuve — signée par le
        // signataire, sur le message que le serveur recomposera.
        let defi = (0..<Messages.defiOctets).map { _ in UInt8.random(in: .min ... .max) }
        let cle = signataire.clePublique
        let message = Messages.dePossession(cle: cle, defi: defi, liaison: Self.liaisonDeCanal)
        let preuve: [UInt8]
        do {
            preuve = try await signataire.signer(message)
        } catch {
            throw ErreurAnnuaire.nonConfirme
        }
        // Le banc vérifie la preuve comme le serveur le fera : sous la clé
        // présentée, sur ce défi-là. C'est la seule cryptographie qu'il fait,
        // et c'est celle qui éprouve la clé de l'appareil.
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

    func rejoindre(compte: Identifiant, appareil: Identifiant, avec signataire: any Signataire) async throws -> Compte {
        // Le banc ne connaît qu'un compte, et les appareils qu'on y a enrôlés
        // avec leur clé : l'invitation doit désigner l'un d'eux, sous la clé
        // que le signataire présente. Puis la preuve, comme le serveur
        // l'exigerait à la connexion : le message d'authentification, sous
        // le genre `a`.
        guard let compteLocal, compteLocal.identifiant == compte,
              parcAppareils.contains(where: { $0.id == appareil && $0.revoqueLe == nil }),
              clesEnrolees[appareil] == signataire.clePublique else { throw ErreurAnnuaire.introuvable }
        let defi = (0..<Messages.defiOctets).map { _ in UInt8.random(in: .min ... .max) }
        let message = Messages.aSigner(appareil: appareil, defi: defi, liaison: Self.liaisonDeCanal)
        let preuve: [UInt8]
        do {
            preuve = try await signataire.signer(message)
        } catch {
            throw ErreurAnnuaire.nonConfirme
        }
        guard VerificationAppareil.verifie(cle: signataire.clePublique, message: message, signature: preuve) else {
            throw ErreurAnnuaire.preuveInvalide
        }
        // Désormais, c'est CET appareil qui regarde l'écran.
        parcAppareils = parcAppareils.map { unAppareil in
            var copie = unAppareil
            copie.estCeluiCi = unAppareil.id == appareil
            if copie.estCeluiCi { copie.nom = "Cet appareil" }
            return copie
        }
        return compteLocal
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

    func enrolerAppareil(cle: [UInt8]) async throws -> Appareil {
        guard compteLocal != nil else { throw ErreurAnnuaire.introuvable }
        // Le serveur vérifie que la clé est un point de la courbe ; le banc,
        // qu'elle en a la forme. Une clé déjà enrôlée ne s'enrôle pas deux fois.
        guard cle.count == Messages.cleOctets, cle[0] == 0x02 || cle[0] == 0x03 else { throw ErreurAnnuaire.requeteInvalide("clé") }
        guard !clesEnrolees.values.contains(cle) else { throw ErreurAnnuaire.requeteInvalide("clé déjà enrôlée") }
        let appareil = Appareil(id: Self.neuf(.appareil), nom: "Autre appareil", biometrie: .empreinte,
                                enroleLe: horloge(), revoqueLe: nil, estCeluiCi: false)
        parcAppareils.append(appareil)
        clesEnrolees[appareil.id] = cle
        return appareil
    }

    /// Le banc efface tout ce qui est au compte : ce qu'il reste ne prouve
    /// plus rien — la clé qui demandait est révoquée avec les autres.
    func effacerCompte() async throws {
        guard compteLocal != nil else { throw ErreurAnnuaire.nonConfirme }
        compteLocal = nil
        parcAppareils = []
        parcMachines = []
        clesEnrolees = [:]
        aretes = []
    }

    func revoquerAppareil(_ id: Identifiant) async throws {
        guard let indice = parcAppareils.firstIndex(where: { $0.id == id }) else {
            throw ErreurAnnuaire.introuvable
        }
        guard !parcAppareils[indice].estCeluiCi else { throw ErreurAnnuaire.interdit }
        parcAppareils[indice].revoqueLe = horloge()
    }

    /// Pour soi seulement : le banc, comme le serveur, ne connaît que
    /// l'appareil qui parle. Sans compte, il n'y a personne à décrire.
    func decrire(_ description: Appareil.Description) async throws {
        guard let indice = parcAppareils.firstIndex(where: \.estCeluiCi) else { throw ErreurAnnuaire.introuvable }
        let octets = description.modele.utf8.count
        guard octets >= 1, octets <= Appareil.Description.modeleOctetsMax else { throw ErreurAnnuaire.requeteInvalide("modele") }
        parcAppareils[indice].description = description
    }

    // MARK: - Autorisations

    func autorisations() async throws -> [Autorisation] { aretes }

    /// Le banc dit ce qu'il est, pour que l'écran ne confonde jamais une
    /// démonstration avec un annuaire.
    nonisolated var nom: String { "banc en mémoire" }
    func version() async throws -> VersionAnnuaire? {
        VersionAnnuaire(version: "banc en mémoire", posture: posture)
    }

    /// Le seul code que ce banc accepte, sous la posture `invitation`.
    static let invitationAttendue = "4K9M2P7R1T"

    // MARK: - Les nouvelles

    /// L'écoute en cours, s'il y en a une — une seule, comme sur le fil.
    private var ecoute: AsyncStream<Void>.Continuation?

    /// Le banc n'a pas de connexion à perdre : une écoute s'ouvre dès qu'il
    /// y a un compte, et vit jusqu'à ``couperLesNouvelles()``.
    func nouvelles() async -> AsyncStream<Void>? {
        guard compteLocal != nil, ecoute == nil else { return nil }
        let (flux, suite) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        ecoute = suite
        return flux
    }

    func connexionTenue() async -> Bool { compteLocal != nil }

    /// Ce que l'annuaire écrit sur `GET /v1/nouvelles` quand un accès change
    /// pour ce compte : `{"quoi":"autorisation"}`, et rien d'autre.
    func annoncerUneNouvelle() {
        ecoute?.yield()
    }

    /// La connexion tombe : le flux se termine, et ne se rouvre qu'à la
    /// demande — comme sur le fil, où reconnecter est un geste.
    func couperLesNouvelles() {
        ecoute?.finish()
        ecoute = nil
    }

    func utilisateurExiste(_ id: Identifiant) async throws -> Bool {
        id == compteLocal?.identifiant || autresComptes[id] != nil
    }

    /// Le banc tient la même règle que le serveur : mes machines si c'est
    /// moi ; sinon ce que les arêtes vivantes de `u` vers moi nomment —
    /// « tout » ouvre chacune, une machine elle-même, un service celle qui
    /// le porte ; et rien, vide, sans arête. Le banc n'a de machines que
    /// pour le compte local : les autres comptes rendent vide.
    func machines(de utilisateur: Identifiant) async throws -> [MachineVisible] {
        guard let compteLocal else { throw ErreurAnnuaire.introuvable }
        if utilisateur == compteLocal.identifiant {
            return parcMachines.map { MachineVisible(id: $0.id, nom: $0.nom) }
        }
        return []
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
