import Foundation

/// L'application parle français ; ses dates aussi, quel que soit le réglage
/// de l'appareil — un « il y a 2 min » au milieu d'un écran français ne doit
/// pas devenir « 2 minutes ago » parce que le téléphone est en anglais.
extension Locale {
    static let francais = Locale(identifier: "fr_FR")
}

extension Date {
    /// « il y a 2 min », « la semaine dernière ».
    var relatif: String {
        formatted(.relative(presentation: .named).locale(.francais))
    }

    /// « 11 sept. 2026 ».
    var jour: String {
        formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: .francais))
    }
}

extension Joignabilite {
    /// Le mot, exactement — et jamais « en ligne ».
    var libelle: String { libelle(sonde: nil) }
    var detail: String { detail(sonde: nil) }

    /// Une sonde partie de la machine elle-même ne prouve pas qu'on la
    /// joigne du dehors : le mot le dit.
    func libelle(sonde: Sonde?) -> String {
        switch self {
        case .enCours: "Annoncé"
        case .joignable: sonde?.locale == true ? TextesSonde.joignableLocal : "Joignable"
        case .injoignable: "Annoncé, injoignable"
        case .nonSonde: "Annoncé"
        }
    }

    /// « joignable » porte toujours sa date : un « joignable » sans date décrit
    /// le passé au présent. Et qui l'a constaté : les racines, ou l'annuaire
    /// local qui sert le domaine.
    func detail(sonde: Sonde?) -> String {
        switch self {
        case .enCours: "sonde en cours"
        case let .joignable(depuis, _), let .injoignable(depuis):
            sonde.map { TextesSonde.rapportePar($0.par, depuis) } ?? "depuis l'annuaire, \(depuis.relatif)"
        case .nonSonde: "UDP — non sondé"
        }
    }
}

/// L'origine de la sonde d'un service fédéré (décision 60) — à la lettre :
/// Android dit les mêmes.
enum TextesSonde {
    static let joignableLocal = "Joignable depuis la machine"
    static func rapportePar(_ annuaire: Identifiant, _ depuis: Date) -> String {
        "rapporté par l'annuaire \(annuaire.abrege), \(depuis.relatif)"
    }
    static let pasDeLExterieur = "Sondé depuis la machine elle-même : pas vérifié de l'extérieur."
}

extension Service {
    /// « Joignable », mais constaté depuis la machine elle-même : à dire.
    var joignableDeLInterieurSeulement: Bool {
        guard sonde?.locale == true, case .joignable = resume else { return false }
        return true
    }

    var libelleEtat: String {
        switch etat {
        case .annonce: resume?.libelle(sonde: sonde) ?? "Annoncé"
        case .parti: "Parti"
        }
    }

    var detailEtat: String {
        switch etat {
        case .annonce where sansDetail: TextesDomaines.sansDetail
        case .annonce: resume?.detail(sonde: sonde) ?? ""
        case let .parti(volontaire, le):
            [volontaire.map { $0 ? "arrêt volontaire" : "inactivité" } ?? "motif inconnu", le?.relatif].compactMap { $0 }.joined(separator: ", ")
        }
    }
}

extension Appareil.Attestation {
    /// Sous quoi l'appareil est entré, en toutes lettres — le même mot sur
    /// l'iPhone et sur le Mac, parce qu'il vient d'ici et non de deux écrans
    /// qui finiraient par diverger.
    ///
    /// **`attendue` se dit au présent** : l'appareil n'est pas entré, il est
    /// en train de le faire, et c'est ce que son porteur doit lire pour
    /// savoir qu'il lui reste un geste (`protocole.md` §2.2).
    var libelle: String {
        switch self {
        case .apple: "attesté par Apple"
        case .android: "clé attestée (Android)"
        case .invitation: "sur invitation"
        case .aucune: "sans attestation"
        case .attendue: "en attente d'attestation"
        }
    }
}

extension Machine {
    var resumeListe: String {
        var morceaux = [capacitesTexte]
        let vivants = services.filter { if case .annonce = $0.etat { true } else { false } }.count
        if vivants > 0 { morceaux.append("\(vivants) service\(vivants > 1 ? "s" : "")") }
        if unServiceOscille { morceaux.append("un service oscille") }
        return morceaux.joined(separator: " · ")
    }
}

