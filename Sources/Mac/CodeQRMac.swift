import CoreImage.CIFilterBuiltins
import SwiftUI

/// Un QR code, tracé depuis un texte — pour qu'un téléphone le lise.
///
/// Le Mac n'a pas de caméra qui lise un code, mais il a un écran qui en
/// affiche : la moitié « Mac → téléphone » de l'invitation
/// (`Coeur/Modele/Invitation.swift`) peut donc se lire à la caméra du
/// téléphone, comme entre deux téléphones. Seule la moitié « téléphone → Mac »
/// reste un texte collé.
///
/// Même recette que `Ecrans/Composants/CodeQR.swift` : CoreImage rend un
/// module par pixel, et l'image est agrandie sans interpolation, sinon les
/// modules baveraient. Le composant iOS n'est pas réutilisé tel quel parce
/// qu'il lie UIKit et AVFoundation pour le lecteur, qui n'ont rien à faire ici.
struct CodeQRMac: View {
    let texte: String
    var taille: CGFloat = 160

    var body: some View {
        if let image = Self.image(pour: texte) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: taille, height: taille)
                // Un fond blanc sous le code, même en apparence sombre : les
                // lecteurs veulent du noir sur blanc, pas l'inverse.
                .padding(6)
                .background(Color.white)
                .accessibilityLabel("Code à lire par le téléphone")
        } else {
            Text("Le code n'a pas pu être tracé.").font(.caption).foregroundStyle(.red)
        }
    }

    private static func image(pour texte: String) -> CGImage? {
        let filtre = CIFilter.qrCodeGenerator()
        filtre.message = Data(texte.utf8)
        // Correction « M », comme sur iOS : assez pour un écran lu de près.
        filtre.correctionLevel = "M"
        guard let sortie = filtre.outputImage else { return nil }
        return CIContext().createCGImage(sortie, from: sortie.extent)
    }
}
