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
    /// Le code d'invitation n'a pas été accepté.
    ///
    /// **Et l'on ne sait pas lequel des trois** — faux, expiré, déjà
    /// consommé : l'annuaire rend le même `403` pour les trois, à dessein
    /// (`protocole.md` §2.1), parce que distinguer dirait à qui essaie des
    /// codes lesquels ont existé.
    case invitationRefusee
    /// `429` — trop d'essais depuis cette adresse : la limite de débit de la
    /// posture `invitation`, cinq échecs par minute (`protocole.md` §2.2).
    ///
    /// **Ce n'est pas un refus.** La même demande, un peu plus tard, peut
    /// aboutir — et un code juste tapé pendant que la porte est fermée n'est
    /// pas même regardé. Dire « code refusé » ici ferait jeter un bon code.
    case tropDEssais
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
    /// Le nom sous lequel cet annuaire répond — celui qu'on exige de son
    /// certificat —, pour que l'écran dise à qui il parle sans le deviner.
    var nom: String { get }

    /// `POST /v1/comptes` — crée le compte et enrôle cet appareil.
    ///
    /// **C'est l'annuaire qui conduit** : il tire le défi, connaît la liaison
    /// de son canal, compose le message de possession et fait signer le
    /// signataire — un seul geste biométrique, au moment exact où la preuve
    /// est exigée. Le banc et le transport réel font la même chose, chacun
    /// avec ce qu'il a.
    /// **Le code d'invitation** n'est attendu que d'une racine en posture
    /// ``PostureAnnuaire/invitation`` — l'appelant le sait par
    /// ``version()``. Il part dans la case d'attestation, sous la plate-forme
    /// `3` ; `nil` ailleurs, et la plate-forme reste « aucune ».
    func ouvrirCompte(avec signataire: any Signataire, invitation: CodeInvitation?) async throws -> Compte
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
    /// `PUT /v1/appareils/{moi}/description` — ce que CET appareil est.
    /// **Pour soi seulement**, comme le jeton de poussée ; posé juste après
    /// la preuve, reposé quand il change.
    func decrire(_ description: Appareil.Description) async throws

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

    /// `GET /v1/utilisateurs/{u}/machines` — les machines de `u` que ses
    /// autorisations envers moi donnent à voir ; les miennes si `u` est moi ;
    /// vide sans aucune arête — vide, pas une erreur.
    func machines(de utilisateur: Identifiant) async throws -> [MachineVisible]
    /// `PUT /v1/alias`, `DELETE /v1/alias` avec `nil`.
    func definirAlias(_ alias: String?) async throws

    /// `DELETE /v1/compte` — efface MON compte, celui de la clé qui signe :
    /// appareils, machines et services, autorisations dans les deux sens,
    /// alias libéré — dans une transaction (`modele.md` §2.1). `204`, puis
    /// l'annuaire ferme la connexion : la clé qui a demandé est révoquée, et
    /// ce n'est pas une panne. Le dernier acte d'une clé.
    func effacerCompte() async throws

    /// `GET /v1/version` — ce que l'annuaire dit de lui-même, sans rien
    /// prouver : sa version, et **depuis 0.16.0 sa posture d'attestation**.
    /// `nil` si l'annuaire est trop ancien pour répondre à ce verbe (`404`).
    ///
    /// C'est par là que l'écran d'accueil sait s'il doit demander un code
    /// d'invitation — la seule ressource qu'il puisse lire avant d'avoir un
    /// compte.
    func version() async throws -> VersionAnnuaire?

    /// `GET /v1/nouvelles` sur la connexion tenue — un élément chaque fois
    /// que l'annuaire dit qu'un accès a changé pour ce compte
    /// (`protocole.md` §2, « notifications sans tiers »).
    ///
    /// **La nouvelle ne dit rien d'autre** : ni qui, ni quoi. L'application
    /// relit ``autorisations()`` et montre la différence (``Nouveautes``).
    ///
    /// **`nil` sans connexion tenue, et rien n'est tenté pour en avoir une** :
    /// reconnecter, c'est reprouver la clé, donc un geste biométrique — c'est
    /// à l'utilisateur de le faire, pas à une écoute. `nil` aussi quand une
    /// écoute tourne déjà : il n'y en a qu'une. Le flux se termine quand la
    /// connexion tombe ; la prochaine relecture voulue la rouvrira.
    func nouvelles() async -> AsyncStream<Void>?

    /// La connexion est-elle encore là, prouvée — de quoi lire sans geste ?
    /// Une relecture de retour au premier plan ne se fait qu'à cette
    /// condition : elle ne demande pas Face ID pour une pastille.
    func connexionTenue() async -> Bool

    /// Ferme la connexion, l'écoute des nouvelles d'abord — l'ABI veut qu'une
    /// attente soit arrêtée avant qu'on libère ce qu'elle lit. Ce qu'on fait
    /// d'un annuaire qu'on quitte pour une autre racine : il ne sert plus.
    func fermer() async

    /// La racine que la connexion tenue a jointe, ou `nil` sans connexion
    /// vivante. **Ne se connecte pas** et ne demande aucun geste : elle lit
    /// ce qui est, pour que l'écran le dise.
    func racineTenue() async -> RacineTenue?
}