/// Une erreur d'annuaire, dite à l'utilisateur dans ses mots.
extension ErreurAnnuaire {
    var message: String {
        switch self {
        case .introuvable: "Introuvable."
        case .interdit: "Un appareil ne peut pas se révoquer lui-même."
        case .aliasPris: "Cet alias est déjà pris."
        case let .requeteInvalide(champ): "Demande refusée : \(champ)."
        case .nonImplemente: "L'annuaire ne sait pas encore le dire."
        case let .reseau(detail): "Annuaire injoignable : \(detail)"
        case .nonConfirme: "Identité non confirmée ; rien n'a été envoyé."
        case .preuveInvalide: "La preuve de possession de la clé ne vérifie pas."
        case .invitationRefusee:
            "Ce code d'invitation n'a pas été accepté. Vérifiez-le auprès de qui vous l'a donné : il ne vaut qu'une fois, et il expire."
        case .tropDEssais: TextesInvitation.tropDEssais
        case .dernierDomaine: TextesDomaines.dernierDomaine
        case .rattachementInterdit: TextesDomaines.rattachementInterdit
        case .rangementRefuse: TextesDomaines.rangementRefuse
        case .secondMembreDejaDeclare: TextesDomaines.secondDejaDeclare
        case .inscriptionClose: TextesDomaines.inscriptionClose
        }
    }
}

extension Error {
    var messageAnnuaire: String {
        (self as? ErreurAnnuaire)?.message ?? localizedDescription
    }
}

/// Ce que les deux écrans d'ouverture de compte — iOS et macOS — disent du
/// code d'invitation.
///
/// **Les mêmes mots des deux côtés.** Les deux écrans ne se ressemblent pas
/// (une `List` sur iPhone, une colonne sur le Mac), mais ce qu'ils expliquent
/// est identique, et deux rédactions jumelles finissent par diverger : la
/// première correction n'est portée qu'à un endroit. C'est la leçon des deux
/// `switch` d'attestation, réunis pour la même raison.
enum TextesInvitation {
    static let titre = "Code d'invitation"
    static let exemple = "4K9M2-P7R1T"

    /// Pourquoi l'on demande ce code — dit sans jargon : l'utilisateur ne
    /// connaît ni « posture » ni « attestation », il sait qu'on lui a donné
    /// un code.
    static let explication =
        "Cet annuaire n'ouvre un compte que sur invitation. Saisissez le code que son exploitant vous a donné."

    /// Ce que le code vaut, dit avant qu'on le tape plutôt qu'après qu'il a
    /// échoué : il ne sert qu'une fois, et il ne dure pas.
    static let duree = "Dix symboles, à usage unique. Il expire — demandez-en un autre s'il est trop vieux."

    /// Ce que l'on dit quand l'annuaire a fermé la porte un instant (`429`).
    ///
    /// **Attendre, pas douter du code** : pendant la minute où la limite
    /// tient, l'annuaire ne regarde même pas ce qu'on tape — un bon code y
    /// échouerait aussi. Le dire autrement pousserait à jeter un code juste.
    /// La phrase ne parle pas du code : rejoindre un compte la reprend telle
    /// quelle, et là il n'y en a pas.
    static let tropDEssais = "Trop d'essais : réessayez dans une minute."
}

/// Ce que l'iPhone et le Mac disent du choix de la racine — les mêmes mots
/// des deux côtés, pour la même raison que ``TextesInvitation``.
enum TextesRacine {
    static let titre = "Racine"
    /// `annuaire.json` est là, mais ne désigne aucune racine par son
    /// identité : l'application le dit, et ne se replie sur rien.
    static let aucuneTitre = "Aucune racine utilisable"
    static let aucuneIdentifiee = "Le fichier annuaire.json de l'application ne désigne aucune racine par son identité (« annuaire » : n-…, « locateurs » : adresses littérales). La forme par nom DNS n'est plus lue."

    /// Ce que change le choix, en une phrase — et ce qu'il ne change pas.
    /// Ce que tient la connexion — le nom de la racine qui a répondu, même
    /// sous « Automatique ». Les mêmes mots sur Android.
    static func connecteA(_ racine: String) -> String { "Connecté à \(racine)" }
    static let nonConnecte = "Non connecté"

    static let explication =
        "Votre compte, vos appareils et vos accès sont les mêmes sur chaque racine : elles se répliquent. Changer ne change que la connexion — et, sur le Mac, les accès annoncés en direct : seuls ceux accordés sur la racine choisie le sont ; les autres apparaissent à la relecture. La reconnexion demande votre confirmation biométrique."
}

/// Ce que l'iPhone et le Mac disent des accès reçus depuis la dernière fois
/// — les mêmes mots des deux côtés, pour la même raison que
/// ``TextesInvitation``.
enum TextesNouveautes {
    /// La marque d'une ligne jamais montrée, dans l'écran des accès.
    static let marque = "nouveau"

