import Foundation
import OSLog

/// Les annuaires entre lesquels cet appareil peut choisir, et celui qu'il a
/// choisi.
///
/// # UNE LISTE, PARCE QUE LES RACINES SONT DEUX
///
/// nitrogen et argon tiennent le même annuaire, répliqué : le même compte,
/// la même clé d'appareil, les mêmes accès, sur l'une comme sur l'autre. Ce
/// qui change en passant de l'une à l'autre, c'est la connexion tenue — et
/// donc les nouvelles entendues en direct : une racine ne réveille que pour
/// les accès écrits chez elle (décision 9) ; les autres se voient à la
/// relecture. Jusqu'ici le choix se faisait à la construction, et un essai
/// sur argon a dû re-signer une copie du paquet.
///
/// # LE FICHIER : L'IDENTITÉ PAR LA CLÉ, ET RIEN D'AUTRE
///
/// ```json
/// {"annuaires": [
///   {"libelle": "Automatique", "racines": [
///      {"annuaire": "n-0PWT8HZD80QMSPPDZ5CQXXYHQC", "locateurs": ["[2001:41d0:20a:900::1dd4]:6630", "178.32.16.250:6630"]},
///      {"annuaire": "n-3K3P6H252W8K9370QG1YYTWBWB", "locateurs": ["[2001:41d0:20a:900::1d32]:6630", "178.32.16.249:6630"]}]},
///   {"annuaire": "n-0PWT8HZD80QMSPPDZ5CQXXYHQC", "locateurs": ["[2001:41d0:20a:900::1dd4]:6630", "178.32.16.250:6630"]},
///   {"annuaire": "n-3K3P6H252W8K9370QG1YYTWBWB", "locateurs": ["[2001:41d0:20a:900::1d32]:6630", "178.32.16.249:6630"]}
/// ]}
/// ```
///
/// Une entrée dit qui l'on doit trouver au bout (`annuaire`, le `n-…` que
/// la clé d'identité de la racine donne) et où le joindre (`locateurs`, des
/// adresses LITTÉRALES — aucun nom ne se résout, C20). Une entrée qui couvre
/// plusieurs racines — « Automatique » — les liste dans `racines`, chacune
/// avec les siennes. Un locateur qui n'est pas littéral, un `n-…` de
/// travers, se laissent de côté : on ne devine pas. `libelle` est ce que
/// l'écran en dit ; `nom`, facultatif, remplace le nom que la liste
/// embarquée (``RacinesConnues``) donne à l'identité.
///
/// # LA FORME D'HIER N'EST PLUS LUE
///
/// Une entrée sans identité — `{"adresse": "nom:port", "nom": …}`, un nom
/// DNS et une chaîne sous autorité — ne sert plus : les racines ne
/// présentent plus que leur certificat d'identité. Elle est laissée de côté,
/// et le journal le dit. Si rien d'identifié ne reste, l'application le dit
/// à l'écran (``Paquet/inutilisable(_:)``) : **aucun repli** sur le DNS, ni
/// sur le banc de démonstration. `annuaire-racine.pem` n'est plus lu ni
/// embarqué. Seule trace gardée d'hier : `adresse`, s'il est encore là,
/// désigne l'entrée qu'une préférence retenue avant 0.20.0 avait choisie.
enum ChoixDAnnuaire {
    private static let journal = Logger(subsystem: "org.airdesktop.servicelocator", category: "annuaire")

    private struct Identifiee: Decodable {
        let annuaire: String
        let locateurs: [String]
    }

    private struct Entree: Decodable {
        let adresse: String?
        let nom: String?
        let libelle: String?
        let annuaire: String?
        let locateurs: [String]?
        let racines: [Identifiee]?

        /// Les racines par leur identité — la forme courte (`annuaire` et
        /// `locateurs` sur l'entrée) et la longue (`racines`) mises ensemble,
        /// ce qui ne se lit pas laissé de côté.
        var identites: [AnnuaireReel.RacineIdentifiee] {
            var toutes = racines ?? []
            if let annuaire, let locateurs { toutes.insert(Identifiee(annuaire: annuaire, locateurs: locateurs), at: 0) }
            return toutes.compactMap { racine in
                guard (try? Identifiant.analyser(racine.annuaire, genre: .annuaire)) != nil else { return nil }
                let litteraux = racine.locateurs.filter(ChoixDAnnuaire.estLitteral)
                return litteraux.isEmpty ? nil : AnnuaireReel.RacineIdentifiee(annuaire: racine.annuaire, locateurs: litteraux)
            }
        }
    }

    private struct Liste: Decodable {
        let annuaires: [Entree]
    }

    /// Ce que le paquet donne à l'application.
    enum Paquet: Equatable {
        /// Pas d'`annuaire.json` : un poste de développement, le banc.
        case absent
        case annuaires([AnnuaireReel.Reglages])
        /// Un fichier, mais aucune racine utilisable : dit tel quel à l'écran.
        case inutilisable(String)
    }

