import AppKit
import SwiftUI

/// « Installer la commande asl » : le lien `~/.local/bin/asl` vers l'`asl`
/// livré dans le paquet (`Contents/Helpers/asl`, README du dépôt client,
/// « asl sur macOS »).
///
/// L'application est en bac à sable : elle ne pose le lien que dans le
/// dossier que l'utilisateur lui désigne (`NSOpenPanel`,
/// `files.user-selected.read-write`). La commande à copier reste affichée
/// pour qui préfère le terminal.
struct CommandeAslVue: View {
    @State private var issue: (texte: String, echec: Bool)?

    /// L'`asl` du paquet — celui-ci, où qu'il soit : `/Applications` ou
    /// `build/Debug`.
    static var asl: URL { Bundle.main.bundleURL.appending(path: "Contents/Helpers/asl") }
    private var present: Bool { FileManager.default.isExecutableFile(atPath: Self.asl.path) }

    var body: some View {
        Form {
            LabeledContent("asl dans l'application") {
                if present { Copiable(Self.asl.path) } else { Text("absent de ce paquet").foregroundStyle(.secondary) }
            }
            LabeledContent("Dans le terminal") {
                Button("Installer la commande asl…") { choisirLeDossier() }.disabled(!present)
            }
            if let issue {
                Label(issue.texte, systemImage: issue.echec ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(issue.echec ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("Ou copiez") { Copiable(LienDeLaCommande.commande(pour: Self.asl)) }
            Text("Le bouton pose un lien, pas une copie : asl suit les mises à jour de l'application, et lit la même identité de machine qu'elle. Choisissez ~/.local/bin, ou un autre dossier de votre PATH.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    private func choisirLeDossier() {
        let panneau = NSOpenPanel()
        panneau.canChooseDirectories = true
        panneau.canChooseFiles = false
        panneau.canCreateDirectories = true
        panneau.allowsMultipleSelection = false
        // `.local` est caché : sans cela, ~/.local/bin ne se voit pas.
        panneau.showsHiddenFiles = true
        panneau.directoryURL = LienDeLaCommande.dossierPropose
        panneau.prompt = "Installer ici"
        panneau.message = "Où poser la commande asl ? ~/.local/bin est proposé ; il doit être dans votre PATH."
        guard panneau.runModal() == .OK, let dossier = panneau.url else { return }
        poser(dans: dossier, remplacerUnFichier: false)
    }

    private func poser(dans dossier: URL, remplacerUnFichier: Bool) {
        let lien = dossier.appending(path: LienDeLaCommande.nom).path
        do {
            switch try LienDeLaCommande.lier(Self.asl, dans: dossier, remplacerUnFichier: remplacerUnFichier) {
            case .cree: issue = ("Commande installée : \(lien)", false)
            case .remplace: issue = ("Commande installée, à la place de l'ancienne : \(lien)", false)
            case .dejaEnPlace: issue = ("La commande était déjà installée : \(lien)", false)
            case .dossierEnPlace: issue = ("Un dossier « asl » occupe déjà \(lien) : rien n'a été touché.", true)
            case .fichierEnPlace:
                let alerte = NSAlert()
                alerte.messageText = "Un fichier asl existe déjà dans ce dossier."
                alerte.informativeText = "\(lien) est un fichier, sans doute une copie installée à la main. Le remplacer par un lien vers l'asl de l'application ?"
                alerte.addButton(withTitle: "Remplacer")
                alerte.addButton(withTitle: "Annuler")
                if alerte.runModal() == .alertFirstButtonReturn {
                    poser(dans: dossier, remplacerUnFichier: true)
                } else {
                    issue = ("Rien n'a été touché : \(lien) reste en place.", true)
                }
            }
        } catch {
            issue = ("Le lien n'a pas pu être posé : \(error.localizedDescription)", true)
        }
    }
}