    /// La notification locale du Mac. **Générique, par principe** : la
    /// nouvelle de l'annuaire ne dit ni qui ni quoi (`protocole.md` §2), et
    /// une notification reste lisible sur un écran verrouillé — elle n'a pas
    /// à dire ce que la fenêtre dira. Ni « accès » ni « accordé » : les mots
    /// d'Android, à la lettre, pour que les deux plates-formes n'en disent pas
    /// plus l'une que l'autre.
    static let titre = "Du nouveau dans Service Locator"
    static let corps = "Ouvrez l'application pour voir ce qui a changé."

    /// Pourquoi demander la permission, dit avant que macOS la demande.
    static let explication =
        "Quand un compte vous accorde un accès, l'annuaire le signale à ce Mac tant que l'application est ouverte et connectée. Rien ne passe par Apple ni par un autre tiers, et la notification ne dit rien de plus que « du nouveau »."
}

/// Ce que l'iPhone, le Mac et Android disent des domaines et des annuaires
/// locaux — les mêmes mots partout.
/// L'état d'écho, en toutes lettres — les mêmes mots sur l'iPhone, sur le
/// Mac, et proposés à Android.
enum TextesEcho {
    static let titre = "Écho"
    static let absent = "Pas d'écho"
    static let commentLeLancer = "Sur la machine : asl echo"
    static let interieur = "prouvé de son réseau : sa clé répond, ce qui ne dit pas qu'on la joint du dehors"
    static let autreCle = "une réponse est venue, signée par une autre clé que celle de cette machine"
    static func via(_ mot: String) -> String {
        switch mot {
        case "upnp": "par la redirection que la box a accordée (UPnP)"
        case "nat": "par le NAT que la connexion à l'annuaire tient ouvert"
        case "direct": "en direct, sans traduction d'adresse"
        default: "par « \(mot) »"
        }
    }
    static func constate(_ quand: String) -> String { "constaté \(quand)" }
    static func par(_ annuaire: String) -> String { "par l'annuaire \(annuaire)" }
}

extension EtatDEcho {
    var libelle: String {
        switch verdict {
        case .verifie:
            switch depuis {
            case .exterieur?: "Écho vérifié, du dehors"
            case .interieur?: "Écho vérifié, de l'intérieur"
            default: "Écho vérifié"
            }
        case .injoignable: "Écho injoignable"
        case .autreCle: "Écho signé par une autre clé"
        case .enCours: "Écho en cours de vérification"
        case let .inconnu(mot): "Écho : \(mot)"
        }
    }

    /// Par où, quand, par qui — et ce qu'une preuve de l'intérieur ne dit
    /// pas.
    var detail: String {
        var morceaux: [String] = []
        if verdict == .verifie, let via { morceaux.append(TextesEcho.via(via)) }
        if verdict == .autreCle { morceaux.append(TextesEcho.autreCle) }
        if verdict == .verifie, depuis == .interieur { morceaux.append(TextesEcho.interieur) }
        if let a { morceaux.append(TextesEcho.constate(a.relatif)) }
        if let par { morceaux.append(TextesEcho.par(par.abrege)) }
        return morceaux.joined(separator: ", ")
    }
}

enum TextesDomaines {
    static let domaines = "Domaines"
    static let aucunDomaine = "Aucun domaine."
    static let creer = "Créer un domaine"
    static let aliasFacultatif = "Alias (facultatif)"
    static let hebergeRacines = "Hébergé par : les racines"
    static let pasDAlias = "pas d'alias"
    static let proprietaire = "Propriétaire"
    static let vous = "vous"
    static func hebergeAnnuaire(_ n: String) -> String { "Hébergé par : l'annuaire \(n)" }
    static let supprimer = "Supprimer le domaine"
    static let confirmerSuppression = "Les machines qui y sont rangées n'y seront plus. Rien d'autre ne part."
    static let dernierDomaine = "C'est votre dernier domaine : un compte en garde toujours un."
    static let machinesRangees = "Machines rangées ici"
    static let aucuneMachine = "Aucune machine rangée dans ce domaine."
    static let aucunService = "aucun service annoncé"
    /// Un service vu par `voir` seul (décision 102).
    static let sansDetail = "points d'écoute réservés à qui localise dans ce domaine"
    /// Avant de ranger une machine dans le domaine d'un AUTRE compte : ce
    /// que ce rangement ouvre (décisions 100 à 104).
    static func rangerChezUnAutre(_ domaine: String) -> String { "Ranger dans « \(domaine) », le domaine d'un autre compte ?" }
    static let ceQueLeRangementOuvre = "Qui voit ce domaine verra les services de cette machine ; qui y localise les joindra."
    static let rangerQuandMeme = "Ranger"
    static let domaineDeLaMachine = "Domaine"
    static let aucun = "aucun"
    static let ranger = "Ranger dans un domaine"
    static let retirerDuDomaine = "Retirer du domaine"
    static let rattachementInterdit = "Vous n'avez pas le droit de ranger une machine dans ce domaine."
    static let rangementRefuse = "Ce domaine ne peut pas recevoir cette machine."
    static let domaineRacine = "Domaine racine"
    static let confier = "Confier à mon annuaire local"
    static let rendreAuxRacines = "Rendre aux racines"

