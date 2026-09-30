import SwiftUI

extension EtatDEcho {
    /// Vert : prouvé du dehors. Accent : prouvé de l'intérieur, ou pas
    /// encore sondé. Orange : rien n'a répondu. Rouge : une autre clé a
    /// répondu — c'est l'alerte que l'écho est fait pour lever.
    var teinte: Color {
        switch verdict {
        case .verifie: depuis == .exterieur ? Couleurs.joignable : Couleurs.accent
        case .injoignable: Couleurs.attention
        case .autreCle: Couleurs.alerte
        case .enCours, .inconnu: .secondary
        }
    }
}

/// L'état d'écho d'une machine, le même sur l'iPhone et sur le Mac : le
/// libellé avec sa pastille, puis par où, quand et par qui. `nil` : pas
/// d'écho, et comment en lancer un.
struct EtatDEchoVue: View {
    let echo: EtatDEcho?
    /// Dans une liste de machines : on tait l'absence, qui n'y dit rien.
    var compact = false

    var body: some View {
        if let echo {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(echo.teinte).frame(width: 8, height: 8)
                    Text(echo.libelle).font(compact ? .caption : .body)
                }
                if !echo.detail.isEmpty {
                    Text(echo.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if !compact {
            VStack(alignment: .leading, spacing: 2) {
                Text(TextesEcho.absent).foregroundStyle(.secondary)
                Text(TextesEcho.commentLeLancer).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }
}
