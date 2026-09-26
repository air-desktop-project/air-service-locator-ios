import SwiftUI

/// Le point d'entrée.
///
/// **C'est ici, et nulle part ailleurs, que l'on choisit qui répond** aux
/// écrans. Si le bundle porte les réglages d'annuaires (`annuaire.json`,
/// `annuaire-racine.pem` — non versionnés, ``ChoixDAnnuaire``), c'est le
/// transport réel, vers la racine retenue ; sinon, le banc en mémoire, peuplé
/// de démonstration. Les écrans ne voient que
/// l'interface `Annuaire`, et ne savent pas lequel des deux leur parle.
@main
struct AirServiceLocatorApp: App {
    @State private var session: Session

    init() {
        if let reelle = Session.reelle(annuaires: ChoixDAnnuaire.duPaquet()) {
            _session = State(initialValue: reelle)
        } else {
            let simule = AnnuaireSimule()
            _session = State(initialValue: Session(annuaire: simule) { signataire, invitation in try await simule.ouvrirCompteDeDemonstration(avec: signataire, invitation: invitation) })
        }
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
    @Environment(\.scenePhase) private var phase

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
        .task {
            await session.rafraichirCompte()
            // L'ouverture a prouvé la clé : la relecture des accès suit sans
            // autre geste. C'est tout ce que l'iPhone a pour apprendre qu'on
            // lui a accordé quelque chose — il n'y a pas de poussée.
            await session.relire()
        }
        // De retour au premier plan, la même relecture — mais seulement si la
        // connexion tient encore : pas de Face ID pour une pastille.
        .onChange(of: phase) { _, phase in
            if phase == .active { Task { await session.relire(sansGeste: true) } }
        }
    }
}

struct OngletsVue: View {
    @Environment(Session.self) private var session

    var body: some View {
        // `.tabItem` plutôt que `Tab` : la cible est iOS 17, et `Tab` demande 18.
        TabView {
            NavigationStack { MachinesVue() }
                .tabItem { Label("Machines", systemImage: "desktopcomputer") }
            NavigationStack { AccesVue() }
                .tabItem { Label("Accès", systemImage: "key.horizontal") }
                // Zéro n'affiche rien.
                .badge(session.nouveautes)
            NavigationStack { CompteVue() }
                .tabItem { Label("Compte", systemImage: "person") }
        }
    }
}
