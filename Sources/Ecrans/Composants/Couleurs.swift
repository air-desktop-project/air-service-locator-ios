import SwiftUI

/// La seule teinte décidée du produit, partagée avec Android. Le reste est
/// celui du système.
enum Couleurs {
    static let accent = Color(red: 0x2D / 255, green: 0x6B / 255, blue: 0xB0 / 255)
    static let joignable = Color(red: 0x2E / 255, green: 0x7D / 255, blue: 0x32 / 255)
    static let attention = Color(red: 0xC7 / 255, green: 0x77 / 255, blue: 0x00 / 255)
    static let parti = Color.secondary
}
