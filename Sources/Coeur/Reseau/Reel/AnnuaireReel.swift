import CAsl
import Foundation
import OSLog

/// L'annuaire, par le transport réel : la pile QUIC d'`asl-client`, derrière
/// son ABI C (`asl_appareil_*`), embarquée en xcframework.
///
/// # Ce que fait le natif, et ce qui reste ici
///
/// Le natif ouvre la connexion, exporte la liaison de canal, tire le défi,
/// porte la preuve et tient la connexion vivante. **Il ne signe rien** : quand
/// il a besoin d'une signature, il rappelle `signer` de cet objet, sur le fil
/// qui a fait l'appel — et c'est là que la Secure Enclave demande Face ID.
///
/// Ce qui reste ici est ce qu'un téléphone fait mieux qu'une bibliothèque :
/// composer et lire du JSON, et décider quoi montrer d'un `404`.
///
/// # Un seul fil, et jamais le principal
///
/// L'ABI ne se partage pas entre fils, et un rappel de signature bloque le fil
/// qui l'a provoqué le temps du geste. Tout passe donc par `file`, une file
/// série de fond : les méthodes `async` y déposent leur travail et attendent.
///
/// # Ce que le serveur ne sert pas encore, et comment on l'attend
///
/// `GET /v1/machines` et `GET /v1/appareils` n'existent pas encore côté
/// serveur (voir `CLAUDE.md` du dépôt client). Les machines que CET appareil a
/// déclarées sont donc retenues localement, et l'écran le dit : un second
/// appareil du même compte ne les verrait pas. Le jour où le verbe existe,
/// `machines()` le préfère, et le carnet local n'est plus qu'un cache.
final class AnnuaireReel: Annuaire, @unchecked Sendable {
    /// Où est l'annuaire, sous quel nom, et qui a signé son certificat.
    struct Reglages: Sendable {
        let adresse: String
        let nom: String
        let racinesPEM: Data
    }

    enum ErreurNative: Error {
        case code(Int32, String)
    }

    /// Ce que le natif fait, pas à pas — pour lire une connexion qui n'aboutit
    /// pas sans deviner.
    private static let journal = Logger(subsystem: "org.airdesktop.servicelocator", category: "annuaire")
    private let file = DispatchQueue(label: "org.airdesktop.servicelocator.annuaire", qos: .userInitiated)
    private let reglages: Reglages
    private let signataire: @Sendable () throws -> any Signataire
    private var handle: OpaquePointer?
    private var cleCourante: (any Signataire)?

    init(reglages: Reglages, signataire: @escaping @Sendable () throws -> any Signataire) {
        self.reglages = reglages
        self.signataire = signataire
    }

    deinit {
        if let handle { asl_appareil_libere(handle) }
    }

    // MARK: - Le natif

    /// Exécute `travail` sur la file de fond, et rend ce qu'il rend.
    private func surLaFile<T: Sendable>(_ travail: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { suite in
            file.async {
                suite.resume(with: Result { try travail() })
            }
        }
    }

    /// Le handle, créé et réglé à la première demande.
    private func handleOuCreer() throws -> OpaquePointer {
        if let handle { return handle }
        var neuf: OpaquePointer?
        try exiger(asl_appareil_neuf(&neuf), "asl_appareil_neuf")
        guard let neuf else { throw ErreurNative.code(ASL_INTERNE, "handle nul") }
        try exiger(asl_appareil_annuaire(neuf, reglages.adresse, reglages.nom), "asl_appareil_annuaire")
        try reglages.racinesPEM.withUnsafeBytes { pem in
            try exiger(asl_appareil_racines(neuf, pem.bindMemory(to: UInt8.self).baseAddress, pem.count), "asl_appareil_racines")
        }
        let cle = try signataire()
        cleCourante = cle
        let contexte = Unmanaged.passUnretained(self).toOpaque()
        try cle.clePublique.withUnsafeBufferPointer { octets in
            try exiger(asl_appareil_cle(neuf, octets.baseAddress, Self.rappel, contexte), "asl_appareil_cle")
        }
        if let appareil = Carnet.appareilEnrole {
            try exiger(asl_appareil_identite(neuf, appareil.texte), "asl_appareil_identite")
        }
        handle = neuf
        return neuf
    }

