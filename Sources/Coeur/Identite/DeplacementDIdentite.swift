import Foundation

/// Le déménagement de l'identité de machine d'un dossier `asl/` à un autre —
/// du conteneur de l'app Mac vers le conteneur de groupe
/// `SB7H9B6TY8.org.airdesktop.servicelocator`, que l'app et son agent
/// `asl-echo` partagent dans le bac à sable (décision 93, E11 option 2 : l'app
/// Mac ira sur le Mac App Store).
///
/// # On ne perd jamais la graine
///
/// La graine EST la clé de la machine : perdue, la machine se ré-enrôle ;
/// copiée de travers, elle signe au nom d'une autre. D'où l'ordre, que la
/// spec fixe : copier dans un fichier temporaire du dossier d'arrivée,
/// renommer (atomique), **relire et comparer octet à octet**, et seulement
/// alors retirer l'ancienne copie. Une identité DIFFÉRENTE déjà présente à
/// l'arrivée n'est jamais écrasée : rien n'est touché, et on le dit.
///
/// Des fonctions sur des chemins, sans rien du bac à sable : les essais les
/// tiennent dans un dossier temporaire.
enum DeplacementDIdentite {
    enum Issue: Equatable {
        /// Aucune identité, ni ici ni là : rien à faire.
        case rienADeplacer
        /// L'identité est déjà à l'arrivée ; une copie identique au départ a
        /// été retirée.
        case dejaEnPlace
        /// L'identité a été copiée, vérifiée, et l'ancienne retirée.
        case deplacee
        /// Deux identités DIFFÉRENTES, au départ et à l'arrivée : rien n'est
        /// touché. La phrase dit où, pour qu'on tranche à la main.
        case conflit(String)
    }

    static let identite = "identite"
    /// Le cache des racines d'`asl` : suit l'identité, sans conflit possible
    /// — c'est un cache, l'arrivée l'emporte.
    static let racines = "racines"

    static func deplacer(de depart: URL, vers arrivee: URL) throws -> Issue {
        let fm = FileManager.default
        let ancienne = depart.appendingPathComponent(identite)
        let nouvelle = arrivee.appendingPathComponent(identite)
        let issue: Issue
        switch (fm.fileExists(atPath: ancienne.path), fm.fileExists(atPath: nouvelle.path)) {
        case (false, false):
            issue = .rienADeplacer
        case (false, true):
            issue = .dejaEnPlace
        case (true, true):
            guard try Data(contentsOf: ancienne) == Data(contentsOf: nouvelle) else {
                return .conflit("Deux identités de machine différentes : \(ancienne.path) et \(nouvelle.path). Rien n'a été touché ; gardez celle de la machine enrôlée, retirez l'autre.")
            }
            try fm.removeItem(at: ancienne)
            issue = .dejaEnPlace
        case (true, false):
            try copierVerifier(ancienne, vers: nouvelle, dans: arrivee)
            try fm.removeItem(at: ancienne)
            issue = .deplacee
        }
        try deplacerLeCache(de: depart, vers: arrivee)
        return issue
    }

    /// Copier dans un fichier temporaire de l'arrivée, le fermer à 0600,
    /// renommer, relire et comparer. Un écart retire la copie et échoue :
    /// l'ancienne reste.
    private static func copierVerifier(_ source: URL, vers cible: URL, dans dossier: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dossier, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let octets = try Data(contentsOf: source)
        let temporaire = dossier.appendingPathComponent(".\(identite).deplacement")
        if fm.fileExists(atPath: temporaire.path) { try fm.removeItem(at: temporaire) }
        guard fm.createFile(atPath: temporaire.path, contents: octets, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: temporaire.path])
        }
        try fm.moveItem(at: temporaire, to: cible)
        guard try Data(contentsOf: cible) == octets else {
            try? fm.removeItem(at: cible)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: cible.path])
        }
        var valeurs = URLResourceValues()
        valeurs.isExcludedFromBackup = true
        var cibleModifiable = cible
        try? cibleModifiable.setResourceValues(valeurs)
    }

    private static func deplacerLeCache(de depart: URL, vers arrivee: URL) throws {
        let fm = FileManager.default
        let ancien = depart.appendingPathComponent(racines)
        guard fm.fileExists(atPath: ancien.path) else { return }
        let nouveau = arrivee.appendingPathComponent(racines)
        if !fm.fileExists(atPath: nouveau.path) {
            try fm.createDirectory(at: arrivee, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.copyItem(at: ancien, to: nouveau)
        }
        try fm.removeItem(at: ancien)
    }
}
