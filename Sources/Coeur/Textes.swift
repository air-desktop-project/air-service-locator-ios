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
    var libelle: String {
        switch self {
        case .enCours: "Annoncé"
        case .joignable: "Joignable"
        case .injoignable: "Annoncé, injoignable"
        case .nonSonde: "Annoncé"
        }
    }

    /// « joignable » porte toujours sa date : un « joignable » sans date décrit
    /// le passé au présent.
    var detail: String {
        switch self {
        case .enCours: "sonde en cours"
        case let .joignable(depuis, _): "depuis l'annuaire, \(depuis.relatif)"
        case let .injoignable(depuis): "depuis l'annuaire, \(depuis.relatif)"
        case .nonSonde: "UDP — non sondé"
        }
    }
}

extension Service {
    var libelleEtat: String {
        switch etat {
        case .annonce: resume?.libelle ?? "Annoncé"
        case .parti: "Parti"
        }
    }

    var detailEtat: String {
        switch etat {
        case .annonce: resume?.detail ?? ""
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

    /// Ce que change le choix, en une phrase — et ce qu'il ne change pas.
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
