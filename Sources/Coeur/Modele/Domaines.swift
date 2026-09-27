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

    var id: String { membre?.texte ?? annuaire.map { "\($0.texte)+\(adresse)" } ?? "attendue:\(adresse)" }
    /// Le titulaire lui-même (et non un second membre).
    var estTitulaire: Bool { membre != nil && membre == annuaire }
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

    /// `GET /v1/annuaires`.
    static func annuaires(_ corps: Data) -> [AnnuaireLocal] {
        objets(corps).compactMap { o in
            guard let etat = o["etat"] as? String, let adresse = o["adresse"] as? String else { return nil }
            return AnnuaireLocal(membre: id(o["membre"], .annuaire), annuaire: id(o["annuaire"], .annuaire),
                                 etat: .init(etat), adresse: adresse, expireLe: date(o["expire_a"]))
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
