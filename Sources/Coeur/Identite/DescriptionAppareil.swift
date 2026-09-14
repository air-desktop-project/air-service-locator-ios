import Foundation

extension Appareil.Description {
    /// Ce que CET appareil dit de lui-même à l'annuaire
    /// (`PUT /v1/appareils/{a}/description`, `docs/protocole.md` §2.2).
    ///
    /// # Le modèle, et jamais le nom
    ///
    /// Ce qui part est l'**identifiant de modèle** que le système rend —
    /// `iPhone18,1`, `MacBookPro16,1` : une désignation d'usine, qui ne nomme
    /// personne. Ce qui ne part PAS est le nom que l'utilisateur a donné à
    /// l'appareil (`UIDevice.current.name`, `Host.current().localizedName`) :
    /// « iPhone de Thierry » porte un prénom, précisément ce que C13 refuse.
    /// La même règle vaut pour l'écran de l'appareil lui-même, qui peut montrer
    /// ce nom localement — il ne quitte pas l'appareil.
    ///
    /// L'identifiant d'usine est moins lisible que « iPhone 17 », et c'est un
    /// choix : la table qui traduit l'un en l'autre est celle d'Apple, elle
    /// change à chaque automne, et une traduction fausse serait pire qu'une
    /// désignation brute. L'étiquette sert à reconnaître les siens ; un
    /// identifiant d'usine y suffit.
    static func deCetAppareil() -> Appareil.Description {
        #if os(macOS)
        return Appareil.Description(plateforme: .macos, modele: borner(sysctl("hw.model") ?? "Mac"))
        #else
        // Sur le simulateur, `uname` rend le modèle du Mac hôte ; le modèle
        // simulé est dans l'environnement, et l'étiquette dit que c'en est un.
        if let simule = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return Appareil.Description(plateforme: .ios, modele: borner("\(simule) (simulateur)"))
        }
        return Appareil.Description(plateforme: .ios, modele: borner(uname() ?? "iPhone"))
        #endif
    }

    /// `hw.model` sur un Mac ; `nil` si le noyau ne répond pas.
    private static func sysctl(_ nom: String) -> String? {
        var taille = 0
        guard sysctlbyname(nom, nil, &taille, nil, 0) == 0, taille > 0 else { return nil }
        var tampon = [UInt8](repeating: 0, count: taille)
        guard sysctlbyname(nom, &tampon, &taille, nil, 0) == 0 else { return nil }
        return String(decoding: tampon.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// `utsname.machine` : `iPhone18,1`.
    private static func uname() -> String? {
        var systeme = utsname()
        guard Foundation.uname(&systeme) == 0 else { return nil }
        return withUnsafeBytes(of: &systeme.machine) { octets in
            String(decoding: octets.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// Un à soixante-quatre octets, coupés sur une frontière de caractère :
    /// les règles du nom de machine, tenues avant d'envoyer plutôt que
    /// refusées par l'annuaire.
    private static func borner(_ modele: String) -> String {
        var texte = modele
        while texte.utf8.count > modeleOctetsMax { texte.removeLast() }
        return texte.isEmpty ? "?" : texte
    }
}
