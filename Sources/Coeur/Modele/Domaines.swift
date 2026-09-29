import Foundation

/// Un domaine : l'espace où l'on range ses machines, et qu'on peut confier à
/// son propre annuaire (`protocole.md`, « Domaines », depuis l'annuaire 0.23.0).
struct Domaine: Identifiable, Hashable, Sendable {
    /// Qui sert ce domaine : les racines, ou l'annuaire local `n-…` à qui son
    /// propriétaire l'a confié. **Effectif** : un annuaire retiré ou refusé
    /// rend la main aux racines sans que rien ne soit réécrit.
    enum Hebergeur: Hashable, Sendable {
        case racines
        case annuaire(Identifiant)
    }

    /// Une machine rangée dans le domaine — la sienne, ou celle d'un autre
    /// compte qui y a le droit de ranger.
    struct MachineRangee: Identifiable, Hashable, Sendable {
        let id: Identifiant
        let proprietaire: Identifiant
        let nom: String?
        let alias: String?

        var titre: String { alias ?? nom ?? id.abrege }
    }

    let id: Identifiant
    let proprietaire: Identifiant
    let alias: String?
    let hebergePar: Hebergeur
    /// `administrer`, `rattacher`, `voir`, `localiser` — ce que CE compte
    /// peut y faire.
    let droits: [String]
    /// Rendues par le détail (`GET /v1/domaines/{d}`) seulement ; vide dans la
    /// liste, et vide sans le droit de voir.
    var machines: [MachineRangee] = []

    /// L'alias, ou l'identifiant ENTIER : ce qu'un menu ou un titre en dit.
    /// L'abrégé (`d-4M7F…DEVD`) ne distingue pas à coup sûr deux domaines
    /// sans alias, et ne se recopie pas.
    var titre: String { alias ?? id.texte }
    /// Ce qu'une ligne de la liste en dit : l'alias, ou l'identifiant entier
    /// — l'abrégé ne distingue pas deux domaines sans alias.
    var titreComplet: String { alias ?? "\(id.texte) - \(TextesDomaines.pasDAlias)" }
    func peut(_ droit: String) -> Bool { droits.contains(droit) }

    /// Peut-on y ranger une machine ? Seulement avec `rattacher` — que le
    /// propriétaire d'un domaine ordinaire tient toujours. Le domaine racine
    /// ne le donne à personne, pas même à son propriétaire (il ne contient
    /// aucune machine en v1) : il n'est donc jamais proposé.
    var recoitDesMachines: Bool { peut("rattacher") }
}

/// Un annuaire local — une machine du compte qui sert elle-même ses domaines,
/// inscrite auprès des racines (depuis l'annuaire 0.27.0).
struct AnnuaireLocal: Identifiable, Hashable, Sendable {
    enum Etat: Hashable, Sendable {
        /// Déclaré ; le code n'a pas encore été présenté par la machine.
        case attendue
        /// Présenté ; les racines n'ont pas encore décidé.
        case enAttente
        case acceptee
        case refusee
        case retiree
        /// Une valeur que cette version ne connaît pas : dite telle quelle.
        case inconnu(String)

        init(_ texte: String) {
            switch texte {
            case "attendue": self = .attendue
            case "en attente": self = .enAttente
            case "acceptée": self = .acceptee
            case "refusée": self = .refusee
            case "retirée": self = .retiree
            default: self = .inconnu(texte)
            }
        }
    }

    /// Le membre présenté (`n-…`), absent tant que le code n'a pas servi.
    let membre: Identifiant?
    /// Le titulaire de la paire — c'est lui qu'on confie un domaine, lui
    /// qu'on retire. Absent pour une première déclaration non encore
    /// présentée.
    let annuaire: Identifiant?
    let etat: Etat
    let adresse: String
    let expireLe: Date?
    /// Comment ce membre juge sa paire (`paire`, décision 70) ; absent tant
    /// qu'il n'a pas parlé à la racine qui répond depuis qu'elle tourne.
    var paire: Paire? = nil
    /// Ce que la racine qui répond sait de la voie de fédération de ce membre
    /// vers elle (`voie`, décision 86) ; absent sans rapport de lui.
    var voie: Voie? = nil

    /// `paire` : `seul`, `reglee`, `sans-peer`, `peer-inconnu`.
    enum Paire: Hashable, Sendable {
        case seul, reglee, sansPeer, peerInconnu
        /// Une valeur que cette version ne connaît pas : ni réglée, ni
        /// fautive — l'écran n'en dit rien.
        case inconnue(String)

        init(_ texte: String) {
            switch texte {
            case "seul": self = .seul
            case "reglee": self = .reglee
            case "sans-peer": self = .sansPeer
            case "peer-inconnu": self = .peerInconnu
            default: self = .inconnue(texte)
            }
        }

        /// Le membre tourne mal réglé : sa paire ne se réplique pas.
        var malReglee: Bool { self == .sansPeer || self == .peerInconnu }
    }

    /// `voie` : `ouverte`, `tombee`.
    enum Voie: Hashable, Sendable {
        case ouverte, tombee
        /// Une valeur inconnue compte comme une absence : on n'affirme rien.
        case inconnue(String)

        init(_ texte: String) {
            switch texte {
            case "ouverte": self = .ouverte
            case "tombee": self = .tombee
            default: self = .inconnue(texte)
            }
        }
    }

