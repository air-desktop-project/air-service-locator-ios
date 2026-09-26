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
/// # LE FICHIER, SOUS SES DEUX FORMES
///
/// ```json
/// {"annuaires": [
///   {"adresse": "asl-root.air-desktop.org:6630", "nom": "asl-root.air-desktop.org", "libelle": "Automatique"},
///   {"adresse": "nitrogen.air-desktop.org:6630", "nom": "nitrogen.air-desktop.org"},
///   {"adresse": "argon.air-desktop.org:6630", "nom": "argon.air-desktop.org"}
/// ]}
/// ```
///
/// L'ancien objet seul, `{"adresse": …, "nom": …}`, reste lu : c'est une
/// liste d'un élément, et les fichiers déjà posés sur les postes de
/// développement continuent de marcher. Une seule racine PEM pour toutes :
/// les certificats des racines sont signés par la même autorité.
enum ChoixDAnnuaire {
    private struct Entree: Decodable {
        let adresse: String
        let nom: String
        let libelle: String?
    }

    private struct Liste: Decodable {
        let annuaires: [Entree]
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
        // Deux entrées à la même adresse n'en font qu'une : c'est l'adresse
        // que la préférence retient.
        var vues = Set<String>()
        return entrees.filter { vues.insert($0.adresse).inserted }.map {
            AnnuaireReel.Reglages(adresse: $0.adresse, nom: $0.nom, racinesPEM: racinesPEM, libelle: $0.libelle)
        }
    }

    /// `annuaire.json` et `annuaire-racine.pem` du paquet — non versionnés ;
    /// absents, la liste est vide et l'application tourne sur le banc.
    static func duPaquet(_ paquet: Bundle = .main) -> [AnnuaireReel.Reglages] {
        guard let json = paquet.url(forResource: "annuaire", withExtension: "json"),
              let pem = paquet.url(forResource: "annuaire-racine", withExtension: "pem"),
              let donnees = try? Data(contentsOf: json),
              let racines = try? Data(contentsOf: pem)
        else { return [] }
        return lire(json: donnees, racinesPEM: racines)
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
        return annuaires.first { $0.adresse == retenue } ?? annuaires.first
    }

    func retenir(_ annuaire: AnnuaireReel.Reglages) {
        defauts.set(annuaire.adresse, forKey: Self.cle)
    }
}