    /// Le rappel de signature, tel que le natif l'appelle : sur le fil de
    /// l'appel en cours, donc sur `file`. On bloque ce fil le temps que la
    /// clé signe — et que le porteur pose son doigt.
    private static let rappel: asl_signataire = { contexte, message, taille, signature in
        guard let contexte, let message, let signature else { return ASL_ARGUMENT }
        let moi = Unmanaged<AnnuaireReel>.fromOpaque(contexte).takeUnretainedValue()
        let octets = Array(UnsafeBufferPointer(start: message, count: taille))
        guard let signee = moi.signerBloquant(octets), signee.count == Int(ASL_SIGNATURE_OCTETS) else {
            return 1
        }
        signee.withUnsafeBufferPointer { source in
            signature.update(from: source.baseAddress!, count: signee.count)
        }
        return 0
    }

    private func signerBloquant(_ message: [UInt8]) -> [UInt8]? {
        Self.journal.notice("rappel de signature : \(message.count) octets")
        guard let cle = cleCourante else { return nil }
        let attente = DispatchSemaphore(value: 0)
        let boite = Boite()
        Task.detached {
            do {
                boite.valeur = try await cle.signer(message)
            } catch {
                Self.journal.error("la clé n'a pas signé : \(String(describing: error), privacy: .public)")
            }
            attente.signal()
        }
        attente.wait()
        return boite.valeur
    }

    private final class Boite: @unchecked Sendable {
        var valeur: [UInt8]?
    }

