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
    /// `POST /v1/comptes` — crée le compte et enrôle cet appareil.
    ///
    /// **C'est l'annuaire qui conduit** : il tire le défi, connaît la liaison
    /// de son canal, compose le message de possession et fait signer le
    /// signataire — un seul geste biométrique, au moment exact où la preuve
    /// est exigée. Le banc et le transport réel font la même chose, chacun
    /// avec ce qu'il a.
    func ouvrirCompte(avec signataire: any Signataire) async throws -> Compte
    /// Rejoint un compte existant, **depuis le nouveau téléphone** : un
    /// appareil déjà enrôlé a posté sa clé (``enrolerAppareil(cle:)``) et lui
    /// a rendu l'invitation. Rien n'est posté ici — la clé est déjà connue de
    /// l'annuaire — mais elle est **prouvée**, sur cette connexion : c'est le
    /// geste, et c'est ce qui échoue (``ErreurAnnuaire/preuveInvalide``) si la
    /// clé n'est pas celle qu'on a enrôlée.
    func rejoindre(compte: Identifiant, appareil: Identifiant, avec signataire: any Signataire) async throws -> Compte
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
    /// `POST /v1/appareils` — enrôle un appareil de plus, **depuis celui-ci** :
    /// la clé que le nouveau téléphone a montrée. Rend l'appareil, dont
    /// l'identifiant à lui rendre.
    func enrolerAppareil(cle: [UInt8]) async throws -> Appareil
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
