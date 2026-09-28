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
/// **Elle se connecte au lancement** (0.21.0), sans attendre qu'on ouvre le
/// widget ou la fenêtre : la connexion tenue est ce qui entend les nouvelles,
/// donc ce qui notifie. Touch ID est demandé au démarrage. Le widget et la
/// fenêtre rejoignent cette relecture au lieu d'en lancer une autre
/// (``Donnees/recharger(_:)``).
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
    /// Absente quand `annuaire.json` ne désigne aucune racine par son
    /// identité : chaque surface le dit alors (`faute`), sans repli.
    @State private var session: Session?
    @State private var faute: String?
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
        switch ChoixDAnnuaire.duPaquet() {
        case let .annuaires(annuaires):
            let reelle = Session.reelle(annuaires: annuaires)
            _session = State(initialValue: reelle)
            _machineDeCeMac = State(initialValue: reelle?.annuaireChoisi.map(MachineDeCeMac.init(reglages:)))
            // SE CONNECTER DÈS LE LANCEMENT, sans attendre le widget ni la
            // fenêtre : c'est la connexion tenue qui entend les nouvelles, et
            // sans elle un accès accordé ne se notifie pas tant qu'on n'a rien
            // ouvert. Le prix, choisi par Thierry : Touch ID au démarrage.
            let donnees = Donnees()
            _donnees = State(initialValue: donnees)
            if let reelle { Task { await donnees.recharger(reelle) } }
        case let .inutilisable(message):
            _faute = State(initialValue: message)
        case .absent:
            let simule = AnnuaireSimule()
            _session = State(initialValue: Session(annuaire: simule) { signataire, invitation in try await simule.ouvrirCompteDeDemonstration(avec: signataire, invitation: invitation) })
        }
    }

    var body: some Scene {
        MenuBarExtra("Service Locator", image: "BarreDeMenus") {
            Group {
                if let session {
                    WidgetVue()
                        .environment(session)
                        .environment(donnees)
                        .environment(etatFenetre)
                        .environment(machineDeCeMac)
                } else {
                    RacineInutilisableVue(message: faute ?? TextesRacine.aucuneIdentifiee)
                }
            }
            .tint(Couleurs.accent)
            .frame(width: 380)
        }
        .menuBarExtraStyle(.window)

        Window("Service Locator", id: FenetreVue.identifiant) {
            Group {
                if let session {
                    FenetreVue()
                        .environment(session)
                        .environment(donnees)
                        .environment(etatFenetre)
                        .environment(gestes)
                        .environment(machineDeCeMac)
                } else {
                    RacineInutilisableVue(message: faute ?? TextesRacine.aucuneIdentifiee)
                }
            }
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
                Button("Relire l'annuaire") { if let session { Task { await donnees.recharger(session) } } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            if let session {
                PreferencesVue()
                    .environment(session)
                    .environment(donnees)
                    .environment(machineDeCeMac)
            } else {
                RacineInutilisableVue(message: faute ?? TextesRacine.aucuneIdentifiee)
            }
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
