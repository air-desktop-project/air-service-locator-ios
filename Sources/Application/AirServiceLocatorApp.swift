import SwiftUI

/// Le point d'entrée.
///
/// **L'annuaire est simulé** (`AnnuaireSimule`) tant que le transport de
/// `asl-client` n'est pas embarqué : les écrans parlent à l'interface
/// `Annuaire`, et c'est ici, et nulle part ailleurs, que l'on choisit qui
/// répond. Le jour où le client Rust arrive, cette composition change ; les
/// écrans, non.
@main
struct AirServiceLocatorApp: App {
    @State private var session: Session

    init() {
        let simule = AnnuaireSimule()
        _session = State(initialValue: Session(annuaire: simule) { cle, preuve in try await simule.ouvrirCompteDeDemonstration(cle: cle, preuve: preuve) })
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
            if session.compte == nil {
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
