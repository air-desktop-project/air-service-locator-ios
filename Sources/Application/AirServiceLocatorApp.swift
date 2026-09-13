import SwiftUI

/// Le point d'entrée.
///
/// **C'est ici, et nulle part ailleurs, que l'on choisit qui répond** aux
/// écrans. Si le bundle porte les réglages d'un annuaire (`annuaire.json`,
/// `annuaire-racine.pem` — non versionnés), c'est le transport réel ; sinon,
/// le banc en mémoire, peuplé de démonstration. Les écrans ne voient que
/// l'interface `Annuaire`, et ne savent pas lequel des deux leur parle.
@main
struct AirServiceLocatorApp: App {
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

    /// `{"adresse": "192.0.2.1:6630", "nom": "annuaire"}` et la racine en PEM.
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
        WindowGroup {
            RacineVue()
                .environment(session)
                .tint(Couleurs.accent)
        }
    }
}

/// Accueil tant qu'il n'y a pas de compte, les onglets ensuite.
struct RacineVue: View {
    @Environment(Session.self) private var session

    var body: some View {
        Group {
            if session.premiereRelectureEnCours {
                // Le compte se relit à l'annuaire — et c'est un geste, sur un
                // appareil enrôlé. Ni l'accueil ni les onglets avant de savoir.
                VStack(spacing: 12) {
                    Logo(taille: 64)
                    ProgressView()
                }
            } else if session.compte == nil {
                AccueilVue()
            } else {
                OngletsVue()
            }
        }
        .task { await session.rafraichirCompte() }
    }
}

struct OngletsVue: View {
    var body: some View {
        // `.tabItem` plutôt que `Tab` : la cible est iOS 17, et `Tab` demande 18.
        TabView {
            NavigationStack { MachinesVue() }
                .tabItem { Label("Machines", systemImage: "desktopcomputer") }
            NavigationStack { AccesVue() }
                .tabItem { Label("Accès", systemImage: "key.horizontal") }
            NavigationStack { CompteVue() }
                .tabItem { Label("Compte", systemImage: "person") }
        }
    }
}