    /// Un tampon C terminé par NUL, en texte.
    private static func texte(_ tampon: [CChar]) -> String {
        let octets = tampon.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: octets, as: UTF8.self)
    }

    private func exiger(_ code: Int32, _ quoi: String) throws {
        Self.journal.notice("\(quoi, privacy: .public) → \(code)")
        guard code == ASL_OK else { throw ErreurNative.code(code, quoi) }
    }

    /// Ouvre la connexion — et prouve la clé si l'appareil est enrôlé. C'est
    /// ici que Face ID est demandé, une fois par connexion.
    private func connecter() throws {
        let handle = try handleOuCreer()
        Self.journal.notice("connexion à \(self.reglages.adresse, privacy: .public)…")
        try exiger(asl_appareil_connecter(handle), "asl_appareil_connecter")
    }

    private func connecte() -> Bool {
        var statut: UInt16 = 0
        var ecrit = 0
        guard let handle else { return false }
        // Une requête à vide dit si la tenue vit : `ASL_NON_CONNECTE` sinon.
        return asl_appareil_requete(handle, "GET", "/v1/vu", nil, 0, nil, 0, &ecrit, &statut) != ASL_NON_CONNECTE
    }

    /// Une requête de `protocole.md` §2 : méthode, chemin, corps JSON.
    private func requete(_ methode: String, _ chemin: String, _ corps: Data? = nil) throws -> (statut: Int, corps: Data) {
        let handle = try handleOuCreer()
        if !connecte() { try connecter() }
        var sortie = [UInt8](repeating: 0, count: 64 * 1024)
        var ecrit = 0
        var statut: UInt16 = 0
        let code = sortie.withUnsafeMutableBufferPointer { tampon -> Int32 in
            if let corps, !corps.isEmpty {
                return corps.withUnsafeBytes { octets in
                    asl_appareil_requete(handle, methode, chemin, octets.bindMemory(to: UInt8.self).baseAddress, corps.count,
                                         tampon.baseAddress, tampon.count, &ecrit, &statut)
                }
            }
            return asl_appareil_requete(handle, methode, chemin, nil, 0, tampon.baseAddress, tampon.count, &ecrit, &statut)
        }
        try exiger(code, "\(methode) \(chemin)")
        return (Int(statut), Data(sortie.prefix(ecrit)))
    }

    /// Traduit un code d'état en refus, tel que l'écran le dira.
    private static func refus(_ statut: Int) -> ErreurAnnuaire {
        switch statut {
        case 404: .introuvable
        case 403: .interdit
        case 409: .aliasPris
        case 401: .nonConfirme
        case 501: .nonImplemente
        default: .requeteInvalide("l'annuaire a répondu \(statut)")
        }
    }

    private static func json(_ corps: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: corps)
    }

    private static func encoder(_ objet: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: objet)
    }

    private static func millis(_ valeur: Any?) -> Date? {
        guard let ms = valeur as? Double else { return nil }
        return Date(timeIntervalSince1970: ms / 1_000)
    }

    // MARK: - Compte

    func ouvrirCompte(avec signataire: any Signataire) async throws -> Compte {
        try await surLaFile {
            if let compte = Carnet.compte { return compte }
            let handle = try self.handleOuCreer()
            if !self.connecte() { try self.connecter() }
            var compte = [CChar](repeating: 0, count: Int(ASL_IDENTIFIANT_OCTETS))
            var appareil = [CChar](repeating: 0, count: Int(ASL_IDENTIFIANT_OCTETS))
            let code = asl_appareil_creer_compte(handle, UInt8(ASL_PLATEFORME_AUCUNE), nil, 0, &compte, &appareil)
            switch code {
            case ASL_OK: break
            case ASL_SIGNATURE_REFUSEE: throw ErreurAnnuaire.nonConfirme
            case ASL_REFUSE: throw ErreurAnnuaire.preuveInvalide
            default: throw ErreurNative.code(code, "asl_appareil_creer_compte")
            }
            let cree = Compte(identifiant: try Identifiant.analyser(Self.texte(compte), genre: .utilisateur))
            Carnet.compte = cree
            Carnet.appareilEnrole = try Identifiant.analyser(Self.texte(appareil), genre: .appareil)
            return cree
        }
    }

    func rejoindre(compte: Identifiant, appareil: Identifiant, avec signataire: any Signataire) async throws -> Compte {
        // Le natif signe avec la clé qu'on lui a donnée à la création du
        // handle — la même que `signataire`, celle de l'enclave. Le paramètre
        // dit où le geste est demandé, pas avec quoi.
        _ = signataire
        try await surLaFile {
            let handle = try self.handleOuCreer()
            try self.exiger(asl_appareil_identite(handle, appareil.texte), "asl_appareil_identite")
            // Se connecter sous cette identité, c'est la prouver : le natif
            // ferme la connexion nue s'il y en a une, et rappelle la clé.
            Self.journal.notice("connexion à \(self.reglages.adresse, privacy: .public) en tant que \(appareil.texte, privacy: .public)…")
            let code = asl_appareil_connecter(handle)
            Self.journal.notice("asl_appareil_connecter → \(code)")
            switch code {
            case ASL_OK: break
            case ASL_SIGNATURE_REFUSEE: throw ErreurAnnuaire.nonConfirme
            case ASL_REFUSE: throw ErreurAnnuaire.preuveInvalide
            case ASL_INJOIGNABLE: throw ErreurAnnuaire.reseau("aucun annuaire ne répond")
            default: throw ErreurNative.code(code, "asl_appareil_connecter")
            }
        }
        // La preuve tient : c'est bien la clé que l'autre téléphone a enrôlée.
        // Le compte, lui, ne se vérifie qu'en le lisant.
        let (statut, corps) = try await surLaFile { try self.requete("GET", "/v1/utilisateurs/\(compte.texte)") }
        guard statut == 200 else { throw Self.refus(statut) }
        var rejoint = Compte(identifiant: compte)
        if let objet = try Self.json(corps) as? [String: Any] { rejoint.alias = objet["alias"] as? String }
        Carnet.vider()
        Carnet.compte = rejoint
        Carnet.appareilEnrole = appareil
        return rejoint
    }

    func compte() async throws -> Compte? {
        guard var compte = Carnet.compte else { return nil }
        let identifiant = compte.identifiant
        // Se connecter au lancement, c'est prouver la clé : Face ID, une fois.
        try await surLaFile { if !self.connecte() { try self.connecter() } }
        let (statut, corps) = try await surLaFile { try self.requete("GET", "/v1/utilisateurs/\(identifiant.texte)") }
        if statut == 200, let objet = try Self.json(corps) as? [String: Any] {
            compte.alias = objet["alias"] as? String
            Carnet.compte = compte
        }
        return compte
    }

    func definirAlias(_ alias: String?) async throws {
        let (statut, _) = try await surLaFile {
            if let alias {
                try self.requete("PUT", "/v1/alias", try Self.encoder(["alias": alias]))
            } else {
                try self.requete("DELETE", "/v1/alias")
            }
        }
        guard statut == 204 else { throw Self.refus(statut) }
        if var compte = Carnet.compte { compte.alias = alias; Carnet.compte = compte }
    }

    // MARK: - Machines

    func machines() async throws -> [Machine] {
        let (statut, corps) = try await surLaFile { try self.requete("GET", "/v1/machines") }
        var machines: [Machine]
        if statut == 200, let liste = try Self.json(corps) as? [[String: Any]] {
            machines = liste.compactMap(Self.machine(depuis:))
            Carnet.machines = machines.map { Carnet.Fiche(machine: $0) }
        } else {
            // Le verbe n'existe pas encore : ce que cet appareil a déclaré.
            machines = Carnet.machines.map(\.machine)
        }
        for indice in machines.indices {
            machines[indice].services = (try? await services(de: machines[indice].id)) ?? []
        }
        return machines
    }

    private static func machine(depuis objet: [String: Any]) -> Machine? {
        guard let texte = objet["machine"] as? String, let id = try? Identifiant.analyser(texte, genre: .machine),
              let nom = objet["nom"] as? String else { return nil }
        let capacites = Set((objet["capacites"] as? [String] ?? []).compactMap(Capacite.init(rawValue:)))
        let cle: Machine.Cle
        switch objet["cle"] as? String {
        case "enrolee": cle = .enrolee(le: millis(objet["enrolee_a"]) ?? .now)
        case "revoquee": cle = .revoquee(le: millis(objet["revoquee_a"]) ?? .now, code: code(depuis: objet))
        default: cle = .attendue(code: code(depuis: objet) ?? CodeEnrolement(symboles: "0000000000", expireLe: .distantPast))
        }
        return Machine(id: id, nom: nom, capacites: capacites, cle: cle, services: [])
    }

    /// Le code que l'annuaire rend : dix symboles, groupés ou non, et sa date.
    private static func code(depuis objet: [String: Any]) -> CodeEnrolement? {
        guard let texte = objet["code"] as? String, let expire = millis(objet["expire_a"]) else { return nil }
        let symboles = texte.replacingOccurrences(of: "-", with: "").uppercased()
        guard symboles.count == CodeEnrolement.nombreSymboles else { return nil }
        return CodeEnrolement(symboles: symboles, expireLe: expire)
    }

    func declarerMachine(nom: String, capacites: Set<Capacite>) async throws -> Machine {
        let corps = try Self.encoder(["nom": nom, "capacites": Capacite.allCases.filter { capacites.contains($0) }.map(\.rawValue)])
        let (statut, rendu) = try await surLaFile { try self.requete("POST", "/v1/machines", corps) }
        guard statut == 201, let objet = try Self.json(rendu) as? [String: Any],
              let texte = objet["machine"] as? String, let code = Self.code(depuis: objet)
        else { throw Self.refus(statut) }
        let machine = Machine(id: try Identifiant.analyser(texte, genre: .machine), nom: nom, capacites: capacites,
                              cle: .attendue(code: code), services: [])
        Carnet.machines.append(Carnet.Fiche(machine: machine))
        return machine
    }

    func modifierMachine(_ id: Identifiant, nom: String?, capacites: Set<Capacite>?) async throws -> Machine {
        var objet: [String: Any] = [:]
        if let nom { objet["nom"] = nom }
        if let capacites { objet["capacites"] = Capacite.allCases.filter { capacites.contains($0) }.map(\.rawValue) }
        guard !objet.isEmpty else { throw ErreurAnnuaire.requeteInvalide("{}") }
        let corps = try Self.encoder(objet)
        let (statut, _) = try await surLaFile { try self.requete("PATCH", "/v1/machines/\(id.texte)", corps) }
        guard statut == 204 else { throw Self.refus(statut) }
        guard var fiche = Carnet.machines.first(where: { $0.machine.id == id }) else { throw ErreurAnnuaire.introuvable }
        if let nom { fiche.machine.nom = nom }
        if let capacites { fiche.machine.capacites = capacites }
        Carnet.remplacer(fiche)
        return fiche.machine
    }

    func emettreCode(pour machine: Identifiant) async throws -> CodeEnrolement {
        let (statut, rendu) = try await surLaFile { try self.requete("POST", "/v1/machines/\(machine.texte)/enrolement") }
        guard statut == 201, let objet = try Self.json(rendu) as? [String: Any], let code = Self.code(depuis: objet) else {
            throw Self.refus(statut)
        }
        if var fiche = Carnet.machines.first(where: { $0.machine.id == machine }) {
            switch fiche.machine.cle {
            case let .revoquee(le, _): fiche.machine.cle = .revoquee(le: le, code: code)
            default: fiche.machine.cle = .attendue(code: code)
            }
            Carnet.remplacer(fiche)
        }
        return code
    }

    func revoquerCle(de machine: Identifiant) async throws {
        let (statut, _) = try await surLaFile { try self.requete("DELETE", "/v1/machines/\(machine.texte)/cle") }
        guard statut == 204 else { throw Self.refus(statut) }
        if var fiche = Carnet.machines.first(where: { $0.machine.id == machine }) {
            fiche.machine.cle = .revoquee(le: .now, code: nil)
            Carnet.remplacer(fiche)
        }
    }

    /// `GET /v1/machines/{m}/services` — ce que l'annuaire en rend aujourd'hui :
    /// les réponses d'annonce des services vivants, sans leur nom.
    private func services(de machine: Identifiant) async throws -> [Service] {
        let (statut, corps) = try await surLaFile { try self.requete("GET", "/v1/machines/\(machine.texte)/services") }
        guard statut == 200, let liste = try Self.json(corps) as? [[String: Any]] else { return [] }
        return liste.compactMap { objet in
            guard let texte = objet["service"] as? String, let id = try? Identifiant.analyser(texte, genre: .service) else { return nil }
            var points: [PointEcoute] = []
            var joignabilite: [PointEcoute: Joignabilite] = [:]
            var candidats: [Candidat] = []
            for verdict in objet["joignabilite"] as? [[String: Any]] ?? [] {
                guard let protocole = (verdict["protocole"] as? String).flatMap(PointEcoute.Protocole.init(rawValue:)),
                      let port = verdict["port"] as? Int else { continue }
                let point = PointEcoute(protocole: protocole, port: UInt16(clamping: port))
                points.append(point)
                switch verdict["verdict"] as? String {
                case "joignable":
                    let candidat = verdict["candidat"] as? String ?? ""
                    joignabilite[point] = .joignable(depuis: Self.millis(verdict["a"]) ?? .now, candidat: candidat)
                    if let (adresse, portCandidat) = Self.adresseEtPort(candidat) {
                        candidats.append(Candidat(protocole: protocole, adresse: adresse, port: portCandidat, origine: .reflexif))
                    }
                case "injoignable": joignabilite[point] = .injoignable(depuis: Self.millis(verdict["a"]) ?? .now)
                case "non_sonde": joignabilite[point] = .nonSonde
                default: joignabilite[point] = .enCours
                }
            }
            // Ce que l'annuaire a répondu au daemon, tel quel.
            var diagnostic = Diagnostic()
            if let vu = objet["vu_depuis"] as? [String: Any], let adresse = vu["adresse"] as? String, let port = vu["port"] as? Int {
                diagnostic.vuDepuis = adresse.contains(":") ? "[\(adresse)]:\(port)" : "\(adresse):\(port)"
            }
            diagnostic.derriereNat = (objet["derriere_nat"] as? String).flatMap(Diagnostic.Nat.init(rawValue:))
            diagnostic.keepaliveSecondes = objet["keepalive_secondes"] as? Int
            diagnostic.inactiviteSecondes = objet["inactivite_secondes"] as? Int
            // Le nom manque : l'annuaire ne le rend pas encore. L'identifiant
            // abrégé tient sa place, et l'écran ne ment pas.
            return Service(id: id, nom: id.abrege, points: points, etat: .annonce(depuis: .now),
                           joignabilite: joignabilite, candidats: candidats, diagnostic: diagnostic)
        }
    }

    /// `[2001:db8::1]:49152` ou `203.0.113.4:49152`.
    private static func adresseEtPort(_ texte: String) -> (String, UInt16)? {
        guard let deuxPoints = texte.lastIndex(of: ":"), let port = UInt16(texte[texte.index(after: deuxPoints)...]) else { return nil }
        var adresse = String(texte[..<deuxPoints])
        if adresse.hasPrefix("["), adresse.hasSuffix("]") { adresse = String(adresse.dropFirst().dropLast()) }
        return (adresse, port)
    }

    // MARK: - Appareils

    func appareils() async throws -> [Appareil] {
        let (statut, corps) = try await surLaFile { try self.requete("GET", "/v1/appareils") }
        if statut == 200, let liste = try Self.json(corps) as? [[String: Any]] {
            return liste.compactMap { objet in
                guard let texte = objet["appareil"] as? String, let id = try? Identifiant.analyser(texte, genre: .appareil) else { return nil }
                return Appareil(id: id, nom: id.abrege, biometrie: .visage, enroleLe: Self.millis(objet["enrole_a"]) ?? .now,
                                revoqueLe: Self.millis(objet["revoque_a"]), estCeluiCi: id == Carnet.appareilEnrole)
            }
        }
        // Le verbe n'existe pas encore : cet appareil, et ceux qu'il a
        // enrôlés lui-même. Un appareil enrôlé depuis un autre téléphone n'y
        // paraît pas, et l'écran le dit.
        guard let moi = Carnet.appareilEnrole else { return [] }
        return [Appareil(id: moi, nom: "Cet appareil", biometrie: .visage, enroleLe: Carnet.enroleLe ?? .now, revoqueLe: nil, estCeluiCi: true)]
            + Carnet.appareilsEnrolesDIci.compactMap { enrole in
                enrole.id.map { Appareil(id: $0, nom: "Autre appareil", biometrie: .empreinte, enroleLe: enrole.le, revoqueLe: enrole.revoqueLe, estCeluiCi: false) }
            }
    }

    func enrolerAppareil(cle: [UInt8]) async throws -> Appareil {
        // Le seul corps brut de cette voie après la création du compte :
        // trente-trois octets, la clé telle que le nouveau téléphone l'a
        // montrée. C'est le serveur qui vérifie qu'elle est sur la courbe.
        guard cle.count == Messages.cleOctets else { throw ErreurAnnuaire.requeteInvalide("clé") }
        let (statut, rendu) = try await surLaFile { try self.requete("POST", "/v1/appareils", Data(cle)) }
        guard statut == 201, let objet = try Self.json(rendu) as? [String: Any], let texte = objet["appareil"] as? String else {
            throw Self.refus(statut)
        }
        let id = try Identifiant.analyser(texte, genre: .appareil)
        let appareil = Appareil(id: id, nom: "Autre appareil", biometrie: .empreinte, enroleLe: .now, revoqueLe: nil, estCeluiCi: false)
        Carnet.appareilsEnrolesDIci.append(Carnet.AppareilEnrole(id: id, le: .now, revoqueLe: nil))
        return appareil
    }

    func revoquerAppareil(_ id: Identifiant) async throws {
        let (statut, _) = try await surLaFile { try self.requete("DELETE", "/v1/appareils/\(id.texte)") }
        guard statut == 204 else { throw Self.refus(statut) }
        Carnet.appareilsEnrolesDIci = Carnet.appareilsEnrolesDIci.map { appareil in
            var copie = appareil
            if copie.id == id, copie.revoqueLe == nil { copie.revoqueLe = .now }
            return copie
        }
    }

    // MARK: - Autorisations

    func autorisations() async throws -> [Autorisation] {
        let (statut, corps) = try await surLaFile { try self.requete("GET", "/v1/autorisations") }
        guard statut == 200, let liste = try Self.json(corps) as? [[String: Any]] else { throw Self.refus(statut) }
        return liste.compactMap(Self.autorisation(depuis:))
    }

    private static func autorisation(depuis objet: [String: Any]) -> Autorisation? {
        guard let g = objet["autorisation"] as? String, let id = try? Identifiant.analyser(g, genre: .autorisation),
              let p = objet["par"] as? String, let par = try? Identifiant.analyser(p, genre: .utilisateur),
              let a = objet["a"] as? String, let beneficiaire = try? Identifiant.analyser(a, genre: .utilisateur),
              let porteeTexte = objet["portee"] as? String else { return nil }
        let portee: Autorisation.Portee
        if porteeTexte == "tout" {
            portee = .tout
        } else if let cible = try? Identifiant.analyser(porteeTexte) {
            portee = cible.genre == .service ? .service(cible) : .machine(cible)
        } else {
            return nil
        }
        let revoquee = objet["revoquee"] as? Bool ?? false
        return Autorisation(id: id, accordeePar: par, accordeeA: beneficiaire, portee: portee,
                            etiquette: objet["etiquette"] as? String ?? "", accordeeLe: millis(objet["accordee_a"]) ?? .now,
                            revoqueeLe: revoquee ? (millis(objet["revoquee_a"]) ?? .now) : nil)
    }

    func utilisateurExiste(_ id: Identifiant) async throws -> Bool {
        let (statut, _) = try await surLaFile { try self.requete("GET", "/v1/utilisateurs/\(id.texte)") }
        return statut == 200
    }

    func identifiant(pourAlias alias: String) async throws -> Identifiant? {
        let (statut, corps) = try await surLaFile { try self.requete("GET", "/v1/alias/\(alias)") }
        guard statut == 200, let objet = try Self.json(corps) as? [String: Any], let texte = objet["identifiant"] as? String else { return nil }
        return try Identifiant.analyser(texte, genre: .utilisateur)
    }

    func accorder(a beneficiaire: Identifiant, portee: Autorisation.Portee, etiquette: String) async throws -> Autorisation {
        let porteeTexte: String
        switch portee {
        case .tout: porteeTexte = "tout"
        case let .machine(id), let .service(id): porteeTexte = id.texte
        }
        // `etiquette` n'est pas encore un champ du serveur ; elle ne part pas.
        let corps = try Self.encoder(["a": beneficiaire.texte, "portee": porteeTexte])
        let (statut, rendu) = try await surLaFile { try self.requete("POST", "/v1/autorisations", corps) }
        guard statut == 201, let objet = try Self.json(rendu) as? [String: Any], let g = objet["autorisation"] as? String,
              let compte = Carnet.compte else { throw Self.refus(statut) }
        return Autorisation(id: try Identifiant.analyser(g, genre: .autorisation), accordeePar: compte.identifiant, accordeeA: beneficiaire,
                            portee: portee, etiquette: etiquette, accordeeLe: .now, revoqueeLe: nil)
    }

    func revoquerAutorisation(_ id: Identifiant) async throws {
        let (statut, _) = try await surLaFile { try self.requete("DELETE", "/v1/autorisations/\(id.texte)") }
        guard statut == 204 else { throw Self.refus(statut) }
    }
}

