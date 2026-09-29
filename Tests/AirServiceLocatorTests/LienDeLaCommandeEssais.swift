import Foundation
import Testing
@testable import AirServiceLocator

/// Le lien `~/.local/bin/asl` vers l'`asl` du paquet Mac : un lien se
/// remplace, un fichier seulement sur accord, un dossier jamais.
struct LienDeLaCommandeEssais {
    private let racine = FileManager.default.temporaryDirectory.appending(path: "lien-\(UUID().uuidString)")
    private var bin: URL { racine.appending(path: ".local/bin") }
    private var lien: URL { bin.appending(path: "asl") }
    private var asl: URL { racine.appending(path: "Air Service Locator.app/Contents/Helpers/asl") }

    private func destination() throws -> String {
        try FileManager.default.destinationOfSymbolicLink(atPath: lien.path)
    }

    @Test func leLienSePoseEtLeDossierSeCree() throws {
        defer { try? FileManager.default.removeItem(at: racine) }
        #expect(try LienDeLaCommande.lier(asl, dans: bin) == .cree)
        #expect(try destination() == asl.path)
        #expect(try LienDeLaCommande.lier(asl, dans: bin) == .dejaEnPlace)
    }

    /// L'app a changé de place (`build/Debug` → `/Applications`) : l'ancien
    /// lien, même cassé, cède la place sans rien demander.
    @Test func unAncienLienSeRemplace() throws {
        defer { try? FileManager.default.removeItem(at: racine) }
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: lien.path, withDestinationPath: "/nulle/part/asl")
        #expect(try LienDeLaCommande.lier(asl, dans: bin) == .remplace)
        #expect(try destination() == asl.path)
    }

    @Test func unFichierNeSeRemplaceQueSurAccord() throws {
        defer { try? FileManager.default.removeItem(at: racine) }
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let copie = Data("une copie posée à la main".utf8)
        try copie.write(to: lien)
        #expect(try LienDeLaCommande.lier(asl, dans: bin) == .fichierEnPlace)
        #expect(try Data(contentsOf: lien) == copie)
        #expect(try LienDeLaCommande.lier(asl, dans: bin, remplacerUnFichier: true) == .remplace)
        #expect(try destination() == asl.path)
    }

    @Test func unDossierNeSeTouchePas() throws {
        defer { try? FileManager.default.removeItem(at: racine) }
        try FileManager.default.createDirectory(at: lien, withIntermediateDirectories: true)
        #expect(try LienDeLaCommande.lier(asl, dans: bin, remplacerUnFichier: true) == .dossierEnPlace)
        var estUnDossier: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: lien.path, isDirectory: &estUnDossier) && estUnDossier.boolValue)
    }

    /// La commande à copier cite le chemin entre guillemets — « Air Service
    /// Locator.app » a des espaces — et n'écrase rien (`ln -s`, sans `-f`).
    @Test func laCommandeSeColleTelleQuelle() {
        let commande = LienDeLaCommande.commande(pour: URL(filePath: "/Applications/Air Service Locator.app/Contents/Helpers/asl"))
        #expect(commande == "mkdir -p ~/.local/bin && ln -s \"/Applications/Air Service Locator.app/Contents/Helpers/asl\" ~/.local/bin/asl")
    }
}
