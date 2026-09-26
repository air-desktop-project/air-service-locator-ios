import AppKit
import SwiftUI

/// Les préférences (⌘,) : ce que cette application tient de réglé, et où.
///
/// Il n'y a pas grand-chose à régler, et c'est dit plutôt que masqué :
/// l'annuaire vient des deux fichiers embarqués à la construction
/// (`annuaire.json`, `annuaire-racine.pem`), et les identités de ce Mac
/// vivent dans son conteneur. Ce que l'écran donne, c'est de quoi les
/// retrouver — et de quoi les copier.
struct PreferencesVue: View {
    @Environment(Session.self) private var session
    @Environment(Donnees.self) private var donnees
    @Environment(MachineDeCeMac.self) private var machineDeCeMac: MachineDeCeMac?

    var body: some View {
        TabView {
            annuaire.tabItem { Label("Annuaire", systemImage: "network") }
            ceMac.tabItem { Label("Ce Mac", systemImage: "laptopcomputer") }
        }
        .frame(width: 560, height: 420)
    }

    private var annuaire: some View {
        Form {
            LabeledContent("Annuaire", value: session.annuaireChoisi?.nom ?? session.annuaire.nom)
            // Un seul annuaire dans le fichier : rien à choisir, rien d'affiché.
            if session.annuaires.count > 1 {
                Picker(TextesRacine.titre, selection: Binding(
                    get: { session.annuaireChoisi?.adresse ?? "" },
                    set: { adresse in
                        guard let choisi = session.annuaires.first(where: { $0.adresse == adresse }) else { return }
                        Task { await basculer(vers: choisi) }
                    }
                )) {
                    ForEach(session.annuaires, id: \.adresse) { Text($0.affiche).tag($0.adresse) }
                }
                Text(TextesRacine.explication).font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("Version de l'annuaire") {
                switch donnees.versionAnnuaire {
                case .some(.some(let annuaire)): Text(annuaire.version)
                case .some(.none): Text("ne la dit pas").foregroundStyle(.secondary)
                case .none: Text("—").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Racines", value: "air-desktop-project")
            Text("Les racines proposées sont fixées à la construction de l'application, par `annuaire.json` et `annuaire-racine.pem` dans ses ressources ; le choix parmi elles se fait ici, et il est retenu.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    /// La racine change : l'ancienne est fermée — écoute des nouvelles
    /// comprise —, l'enrôlement d'une machine suivra la nouvelle, et la
    /// relecture reprouve la clé de ce Mac sous Touch ID.
    private func basculer(vers choisi: AnnuaireReel.Reglages) async {
        await session.choisirAnnuaire(choisi)
        machineDeCeMac?.reglages = choisi
        await donnees.recharger(session)
    }

    private var ceMac: some View {
        Form {
            LabeledContent("Version de l'application", value: Version.texte)
            LabeledContent("Appareil") {
                if let moi = Carnet.appareilEnrole { Copiable(moi.texte) } else { Text("pas enrôlé").foregroundStyle(.secondary) }
            }
            LabeledContent("Machine") {
                if let machine = machineDeCeMac?.identifiant { Copiable(machine.texte) } else { Text("ce Mac n'est pas une machine").foregroundStyle(.secondary) }
            }
            if let dossier = MachineDeCeMac.dossierPourAsl {
                LabeledContent("Dossier pour asl") { Copiable(dossier) }
            }
            Text("La clé d'appareil vit dans la Secure Enclave et signe sous Touch ID ; la clé de machine est dans le dossier ci-dessus, au format de l'utilitaire asl, en 0600. Ni l'une ni l'autre ne quitte ce Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}
