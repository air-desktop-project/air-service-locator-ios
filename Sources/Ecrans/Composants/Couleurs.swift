#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

/// Les couleurs décidées du produit, partagées avec Android. Le reste est
/// celui du système.
///
/// # Les trois états ont les couleurs des boutons de fenêtre de macOS
///
/// Rouge, orange et vert sont ceux que macOS donne à fermer, réduire et
/// plein écran (`#FF5F57`, `#FEBC2E`, `#28C840`) : l'utilisateur les a sous
/// les yeux toute la journée, en haut de chaque fenêtre, et les lit sans y
/// penser. Le vert d'avant (`#2E7D32`) était trop sombre pour une pastille
/// de huit points — il passait pour du gris.
///
/// # Une pastille et un texte ne se teignent pas pareil
///
/// Ces trois couleurs sont faites pour des DISQUES PLEINS. Écrit en
/// `#FEBC2E` sur fond blanc, un mot ne se lit plus. ``Texte`` porte donc les
/// mêmes teintes, assombries pour le fond clair — et les vives pour le fond
/// sombre, où ce sont elles qui se lisent. Pastilles et badges prennent la
/// couleur d'ici ; tout ce qui s'écrit prend celle de ``Texte``.
enum Couleurs {
    static let accent = Color(red: 0x2D / 255, green: 0x6B / 255, blue: 0xB0 / 255)

    /// Le vert de « plein écran » : joignable, vivant, actif.
    static let joignable = Color(red: 0x28 / 255, green: 0xC8 / 255, blue: 0x40 / 255)
    /// L'orange de « réduire » : injoignable, en attente, à surveiller.
    static let attention = Color(red: 0xFE / 255, green: 0xBC / 255, blue: 0x2E / 255)
    /// Le rouge de « fermer » : refusé, révoqué, une erreur.
    static let alerte = Color(red: 0xFF / 255, green: 0x5F / 255, blue: 0x57 / 255)
    /// Ni bon ni mauvais : parti, pas encore posé, rien à dire.
    static let parti = Color.secondary

    /// Les mêmes trois teintes, pour ce qui s'écrit : assombries sur fond
    /// clair, vives sur fond sombre.
    enum Texte {
        static let joignable = Couleurs.selonLeFond(clair: Color(red: 0x1C / 255, green: 0x8C / 255, blue: 0x2C / 255),
                                                    sombre: Couleurs.joignable)
        static let attention = Couleurs.selonLeFond(clair: Color(red: 0x9A / 255, green: 0x69 / 255, blue: 0x00 / 255),
                                                    sombre: Couleurs.attention)
        static let alerte = Couleurs.selonLeFond(clair: Color(red: 0xC4 / 255, green: 0x2B / 255, blue: 0x24 / 255),
                                                 sombre: Couleurs.alerte)
    }

    /// Une couleur qui suit l'apparence. Elle se résout à l'affichage, et non
    /// une fois pour toutes : une bascule clair/sombre la retourne sans que
    /// rien ne se recompose.
    private static func selonLeFond(clair: Color, sombre: Color) -> Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { apparence in
            apparence.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(sombre) : NSColor(clair)
        })
        #else
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(sombre) : UIColor(clair)
        })
        #endif
    }
}