/// Ce que cet appareil retient de lui-même, et ce que le serveur ne sait pas
/// encore rendre : le compte, l'appareil enrôlé, les machines déclarées d'ici.
///
/// `UserDefaults` suffit : rien de secret n'y est — la clé vit ailleurs —, et
/// une désinstallation efface tout, comme la clé.
enum Carnet {
    struct Fiche: Codable {
        var id: String
        var nom: String
        var capacites: [String]
        var cle: String
        var code: String?
        var expireLe: Date?
        var revoqueeLe: Date?
        var enroleeLe: Date?

        init(machine: Machine) {
            id = machine.id.texte
            nom = machine.nom
            capacites = machine.capacites.map(\.rawValue)
            switch machine.cle {
            case let .attendue(code): cle = "attendue"; self.code = code.symboles; expireLe = code.expireLe
            case let .enrolee(le): cle = "enrolee"; enroleeLe = le
            case let .revoquee(le, code): cle = "revoquee"; revoqueeLe = le; self.code = code?.symboles; expireLe = code?.expireLe
            }
        }

        var machine: Machine {
            get {
                let id = (try? Identifiant.analyser(self.id, genre: .machine)) ?? Identifiant(genre: .machine, octets: [UInt8](repeating: 0, count: 16))
                let code = self.code.flatMap { symboles in expireLe.map { CodeEnrolement(symboles: symboles, expireLe: $0) } }
                let cle: Machine.Cle
                switch self.cle {
                case "enrolee": cle = .enrolee(le: enroleeLe ?? .now)
                case "revoquee": cle = .revoquee(le: revoqueeLe ?? .now, code: code)
                default: cle = .attendue(code: code ?? CodeEnrolement(symboles: "0000000000", expireLe: .distantPast))
                }
                return Machine(id: id, nom: nom, capacites: Set(capacites.compactMap(Capacite.init(rawValue:))), cle: cle, services: [])
            }
            set { self = Fiche(machine: newValue) }
        }
    }

