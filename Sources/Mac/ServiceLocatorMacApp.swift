import AppKit
import SwiftUI

/// L'application macOS : une icône dans la barre de menus, ET une fenêtre.
///
/// # Deux surfaces, deux rôles
///
/// Le **widget** sous l'icône ne fait que DIRE, d'un coup d'œil : le compte,
/// les machines avec leur puce d'état, la version. C'est ce qu'on regarde
/// vingt fois par jour, et il n'a pas de place pour un geste.
///
/// La **fenêtre** est une vraie fenêtre d'application : tout ce que l'écran
/// iPhone sait faire, avec la place d'un Mac — les identifiants en entier,
/// les dates, les verdicts de sonde, la commande `asl` complète, et tous les
/// gestes (déclarer, enrôler, révoquer, émettre un code). Elle s'ouvre depuis
/// le widget, ou sur une machine du widget.
///
/// `LSUIElement` tient l'application hors du Dock tant que la fenêtre est
/// fermée ; ouverte, l'application redevient ordinaire (Dock, menu, ⌘-Tab),
/// et se retire quand la fenêtre se ferme — `FenetreVue` fait ce va-et-vient.
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
    /// Les gestes en cours survivent au popover, qui se ferme dès qu'il perd
    /// le focus — Touch ID compris.
    @State private var gestes = GestesDuPanneau()
    /// Ce Mac en tant que machine — seulement contre un vrai annuaire : le
    /// banc ne sait pas enrôler une machine.
    @State private var machineDeCeMac: MachineDeCeMac?
    /// Ce que l'annuaire a rendu, partagé par le widget et la fenêtre.
    @State private var donnees = Donnees()
    /// La page ouverte dans la fenêtre — le widget peut la choisir.
    @State private var etatFenetre = EtatFenetre()

    init() {
        if let reelle = Session.reelle(annuaires: ChoixDAnnuaire.duPaquet()), let choisi = reelle.annuaireChoisi {
            _session = State(initialValue: reelle)
            _machineDeCeMac = State(initialValue: MachineDeCeMac(reglages: choisi))
        } else {
            let simule = AnnuaireSimule()
            _session = State(initialValue: Session(annuaire: simule) { signataire, invitation in try await simule.ouvrirCompteDeDemonstration(avec: signataire, invitation: invitation) })
        }
    }

    var body: some Scene {
        MenuBarExtra("Service Locator", image: "BarreDeMenus") {
            WidgetVue()
                .environment(session)
                .environment(donnees)
                .environment(etatFenetre)
                .environment(machineDeCeMac)
                .tint(Couleurs.accent)
                .frame(width: 380)
        }
        .menuBarExtraStyle(.window)

        Window("Service Locator", id: FenetreVue.identifiant) {
            FenetreVue()
                .environment(session)
                .environment(donnees)
                .environment(etatFenetre)
                .environment(gestes)
                .environment(machineDeCeMac)
                .tint(Couleurs.accent)
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
        // Le menu de l'application porte les mêmes gestes que la barre
        // d'outils, avec leurs raccourcis : c'est ce qu'un utilisateur de Mac
        // cherche en premier, et ce que la barre d'outils masquée lui laisse.
        .commands {
            CommandMenu("Machines") {
                Button("Ajouter une machine…") { ouvrir(.declarerMachine) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Faire de ce Mac une machine…") { ouvrir(.ceMacMachine) }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Divider()
                Button("Relire l'annuaire") { Task { await donnees.recharger(session) } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            PreferencesVue()
                .environment(session)
                .environment(donnees)
                .environment(machineDeCeMac)
        }
    }

    @Environment(\.openWindow) private var ouvrirFenetre

    /// Un geste du menu ouvre la fenêtre s'il le faut, puis la feuille.
    private func ouvrir(_ feuille: EtatFenetre.Feuille) {
        ouvrirFenetre(id: FenetreVue.identifiant)
        NSApp.activate(ignoringOtherApps: true)
        etatFenetre.feuille = feuille
    }
}
