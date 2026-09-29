import Foundation
import Testing
@testable import AirServiceLocator

/// Le déménagement de l'identité de machine (décision 93) : jamais de perte,
/// jamais d'écrasement d'une identité différente.
struct DeplacementDIdentiteEssais {
    private let racine = FileManager.default.temporaryDirectory.appending(path: "deplacement-\(UUID().uuidString)")
    private var depart: URL { racine.appending(path: "app/asl") }
    private var arrivee: URL { racine.appending(path: "groupe/Library/Application Support/asl") }

    private static let identite = Data("machine = m-26W610F86BVRH6GPKGSSQK9H4S\ngraine = 00112233\n".utf8)
    private static let autre = Data("machine = m-5N5A5Z42DJRZSB6G3HF9PH99AD\ngraine = 44556677\n".utf8)

    private func poser(_ octets: Data, _ nom: String, dans dossier: URL) throws {
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        try octets.write(to: dossier.appending(path: nom))
    }

    private func existe(_ dossier: URL, _ nom: String) -> Bool {
        FileManager.default.fileExists(atPath: dossier.appending(path: nom).path)
    }

    @Test func lIdentiteDemenageAvecSonCacheEtEnMode0600() throws {
        defer { try? FileManager.default.removeItem(at: racine) }
        try poser(Self.identite, "identite", dans: depart)
        try poser(Data("racines".utf8), "racines", dans: depart)
        #expect(try DeplacementDIdentite.deplacer(de: depart, vers: arrivee) == .deplacee)
        #expect(try Data(contentsOf: arrivee.appending(path: "identite")) == Self.identite)
        #expect(existe(arrivee, "racines"))
        #expect(!existe(depart, "identite"))
        #expect(!existe(depart, "racines"))
        #expect(!existe(arrivee, ".identite.deplacement"))
        let droits = try FileManager.default.attributesOfItem(atPath: arrivee.appending(path: "identite").path)[.posixPermissions] as? Int
        #expect(droits == 0o600)
        // Le lancement suivant n'a plus rien à faire.
        #expect(try DeplacementDIdentite.deplacer(de: depart, vers: arrivee) == .dejaEnPlace)
    }

    @Test func rienADeplacerSansIdentite() throws {
        defer { try? FileManager.default.removeItem(at: racine) }
        #expect(try DeplacementDIdentite.deplacer(de: depart, vers: arrivee) == .rienADeplacer)
    }

    /// La même identité des deux côtés : l'ancienne copie se retire.
    @Test func uneCopieIdentiqueSeRetire() throws {
        defer { try? FileManager.default.removeItem(at: racine) }
        try poser(Self.identite, "identite", dans: depart)
        try poser(Self.identite, "identite", dans: arrivee)
        #expect(try DeplacementDIdentite.deplacer(de: depart, vers: arrivee) == .dejaEnPlace)
        #expect(!existe(depart, "identite"))
        #expect(try Data(contentsOf: arrivee.appending(path: "identite")) == Self.identite)
    }

    /// Deux identités différentes : rien n'est touché, et on le dit.
    @Test func deuxIdentitesDifferentesNeSeTouchentPas() throws {
        defer { try? FileManager.default.removeItem(at: racine) }
        try poser(Self.identite, "identite", dans: depart)
        try poser(Self.autre, "identite", dans: arrivee)
        guard case let .conflit(phrase) = try DeplacementDIdentite.deplacer(de: depart, vers: arrivee) else {
            Issue.record("un conflit était attendu"); return
        }
        #expect(phrase.contains(depart.path) && phrase.contains(arrivee.path))
        #expect(try Data(contentsOf: depart.appending(path: "identite")) == Self.identite)
        #expect(try Data(contentsOf: arrivee.appending(path: "identite")) == Self.autre)
    }

    /// Le cache des racines : l'arrivée l'emporte, l'ancien se retire.
    @Test func leCacheDArriveeLEmporte() throws {
        defer { try? FileManager.default.removeItem(at: racine) }
        try poser(Data("ancien".utf8), "racines", dans: depart)
        try poser(Data("nouveau".utf8), "racines", dans: arrivee)
        #expect(try DeplacementDIdentite.deplacer(de: depart, vers: arrivee) == .rienADeplacer)
        #expect(try Data(contentsOf: arrivee.appending(path: "racines")) == Data("nouveau".utf8))
        #expect(!existe(depart, "racines"))
    }
}