    // `UserDefaults.standard` est sûr entre fils par contrat de Foundation ;
    // le compilateur ne le sait pas.
    private static var defauts: UserDefaults { .standard }

    static var compte: Compte? {
        get {
            guard let texte = defauts.string(forKey: "compte"), let id = try? Identifiant.analyser(texte, genre: .utilisateur) else { return nil }
            return Compte(identifiant: id, alias: defauts.string(forKey: "alias"))
        }
        set {
            defauts.set(newValue?.identifiant.texte, forKey: "compte")
            defauts.set(newValue?.alias, forKey: "alias")
        }
    }

    static var appareilEnrole: Identifiant? {
        get { defauts.string(forKey: "appareil").flatMap { try? Identifiant.analyser($0, genre: .appareil) } }
        set {
            defauts.set(newValue?.texte, forKey: "appareil")
            if newValue != nil, enroleLe == nil { defauts.set(Date(), forKey: "enrole_le") }
        }
    }

    static var enroleLe: Date? { defauts.object(forKey: "enrole_le") as? Date }

    /// Un appareil que CE téléphone a enrôlé, faute de `GET /v1/appareils`.
    struct AppareilEnrole: Codable {
        var texte: String
        var le: Date
        var revoqueLe: Date?

        init(id: Identifiant, le: Date, revoqueLe: Date?) {
            texte = id.texte
            self.le = le
            self.revoqueLe = revoqueLe
        }

        var id: Identifiant? { try? Identifiant.analyser(texte, genre: .appareil) }
    }

    static var appareilsEnrolesDIci: [AppareilEnrole] {
        get { (defauts.data(forKey: "appareils")).flatMap { try? JSONDecoder().decode([AppareilEnrole].self, from: $0) } ?? [] }
        set { defauts.set(try? JSONEncoder().encode(newValue), forKey: "appareils") }
    }

    static var machines: [Fiche] {
        get { (defauts.data(forKey: "machines")).flatMap { try? JSONDecoder().decode([Fiche].self, from: $0) } ?? [] }
        set { defauts.set(try? JSONEncoder().encode(newValue), forKey: "machines") }
    }

    static func remplacer(_ fiche: Fiche) {
        var liste = machines
        if let indice = liste.firstIndex(where: { $0.id == fiche.id }) { liste[indice] = fiche } else { liste.append(fiche) }
        machines = liste
    }

    /// Efface tout — ce qu'on fait quand on quitte un annuaire.
    static func vider() {
        for cle in ["compte", "alias", "appareil", "enrole_le", "machines", "appareils"] { defauts.removeObject(forKey: cle) }
    }
}
