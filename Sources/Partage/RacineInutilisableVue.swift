import SwiftUI

/// Ce que l'application montre quand son `annuaire.json` ne désigne aucune
/// racine par son identité : le dire, et rien d'autre. Ni le DNS, ni le banc
/// de démonstration ne prennent la place — un compte réel ne doit jamais se
/// retrouver à parler à un faux annuaire sans le savoir.
struct RacineInutilisableVue: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(TextesRacine.aucuneTitre, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
        .padding()
    }
}
