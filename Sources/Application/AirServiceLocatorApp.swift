import SwiftUI

/// Le point d'entrée de l'application.
///
/// Il ne fait rien d'autre qu'afficher où en est ce dépôt. Une application qui
/// présenterait des écrans vides aurait l'air de fonctionner ; celle-ci dit
/// qu'elle n'a rien à montrer, parce que les spécifications ne sont pas écrites.
@main
struct AirServiceLocatorApp: App {
    var body: some Scene {
        WindowGroup {
            EcranProvisoire()
        }
    }
}

/// À REMPLACER par la navigation réelle dès que les écrans seront arrêtés.
struct EcranProvisoire: View {
    /// Ce que l'appareil sait faire, mesuré une fois au lancement.
    ///
    /// **La question est posée ICI, dès le premier écran, et c'est délibéré.**
    /// Un appareil sans reconnaissance faciale ni empreinte ne peut pas porter
    /// cette application : le découvrir au moment de la première connexion
    /// ferait installer, ouvrir un compte, puis échouer. Le découvrir au
    /// lancement permet de le dire tout de suite.
    private let identite = IdentiteLocale()

    var body: some View {
        VStack(spacing: 16) {
            Text("air-service-locator")
                .font(.title2.weight(.semibold))

            Text("Ce dépôt porte une arborescence, pas encore une application.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Divider()

            Text(identite.etat().description)
                .font(.footnote.monospaced())
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
