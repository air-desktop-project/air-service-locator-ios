import Foundation

/// Ce qu'un identifiant désigne. Le genre est porté par le préfixe, et il est
/// vérifié à la lecture : un identifiant de machine placé là où l'on attend un
/// service est une erreur, pas une valeur à interpréter.
enum Genre: Character, CaseIterable, Sendable {
    case utilisateur = "u"
    case appareil = "a"
    case machine = "m"
    case service = "s"
    case autorisation = "g"
    case annuaire = "n"
}

/// Un identifiant public d'air-service-locator : `u-` + 26 symboles.
///
/// # Il se compare sur ses seize octets, jamais comme une chaîne
///
/// L'alphabet est le base32 de Crockford (`docs/modele.md` §2, `asl-id` côté
/// serveur) : il retire `I`, `L`, `O` et `U`, et **rattrape la faute à la
/// lecture** — `I` et `L` valent `1`, `O` vaut `0`. Plusieurs textes désignent
/// donc le même identifiant, et un `==` sur des chaînes conclurait à tort qu'il
/// s'agit de deux machines. C'est pourquoi ce type porte les octets, et ne rend
/// le texte qu'à l'affichage, toujours sous sa forme canonique.
struct Identifiant: Hashable, Sendable {
    let genre: Genre
    /// Seize octets, gros-boutiens — 128 bits, qui ne se devinent pas.
    let octets: [UInt8]

    /// `0123456789ABCDEFGHJKMNPQRSTVWXYZ` — sans `I`, `L`, `O`, `U`.
    static let alphabet: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    static let longueurTexte = 28
    static let nombreSymboles = 26

    enum Erreur: Error, Equatable {
        case longueur(attendue: Int, obtenue: Int)
        case prefixeInconnu
        case separateurAbsent
        case symboleInvalide(position: Int)
        /// Le premier symbole vaut 8 ou plus : 130 bits ne tiennent pas en 128.
        case debordement
        case genreInattendu(attendu: Genre, obtenu: Genre)
    }

    init(genre: Genre, octets: [UInt8]) {
        precondition(octets.count == 16, "un identifiant porte seize octets")
        self.genre = genre
        self.octets = octets
    }

    /// Un identifiant neuf, depuis seize octets d'aléa fournis par l'appelant.
    /// Ce type ne tire aucun aléa lui-même : c'est ce qui le rend éprouvable.
    init(genre: Genre, entropie: [UInt8]) {
        self.init(genre: genre, octets: entropie)
    }

    /// Le texte canonique : préfixe minuscule, tiret, corps en majuscules.
    var texte: String {
        // 128 bits lus par groupes de 5, de droite à gauche : le premier symbole
        // ne porte que 3 bits, ce qui est la raison du `debordement` à la lecture.
        var symboles = [Character](repeating: "0", count: Self.nombreSymboles)
        var bits = octets.flatMap { octet in (0..<8).reversed().map { (octet >> $0) & 1 } }
        bits.insert(contentsOf: [0, 0], at: 0)  // 130 bits, alignés sur 26 × 5
        for position in 0..<Self.nombreSymboles {
            let tranche = bits[(position * 5)..<(position * 5 + 5)]
            let indice = tranche.reduce(0) { ($0 << 1) | Int($1) }
            symboles[position] = Self.alphabet[indice]
        }
        return "\(genre.rawValue)-\(String(symboles))"
    }

    /// Lit un identifiant, quel que soit son genre. La casse est indifférente,
    /// et les confusions de Crockford sont rattrapées.
    static func analyser(_ texte: String) throws(Erreur) -> Identifiant {
        let caracteres = Array(texte)
        guard caracteres.count == longueurTexte else {
            throw .longueur(attendue: longueurTexte, obtenue: caracteres.count)
        }
        guard let genre = Genre(rawValue: Character(caracteres[0].lowercased())) else {
            throw .prefixeInconnu
        }
        guard caracteres[1] == "-" else { throw .separateurAbsent }

        var bits: [UInt8] = []
        bits.reserveCapacity(130)
        for (position, caractere) in caracteres[2...].enumerated() {
            guard let chiffre = valeur(caractere) else { throw .symboleInvalide(position: position) }
            bits.append(contentsOf: (0..<5).reversed().map { (chiffre >> $0) & 1 })
        }
        // Les deux bits de tête n'ont pas de place dans seize octets.
        guard bits[0] == 0, bits[1] == 0 else { throw .debordement }
        let corps = bits[2...]
        let octets = stride(from: corps.startIndex, to: corps.endIndex, by: 8).map { debut in
            corps[debut..<(debut + 8)].reduce(UInt8(0)) { ($0 << 1) | $1 }
        }
        return Identifiant(genre: genre, octets: octets)
    }

    /// Lit un identifiant en **exigeant** son genre — la forme à préférer
    /// partout où le genre est connu.
    static func analyser(_ texte: String, genre attendu: Genre) throws(Erreur) -> Identifiant {
        let identifiant = try analyser(texte)
        guard identifiant.genre == attendu else {
            throw .genreInattendu(attendu: attendu, obtenu: identifiant.genre)
        }
        return identifiant
    }

    /// La valeur d'un symbole de Crockford, casse indifférente, fautes rattrapées.
    static func valeur(_ caractere: Character) -> UInt8? {
        switch caractere.uppercased() {
        case "I", "L": return 1
        case "O": return 0
        default:
            guard let indice = alphabet.firstIndex(of: Character(caractere.uppercased())) else { return nil }
            return UInt8(indice)
        }
    }

    /// Une forme courte pour les listes : `u-3F8K…Q2W7`. Jamais pour comparer.
    var abrege: String {
        let t = texte
        return "\(t.prefix(6))…\(t.suffix(4))"
    }
}
