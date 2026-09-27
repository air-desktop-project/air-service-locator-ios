import Foundation

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
/// # LE FICHIER : L'IDENTITÉ PAR LA CLÉ, ET LA FORME D'HIER
///
/// ```json
/// {"annuaires": [
///   {"libelle": "Automatique",
///    "adresse": "asl-root.air-desktop.org:6630", "nom": "asl-root.air-desktop.org",
///    "racines": [
///      {"annuaire": "n-0PWT8HZD80QMSPPDZ5CQXXYHQC", "locateurs": ["[2001:41d0:20a:900::1dd4]:6630", "178.32.16.250:6630"]},
///      {"annuaire": "n-3K3P6H252W8K9370QG1YYTWBWB", "locateurs": ["[2001:41d0:20a:900::1d32]:6630", "178.32.16.249:6630"]}]},
///   {"adresse": "nitrogen.air-desktop.org:6630", "nom": "nitrogen.air-desktop.org",
///    "annuaire": "n-0PWT8HZD80QMSPPDZ5CQXXYHQC", "locateurs": ["[2001:41d0:20a:900::1dd4]:6630", "178.32.16.250:6630"]},
///   {"adresse": "argon.air-desktop.org:6630", "nom": "argon.air-desktop.org",
///    "annuaire": "n-3K3P6H252W8K9370QG1YYTWBWB", "locateurs": ["[2001:41d0:20a:900::1d32]:6630", "178.32.16.249:6630"]}
/// ]}
/// ```
///
/// Une entrée **identifiée** dit qui l'on doit trouver au bout (`annuaire`,
/// le `n-…` que la clé d'identité de la racine donne) et où le joindre
/// (`locateurs`, des adresses LITTÉRALES — aucun nom ne se résout, décision
/// 58). Une entrée qui couvre plusieurs racines — « Automatique » — les
/// liste dans `racines`, chacune avec les siennes. Un locateur qui n'est pas
/// littéral, un `n-…` de travers, se laissent de côté : on ne devine pas.
///
/// `adresse` et `nom` sont la forme d'hier — un nom DNS, résolu ici, et le
/// nom exigé du certificat. Une entrée identifiée ne s'en sert pas pour se
/// connecter ; ils restent dans le fichier le temps de la bascule parce que
/// les versions d'hier de l'application (≤ 0.15) ne lisent qu'eux, et
/// qu'une préférence retenue par son adresse doit continuer de désigner la
/// même entrée. L'ancien objet seul, `{"adresse": …, "nom": …}`, reste lu
/// aussi : c'est une liste d'un élément.
///
/// Une seule racine PEM pour toutes : les certificats d'hier sont signés par
/// la même autorité. Elle n'est plus exigée : sans elle, seules les entrées
/// identifiées restent — une entrée d'hier n'aurait rien à croire.
enum ChoixDAnnuaire {
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

    /// `[IPv6]:port` ou `IPv4:port` — ce qu'`asl_appareil_annuaire_identifie`
    /// accepte, et rien qui demande un résolveur.
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

    /// Les annuaires décrits par ce JSON, dans l'ordre du fichier ; vide si
    /// le fichier ne dit rien de lisible.
    static func lire(json: Data, racinesPEM: Data) -> [AnnuaireReel.Reglages] {
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
            let hier = entree.adresse.flatMap { adresse in entree.nom.map { (adresse, $0) } }
            // Une entrée d'hier sans autorité n'a rien à croire ; une entrée
            // sans rien de lisible n'est pas une entrée.
            guard !identites.isEmpty || (hier != nil && !racinesPEM.isEmpty) else { return nil }
            let nom = entree.nom ?? identites.first.map { RacinesConnues.nom(de: $0.annuaire) } ?? ""
            return AnnuaireReel.Reglages(adresse: entree.adresse ?? "", nom: nom, racinesPEM: racinesPEM,
                                         libelle: entree.libelle, identites: identites)
        }
        // Deux entrées de même clé n'en font qu'une : c'est la clé que la
        // préférence retient.
        var vues = Set<String>()
        return reglages.filter { vues.insert($0.cle).inserted }
    }

    /// `annuaire.json` et `annuaire-racine.pem` du paquet — non versionnés ;
    /// sans liste lisible, l'application tourne sur le banc. Le PEM peut
    /// manquer : les entrées identifiées n'en ont pas besoin.
    static func duPaquet(_ paquet: Bundle = .main) -> [AnnuaireReel.Reglages] {
        guard let json = paquet.url(forResource: "annuaire", withExtension: "json"),
              let donnees = try? Data(contentsOf: json)
        else { return [] }
        let racines = paquet.url(forResource: "annuaire-racine", withExtension: "pem").flatMap { try? Data(contentsOf: $0) } ?? Data()
        return lire(json: donnees, racinesPEM: racines)
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
    /// laisser l'application sans annuaire.
    func choisi(parmi annuaires: [AnnuaireReel.Reglages]) -> AnnuaireReel.Reglages? {
        let retenue = defauts.string(forKey: Self.cle)
        return annuaires.first { $0.cle == retenue } ?? annuaires.first
    }

    func retenir(_ annuaire: AnnuaireReel.Reglages) {
        defauts.set(annuaire.cle, forKey: Self.cle)
    }
}
