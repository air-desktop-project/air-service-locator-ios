import Foundation

/// Les règles du nom d'une machine et des alias, telles que l'annuaire les
/// tient depuis 0.26.0 (`asl-registre`, décisions 45 à 47).
///
/// # POURQUOI L'APPLICATION LES REDIT
///
/// L'annuaire refuse d'un `400` ce qui ne passe pas, et c'est lui qui fait
/// foi. Mais un `400` est un refus générique, dit après coup : l'écran doit
/// pouvoir dire **avant d'envoyer** ce qui ne va pas — « pas d'espace ni
/// d'accent » — et montrer la forme que l'annuaire rangera. Les règles sont
/// donc recopiées ici, octet pour octet ; les essais les tiennent contre les
/// exemples du serveur.
enum NomsEtAlias {
    // MARK: - Le nom d'une machine : un nom d'hôte

    /// Une étiquette RFC 1123 : 1 à 63 octets.
    static let nomOctetsMax = 63

    /// Le nom tel que l'annuaire le rangera — en minuscules, le DNS comparant
    /// sans casse (RFC 4343) —, ou `nil` s'il ne peut pas servir de nom
    /// d'hôte : lettres ASCII, chiffres et tiret, ni tiret en tête ni en queue.
    static func nomDHote(_ nom: String) -> String? {
        let octets = Array(nom.utf8)
        let tiret = UInt8(ascii: "-")
        let admis: (UInt8) -> Bool = { octet in
            (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(octet)
                || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(octet)
                || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(octet)
                || octet == tiret
        }
        guard (1...nomOctetsMax).contains(octets.count), octets.allSatisfy(admis),
              octets.first != tiret, octets.last != tiret
        else { return nil }
        return nom.lowercased()
    }

    // MARK: - Les alias : du texte choisi, en NFC

    /// La forme NFC — une même chaîne composée ou décomposée est une seule
    /// chaîne ; c'est celle que l'annuaire range et compare, octet pour octet.
    static func nfc(_ texte: String) -> String {
        texte.precomposedStringWithCanonicalMapping
    }

    /// Les caractères qu'aucun alias ne porte : contrôles C0 et DEL, C1,
    /// forceurs de sens d'écriture, marque d'ordre des octets, et les deux que
    /// la grammaire JSON de l'API refuse dans un texte libre.
    static func refuse(_ scalaire: Unicode.Scalar) -> Bool {
        switch scalaire.value {
        case 0x00...0x1F, 0x7F...0x9F, 0x202A...0x202E, 0x2066...0x2069, 0xFEFF: true
        default: scalaire == "\"" || scalaire == "\\"
        }
    }

    /// Un alias de compte : **unique**, 3 à 32 octets après NFC, sensible à la
    /// casse, et **pas de tiret en deuxième caractère** — il ne doit pas
    /// ressembler à un `u-…`. Au plus 255 octets saisis avant NFC.
    static func aliasDeCompteValide(_ alias: String) -> Bool {
        guard alias.utf8.count <= 255 else { return false }
        let forme = nfc(alias)
        let scalaires = Array(forme.unicodeScalars)
        return (3...32).contains(forme.utf8.count)
            && !scalaires.contains(where: refuse)
            && scalaires.dropFirst().first != "-"
    }

    /// Un alias de machine : 1 à 253 octets après NFC — la longueur d'un nom
    /// complet —, sensible à la casse, **non unique**. Au plus 480 octets
    /// saisis avant NFC.
    static func aliasDeMachineValide(_ alias: String) -> Bool {
        guard alias.utf8.count <= 480 else { return false }
        let forme = nfc(alias)
        return (1...253).contains(forme.utf8.count) && !forme.unicodeScalars.contains(where: refuse)
    }

    // MARK: - Résoudre un alias de compte

    /// Le chemin de `GET` qui résout cet alias. Un alias ASCII garde la forme
    /// historique `/v1/alias/{alias}`, qu'un annuaire d'avant 0.26.0 sert
    /// aussi ; un alias UTF-8 passe par `?alias=`, pourcent-encodé, en NFC.
    static func cheminDeResolution(_ alias: String) -> String {
        let forme = nfc(alias)
        if forme.unicodeScalars.allSatisfy(\.isASCII) && !forme.contains("/") && !forme.contains("?") && !forme.contains("%") && !forme.contains("#") && !forme.contains(" ") {
            return "/v1/alias/\(forme)"
        }
        return "/v1/alias?alias=\(pourcentEncode(forme))"
    }

    /// RFC 3986 : seuls les caractères non réservés restent tels quels ;
    /// tout le reste, octet UTF-8 par octet, en `%XX`.
    static func pourcentEncode(_ texte: String) -> String {
        var sortie = ""
        for octet in texte.utf8 {
            let c = Character(UnicodeScalar(octet))
            if octet < 0x80, c.isLetter || c.isNumber || "-._~".contains(c) {
                sortie.append(c)
            } else {
                sortie += String(format: "%%%02X", octet)
            }
        }
        return sortie
    }
}

/// Ce que les écrans disent des noms et des alias — les mêmes mots sur
/// l'iPhone, le Mac et Android.
enum TextesNoms {
    static let regleDuNom = "Lettres, chiffres et tirets, sans espace ni accent — c'est le nom d'hôte."
    static func rangeSous(_ forme: String) -> String { "Sera rangé « \(forme) »." }
    static let alias = "Alias"
    static let explicationAlias = "Texte libre, pour vous : un nom complet, avec espaces et accents si vous voulez. Plusieurs machines peuvent porter le même."
    static let aliasIndisponible = "Cet annuaire ne sait pas encore ranger l'alias d'une machine (il faut la version 0.26.0)."
    static let regleAliasDeCompte = "3 à 32 octets, majuscules et accents permis ; pas de tiret en deuxième caractère."
}
