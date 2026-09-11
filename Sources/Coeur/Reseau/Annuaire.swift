import Foundation

/// Ce que l'annuaire refuse, dans les termes de `docs/protocole.md` §2.
enum ErreurAnnuaire: Error, Equatable, Sendable {
    /// `404` — l'objet n'existe pas, OU il n'est pas à nous : c'est le même
    /// `404`, et c'est la propriété qui compte.
    case introuvable
    /// `403` — un appareil se révoque lui-même. Le seul refus qui ne se cache pas.
    case interdit
    /// `409` — l'alias est pris. La demande est légitime, c'est l'état du monde
    /// qui s'y oppose.
    case aliasPris
    /// `400` — la faute est celle de l'appelant.
    case requeteInvalide(String)
    /// `501` — l'annuaire ne sait pas encore le dire (les expositions).
    case nonImplemente
    /// Pas de réponse : l'annuaire injoignable, ou la connexion tombée.
    case reseau(String)
    /// L'appareil n'a pas confirmé l'identité de son porteur ; la clé n'a pas
    /// signé, rien n'est parti.
    case nonConfirme
    /// La preuve de possession ne vérifie pas sous la clé présentée.
    case preuveInvalide
}

/// La voie des applications mobiles (`docs/protocole.md` §2), telle que les
/// écrans la voient.
///
/// # Une interface, deux mises en œuvre
///
/// Les écrans ne savent pas qui répond. Aujourd'hui c'est ``AnnuaireSimule``,
/// en mémoire, qui tient les mêmes règles que le serveur — c'est ce qui permet
/// d'écrire et d'éprouver les écrans avant que le transport soit embarqué.
/// Demain c'est la pile QUIC de `asl-client`, derrière son ABI C, et **rien
/// ici ne changera** : les écrans parlent à cette interface, pas au fil.
///
/// **Toute requête est signée par la clé de l'appareil**, et la biométrie est
/// une condition d'usage de cette clé, appliquée par le matériel. Ce n'est pas
/// un paramètre : c'est ce qui se passe quand une méthode d'ici est appelée.
protocol Annuaire: Sendable {
    /// `GET /v1/defi` — trente-deux octets à usage unique, que la prochaine
    /// signature couvrira.
    func defi() async throws -> [UInt8]
    /// La liaison de canal de la connexion courante — l'exportateur TLS, que
    /// seul un transport réel sait dériver. Trente-deux octets.
    func liaisonDeCanal() async throws -> [UInt8]
    /// `POST /v1/comptes` — crée le compte et enrôle cet appareil : sa clé
    /// publique (33 octets, SEC1 compressé) et la preuve qu'il la détient
    /// (64 octets, `r ‖ s`, sur le défi et la liaison).
    func ouvrirCompte(cle: [UInt8], preuve: [UInt8]) async throws -> Compte
    /// Le compte de cet appareil, s'il en a un.
    func compte() async throws -> Compte?

    func machines() async throws -> [Machine]
    /// `POST /v1/machines` — déclare, et rend la machine avec son code
    /// d'enrôlement. Elle n'a pas encore de clé.
    func declarerMachine(nom: String, capacites: Set<Capacite>) async throws -> Machine
    /// `PATCH /v1/machines/{m}` — ce qui est `nil` ne change pas.
    func modifierMachine(_ id: Identifiant, nom: String?, capacites: Set<Capacite>?) async throws -> Machine
    /// `POST /v1/machines/{m}/enrolement` — le code précédent meurt à l'émission.
    func emettreCode(pour machine: Identifiant) async throws -> CodeEnrolement
    /// `DELETE /v1/machines/{m}/cle` — effet immédiat : connexions fermées,
    /// baux tombés. La machine reste.
    func revoquerCle(de machine: Identifiant) async throws

    func appareils() async throws -> [Appareil]
    /// `DELETE /v1/appareils/{a}` — marqué, non effacé. Jamais soi-même.
    func revoquerAppareil(_ id: Identifiant) async throws

    /// `GET /v1/autorisations` — les deux sens, révoquées comprises.
    func autorisations() async throws -> [Autorisation]
    /// `GET /v1/utilisateurs/{u}` — confirme qu'un identifiant existe, et rien
    /// d'autre.
    func utilisateurExiste(_ id: Identifiant) async throws -> Bool
    /// `GET /v1/alias/{alias}` — rend l'identifiant, et rien d'autre.
    func identifiant(pourAlias alias: String) async throws -> Identifiant?
    /// `POST /v1/autorisations` — accorde, et notifie le bénéficiaire.
    func accorder(a beneficiaire: Identifiant, portee: Autorisation.Portee, etiquette: String) async throws -> Autorisation
    /// `DELETE /v1/autorisations/{g}` — effet immédiat.
    func revoquerAutorisation(_ id: Identifiant) async throws

    /// `PUT /v1/alias`, `DELETE /v1/alias` avec `nil`.
    func definirAlias(_ alias: String?) async throws
}