    var id: String { membre?.texte ?? annuaire.map { "\($0.texte)+\(adresse)" } ?? "attendue:\(adresse)" }
    /// Le titulaire lui-même (et non un second membre).
    var estTitulaire: Bool { membre != nil && membre == annuaire }
}

/// L'état d'un annuaire local — d'une paire — tel que la racine qui répond le
/// voit (`docs/annuaires.md`, « L'état de l'annuaire dans les
/// applications ») : **vivant** si au moins un membre accepté a sa voie
/// ouverte ; **parti** si aucun ne l'est et qu'au moins un l'a tombée ; **pas
/// de nouvelles** sinon — la racine vient de redémarrer, ou aucun membre ne
/// lui a parlé depuis. Rien n'est affirmé que la racine n'a pas constaté.
enum EtatDeLAnnuaire: Hashable, Sendable {
    case vivant, parti, pasDeNouvelles

    init(membres: [AnnuaireLocal]) {
        let voies = membres.filter { $0.etat == .acceptee }.compactMap(\.voie)
        if voies.contains(.ouverte) {
            self = .vivant
        } else if voies.contains(.tombee) {
            self = .parti
        } else {
            self = .pasDeNouvelles
        }
    }
}

/// Le code qu'une machine présente pour inscrire son annuaire : dix symboles,
/// groupés 5-5, vingt-quatre heures.
struct CodeInscription: Hashable, Sendable {
    let code: String
    let expireLe: Date
}

/// Une inscription qui attend la décision des administrateurs des racines.
struct Inscription: Identifiable, Hashable, Sendable {
    let membre: Identifiant
    let annuaire: Identifiant
    let proprietaire: Identifiant
    let adresse: String
    var id: Identifiant { membre }
}

/// La lecture des réponses de l'annuaire — des fonctions pures, pour que les
/// essais les tiennent sans transport.
enum ReponsesDomaines {
    private static func objets(_ corps: Data) -> [[String: Any]] {
        (try? JSONSerialization.jsonObject(with: corps)) as? [[String: Any]] ?? []
    }

    private static func id(_ valeur: Any?, _ genre: Genre) -> Identifiant? {
        (valeur as? String).flatMap { try? Identifiant.analyser($0, genre: genre) }
    }

    private static func date(_ valeur: Any?) -> Date? {
        (valeur as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1_000) }
    }

    static func domaine(depuis objet: [String: Any]) -> Domaine? {
        guard let d = id(objet["domaine"], .domaine), let proprietaire = id(objet["proprietaire"], .utilisateur) else { return nil }
        let hebergeur: Domaine.Hebergeur = id(objet["heberge_par"], .annuaire).map(Domaine.Hebergeur.annuaire) ?? .racines
        let machines = (objet["machines"] as? [[String: Any]] ?? []).compactMap { m -> Domaine.MachineRangee? in
            guard let mid = id(m["machine"], .machine), let p = id(m["proprietaire"], .utilisateur) else { return nil }
            return Domaine.MachineRangee(id: mid, proprietaire: p, nom: m["nom"] as? String, alias: m["alias"] as? String)
        }
        return Domaine(id: d, proprietaire: proprietaire, alias: objet["alias"] as? String, hebergePar: hebergeur,
                       droits: objet["droits"] as? [String] ?? [], machines: machines)
    }

    /// `GET /v1/domaines`.
    static func domaines(_ corps: Data) -> [Domaine] { objets(corps).compactMap(domaine(depuis:)) }

    /// `GET /v1/domaines/{d}`.
    static func detail(_ corps: Data) -> Domaine? {
        ((try? JSONSerialization.jsonObject(with: corps)) as? [String: Any]).flatMap(domaine(depuis:))
    }

    /// Une chaîne non vide, ou rien : `null`, `""`, un nombre ou un booléen
    /// comptent comme un champ absent.
    private static func chaine(_ valeur: Any?) -> String? {
        (valeur as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `GET /v1/annuaires`.
    static func annuaires(_ corps: Data) -> [AnnuaireLocal] {
        objets(corps).compactMap { o in
            guard let etat = o["etat"] as? String, let adresse = o["adresse"] as? String else { return nil }
            // `paire` et `voie` sont des chaînes (et non des booléens) : un
            // champ absent, ou d'un autre type, se lit comme une absence.
            return AnnuaireLocal(membre: id(o["membre"], .annuaire), annuaire: id(o["annuaire"], .annuaire),
                                 etat: .init(etat), adresse: adresse, expireLe: date(o["expire_a"]),
                                 paire: chaine(o["paire"]).map(AnnuaireLocal.Paire.init),
                                 voie: chaine(o["voie"]).map(AnnuaireLocal.Voie.init))
        }
    }

    /// `POST /v1/annuaires`, `POST /v1/annuaires/{n}/membres`.
    static func code(_ corps: Data) -> CodeInscription? {
        guard let o = (try? JSONSerialization.jsonObject(with: corps)) as? [String: Any],
              let code = o["code"] as? String, let expire = date(o["expire_a"]) else { return nil }
        return CodeInscription(code: code, expireLe: expire)
    }

    /// `GET /v1/inscriptions`.
    static func inscriptions(_ corps: Data) -> [Inscription] {
        objets(corps).compactMap { o in
            guard let membre = id(o["membre"], .annuaire), let annuaire = id(o["annuaire"], .annuaire),
                  let proprietaire = id(o["proprietaire"], .utilisateur), let adresse = o["adresse"] as? String else { return nil }
            return Inscription(membre: membre, annuaire: annuaire, proprietaire: proprietaire, adresse: adresse)
        }
    }
}