    static let annuaireLocal = "Mon annuaire local"
    static let aucunAnnuaire = "Aucun annuaire local déclaré."
    static let declarer = "Déclarer un annuaire local"
    static let adresse = "Adresse (hôte:port)"
    static let adresseAide = "L'adresse où la machine qui l'héberge écoute."
    static let codeTitre = "Code d'inscription"
    static let codeAide = "À présenter sur la machine dans les 24 heures :"
    static func commande(code: String, racine: String) -> String {
        "asl-server --register \(code) --directory \(racine) --identity-key <clé>"
    }
    static let secondMembre = "Déclarer le second membre de la paire"
    static let secondDejaDeclare = "Un second membre est déjà déclaré, en attente ou accepté."
    static let retirer = "Retirer l'annuaire"
    static let confirmerRetrait = "La paire entière est retirée ; les domaines qu'elle héberge reviennent aux racines."
    static func etat(_ etat: AnnuaireLocal.Etat) -> String {
        switch etat {
        case .attendue: "code pas encore présenté"
        case .enAttente: "en attente de la décision des racines"
        case .acceptee: "acceptée"
        case .refusee: "refusée"
        case .retiree: "retirée"
        case let .inconnu(texte): texte
        }
    }

    // L'état de l'annuaire local (décisions 70 et 86) — à la lettre :
    // Android dit les mêmes.
    static let vivant = "Vivant"
    static let parti = "Parti"
    static let pasDeNouvelles = "Pas de nouvelles"
    static let voieOuverte = "Voie ouverte"
    static let voieTombee = "Voie tombée"
    static let paireReglee = "Paire réglée"
    static let paireMalReglee = "Paire mal réglée"
    /// Ce qu'on dit d'une valeur absente ou inconnue.
    static let inconnu = "—"

    static func etat(_ etat: EtatDeLAnnuaire) -> String {
        switch etat {
        case .vivant: vivant
        case .parti: parti
        case .pasDeNouvelles: pasDeNouvelles
        }
    }

    static func voie(_ voie: AnnuaireLocal.Voie?) -> String {
        switch voie {
        case .ouverte: voieOuverte
        case .tombee: voieTombee
        case .inconnue, .none: inconnu
        }
    }

    /// Qui est en faute, dans une phrase : « le titulaire (n-7MSV…X87P) »,
    /// « le second membre (n-4EQR…F8Z9) » — le rôle et l'identité, plutôt
    /// qu'une adresse IPv6 illisible.
    static func membreDeLaPaire(_ membre: AnnuaireLocal) -> String {
        let role = membre.estTitulaire ? "le titulaire" : "le second membre"
        return membre.membre.map { "\(role) (\($0.abrege))" } ?? role
    }

    /// La phrase qui dit quoi faire d'un membre mal réglé ; `nil` s'il ne
    /// l'est pas. À la lettre : Android dit la même.
    static func paireFautive(_ membre: AnnuaireLocal) -> String? {
        let qui = membreDeLaPaire(membre)
        let m = qui.prefix(1).uppercased() + qui.dropFirst()
        switch membre.paire {
        case .sansPeer:
            return "\(m) tourne sans --peer : la paire ne se réplique pas ; réglez --peer et --peer-key sur cette machine."
        case .peerInconnu:
            return "\(m) désigne par --peer un annuaire qui n'est pas l'autre membre de la paire ; corrigez --peer et --peer-key sur cette machine."
        default:
            return nil
        }
    }

    static let administration = "Administration des racines"
    static let aucuneInscription = "Aucune inscription en attente."
    static let accepter = "Accepter"
    static let refuser = "Refuser"
    static func confirmerAcceptation(membre: String, adresse: String, proprietaire: String) -> String {
        "L'annuaire \(membre) (\(adresse)), du compte \(proprietaire), servira les domaines qu'on lui confiera."
    }
    static let confirmerRefus = "L'annuaire ne pourra pas servir de domaine. Un refus l'emporte même sur une acceptation passée."
    static let inscriptionClose = "Cette inscription est déjà refusée ou retirée : elle ne peut plus être acceptée."
}
