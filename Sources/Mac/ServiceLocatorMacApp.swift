import SwiftUI

/// L'application macOS : une icône dans la barre de menus, et rien d'autre.
///
/// # Pourquoi la barre de menus
///
/// Sur un Mac, cette application n'a pas d'écran à occuper : elle dit où en
/// sont les machines, et sert à enrôler — ce Mac, ou un téléphone de plus.
/// C'est une information qu'on regarde d'un coup d'œil, et un geste qu'on
/// fait rarement. Un panneau sous une icône, c'est sa juste place ;
/// `LSUIElement` la tient hors du Dock.
///
/// # Ce qu'elle réemploie, et ce qu'elle apporte
///
/// Tout le cœur de l'application iOS — le modèle, l'interface `Annuaire`, la
/// clé dans la Secure Enclave, le transport QUIC — est compilé tel quel pour
/// macOS. Ce dossier n'ajoute que le panneau. La clé est la même que sur
/// iPhone : P-256 dans l'enclave du T2 ou de la puce Apple, sous Touch ID à
/// chaque signature (`docs/attestation/enrolement-macos.md` du serveur).
///
/// **Pas d'attestation** : App Attest n'existe pas sur macOS. Le compte se
/// crée en « aucune », ce que les annuaires de test acceptent — et qu'un
/// annuaire racine refusera un jour. Cette application vaut pour ce qu'elle
/// prouve : la chaîne clé-preuve-transport sur du vrai matériel Apple.
@main
struct ServiceLocatorMacApp: App {
    @State private var session: Session

    init() {
        if let reglages = Self.reglagesDeLAnnuaire() {
            let reel = AnnuaireReel(reglages: reglages) { try CleAppareil.ouOuvrir() }
            _session = State(initialValue: Session(annuaire: reel) { signataire in try await reel.ouvrirCompte(avec: signataire) })
        } else {
            let simule = AnnuaireSimule()
            _session = State(initialValue: Session(annuaire: simule) { signataire in try await simule.ouvrirCompteDeDemonstration(avec: signataire) })
        }
    }

    /// `{"adresse": "nitrogen.air-desktop.org:6630", "nom": "nitrogen.air-desktop.org"}`
    /// et la racine en PEM — les mêmes deux fichiers non versionnés que sur
    /// iOS, dans `Sources/Mac/Ressources/`.
    private static func reglagesDeLAnnuaire() -> AnnuaireReel.Reglages? {
        guard let json = Bundle.main.url(forResource: "annuaire", withExtension: "json"),
              let pem = Bundle.main.url(forResource: "annuaire-racine", withExtension: "pem"),
              let donnees = try? Data(contentsOf: json),
              let objet = try? JSONSerialization.jsonObject(with: donnees) as? [String: String],
              let adresse = objet["adresse"], let nom = objet["nom"],
              let racines = try? Data(contentsOf: pem)
        else { return nil }
        return AnnuaireReel.Reglages(adresse: adresse, nom: nom, racinesPEM: racines)
    }

    var body: some Scene {
        MenuBarExtra("Service Locator", image: "BarreDeMenus") {
            PanneauVue()
                .environment(session)
                .tint(Couleurs.accent)
                .frame(width: 380)
        }
        .menuBarExtraStyle(.window)
    }
}
