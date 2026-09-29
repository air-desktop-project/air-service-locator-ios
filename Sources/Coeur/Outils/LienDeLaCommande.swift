import Foundation

/// Le lien qui met `asl` dans le terminal : `~/.local/bin/asl` →
/// `Air Service Locator.app/Contents/Helpers/asl`.
///
/// # Pourquoi un lien, et pourquoi par un sélecteur
///
/// Sur macOS, `asl` est livré DANS l'application (README du dépôt client,
/// « asl sur macOS ») : même version que l'app, même identité, lue dans le
/// conteneur de groupe. Un lien le rend tapable sans le copier — la copie
/// vieillirait à la prochaine mise à jour de l'app.
///
/// L'application est en bac à sable : elle n'écrit dans `~/.local/bin` que si
/// l'utilisateur lui désigne ce dossier dans un `NSOpenPanel`
/// (`files.user-selected.read-write`). Ce type ne voit que des chemins : le
/// sélecteur est l'affaire de l'écran, et les essais tiennent tout dans un
/// dossier temporaire.
///
/// # On n'écrase pas ce qu'on n'a pas posé
///
/// Un lien, vers n'importe où, se remplace : c'est le nôtre, ou celui d'une
/// ancienne installation. Un FICHIER `asl` — une copie posée à la main, un
/// binaire de développement — ne se remplace que si l'utilisateur l'a dit.
/// Un dossier, jamais.
enum LienDeLaCommande {
    enum Issue: Equatable {
        /// Le lien est posé.
        case cree
        /// Un ancien lien, ou un fichier que l'utilisateur a accepté de
        /// remplacer, a cédé la place.
        case remplace
        /// Le lien existait déjà, vers ce même `asl`.
        case dejaEnPlace
        /// Un fichier `asl` occupe la place : rien n'est touché tant que
        /// l'utilisateur n'a pas dit de le remplacer.
        case fichierEnPlace
        /// Un dossier porte ce nom : on n'y touche pas.
        case dossierEnPlace
    }

    static let nom = "asl"

    /// Le dossier proposé : `~/.local/bin` du COMPTE. Sous le bac à sable,
    /// `HOME` est le conteneur de l'app ; le répertoire du compte se lit dans
    /// la base des utilisateurs, comme le fait `asl` lui-même.
    static var dossierPropose: URL {
        URL(filePath: repertoireDuCompte, directoryHint: .isDirectory).appending(path: ".local/bin", directoryHint: .isDirectory)
    }

    static var repertoireDuCompte: String {
        if let entree = getpwuid(getuid()), let dir = entree.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    /// La commande à copier quand on préfère le terminal au sélecteur.
    static func commande(pour cible: URL) -> String {
        "mkdir -p ~/.local/bin && ln -s \"\(cible.path)\" ~/.local/bin/\(nom)"
    }

    static func lier(_ cible: URL, dans dossier: URL, remplacerUnFichier: Bool = false) throws -> Issue {
        let fm = FileManager.default
        let lien = dossier.appending(path: nom)
        try fm.createDirectory(at: dossier, withIntermediateDirectories: true)

        // `attributesOfItem` ne suit pas le lien : c'est bien lui qu'on juge,
        // même s'il pointe vers une app effacée.
        let existant = try? fm.attributesOfItem(atPath: lien.path)
        var issue = Issue.cree
        switch existant?[.type] as? FileAttributeType {
        case nil:
            break
        case .typeSymbolicLink?:
            if try fm.destinationOfSymbolicLink(atPath: lien.path) == cible.path { return .dejaEnPlace }
            try fm.removeItem(at: lien)
            issue = .remplace
        case .typeDirectory?:
            return .dossierEnPlace
        default:
            guard remplacerUnFichier else { return .fichierEnPlace }
            try fm.removeItem(at: lien)
            issue = .remplace
        }
        try fm.createSymbolicLink(atPath: lien.path, withDestinationPath: cible.path)
        return issue
    }
}