    /// `[IPv6]:port` ou `IPv4:port` — ce qu'`…_annuaire_identifie` accepte,
    /// et rien qui demande un résolveur.
    static func estLitteral(_ locateur: String) -> Bool {
        guard let deuxPoints = locateur.lastIndex(of: ":"), UInt16(locateur[locateur.index(after: deuxPoints)...]) != nil else { return false }
        let hote = locateur[..<deuxPoints]
        if hote.hasPrefix("["), hote.hasSuffix("]") {
            var v6 = in6_addr()
            return inet_pton(AF_INET6, String(hote.dropFirst().dropLast()), &v6) == 1
        }
        var v4 = in_addr()
        return inet_pton(AF_INET, String(hote), &v4) == 1
    }

    /// Les annuaires identifiés que décrit ce JSON, dans l'ordre du fichier ;
    /// vide si rien ne se lit ou si rien n'est identifié.
    static func lire(json: Data) -> [AnnuaireReel.Reglages] {
        let decodeur = JSONDecoder()
        let entrees: [Entree]
        if let liste = try? decodeur.decode(Liste.self, from: json) {
            entrees = liste.annuaires
        } else if let seule = try? decodeur.decode(Entree.self, from: json) {
            entrees = [seule]
        } else {
            entrees = []
        }
        let reglages = entrees.compactMap { entree -> AnnuaireReel.Reglages? in
            let identites = entree.identites
            guard let premiere = identites.first else {
                let quoi = entree.libelle ?? entree.nom ?? entree.adresse ?? "?"
                Self.journal.error("entrée « \(quoi, privacy: .public) » laissée de côté : aucune identité (la forme par nom n'est plus lue)")
                return nil
            }
            return AnnuaireReel.Reglages(nom: entree.nom ?? RacinesConnues.nom(de: premiere.annuaire), libelle: entree.libelle,
                                         identites: identites, cleDHier: entree.adresse)
        }
        // Deux entrées de même clé n'en font qu'une : c'est la clé que la
        // préférence retient.
        var vues = Set<String>()
        return reglages.filter { vues.insert($0.cle).inserted }
    }

    /// `annuaire.json` du paquet — non versionné.
    static func duPaquet(_ paquet: Bundle = .main) -> Paquet {
        depuis(paquet.url(forResource: "annuaire", withExtension: "json"))
    }

    /// Ce que dit ce fichier — absent ou illisible sur disque : le banc.
    static func depuis(_ fichier: URL?) -> Paquet {
        guard let fichier, let donnees = try? Data(contentsOf: fichier) else { return .absent }
        let annuaires = lire(json: donnees)
        return annuaires.isEmpty ? .inutilisable(TextesRacine.aucuneIdentifiee) : .annuaires(annuaires)
    }
}

/// Les racines d'air-desktop-project, par leur identité — de quoi dire
/// « Connecté à nitrogen » sans rien demander au DNS. Les `n-…` sont publics
/// (l'utilitaire `asl` les embarque aussi) ; une identité que cette liste ne
/// connaît pas se dit par son identifiant abrégé.
enum RacinesConnues {
    static let noms: [String: String] = [
        "n-0PWT8HZD80QMSPPDZ5CQXXYHQC": "nitrogen.air-desktop.org",
        "n-3K3P6H252W8K9370QG1YYTWBWB": "argon.air-desktop.org",
    ]

    static func nom(de annuaire: String) -> String {
        noms[annuaire] ?? (try? Identifiant.analyser(annuaire, genre: .annuaire))?.abrege ?? annuaire
    }
}

/// Le choix retenu, **par application et non par compte** : le compte existe
/// sur toutes les racines à la fois, et changer de compte ne dit rien de la
/// racine à laquelle parler.
struct PreferenceDAnnuaire: @unchecked Sendable {
    // `UserDefaults` est sûr entre fils par contrat de Foundation ; le
    // compilateur ne le sait pas. Un essai passe sa propre suite.
    private let defauts: UserDefaults
    private static let cle = "annuaire.adresse"

    init(defauts: UserDefaults = .standard) {
        self.defauts = defauts
    }

    /// L'annuaire retenu s'il est encore dans la liste ; sinon le premier —
    /// une préférence qui nomme une racine retirée du fichier ne doit pas
    /// laisser l'application sans annuaire. Une préférence retenue avant
    /// 0.20.0 l'était par l'adresse d'hier : elle désigne encore l'entrée
    /// qui la porte.
    func choisi(parmi annuaires: [AnnuaireReel.Reglages]) -> AnnuaireReel.Reglages? {
        let retenue = defauts.string(forKey: Self.cle)
        return annuaires.first { $0.cle == retenue }
            ?? annuaires.first { $0.cleDHier != nil && $0.cleDHier == retenue }
            ?? annuaires.first
    }

    func retenir(_ annuaire: AnnuaireReel.Reglages) {
        defauts.set(annuaire.cle, forKey: Self.cle)
    }
}
