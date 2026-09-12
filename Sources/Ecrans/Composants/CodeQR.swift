import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Un QR code, tracé depuis un texte — pour qu'un autre téléphone le lise.
///
/// CoreImage le rend à l'échelle 1 (un module par pixel) ; on l'agrandit sans
/// interpolation, sinon les modules baveraient et la lecture échouerait à la
/// première réflexion sur l'écran.
struct CodeQR: View {
    let texte: String
    var taille: CGFloat = 220

    var body: some View {
        if let image = Self.image(pour: texte) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: taille, height: taille)
                .accessibilityLabel("Code à lire par l'autre téléphone")
        } else {
            Text("Le code n'a pas pu être tracé.").foregroundStyle(.red)
        }
    }

    private static func image(pour texte: String) -> UIImage? {
        let filtre = CIFilter.qrCodeGenerator()
        filtre.message = Data(texte.utf8)
        // Correction « M » : assez pour un écran lu de près, sans grossir le
        // code au point de le rendre illisible sur un petit téléphone.
        filtre.correctionLevel = "M"
        guard let sortie = filtre.outputImage else { return nil }
        let contexte = CIContext()
        guard let cg = contexte.createCGImage(sortie, from: sortie.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Le lecteur de QR code : la caméra arrière, et rien d'autre. Ferme la
/// session dès qu'un code a été lu — on ne filme pas plus longtemps que
/// nécessaire.
///
/// Sur le simulateur, il n'y a pas de caméra : le lecteur le dit, et l'écran
/// qui l'emploie propose toujours le champ texte à côté.
struct LecteurQR: UIViewControllerRepresentable {
    let surLecture: @MainActor (String) -> Void

    func makeUIViewController(context: Context) -> Controleur {
        let controleur = Controleur()
        controleur.surLecture = surLecture
        return controleur
    }

    func updateUIViewController(_ uiViewController: Controleur, context: Context) {}

    // Le délégué est appelé sur la file qu'on lui a donnée — la principale —,
    // mais le protocole ne le dit pas au compilateur : d'où cette conformance
    // marquée, tenue par `setMetadataObjectsDelegate(self, queue: .main)`.
    final class Controleur: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
        var surLecture: (@MainActor (String) -> Void)?
        private let session = AVCaptureSession()
        private var apercu: AVCaptureVideoPreviewLayer?
        private var lu = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let entree = try? AVCaptureDeviceInput(device: camera), session.canAddInput(entree) else {
                afficher("Aucune caméra sur cet appareil.")
                return
            }
            session.addInput(entree)
            let sortie = AVCaptureMetadataOutput()
            guard session.canAddOutput(sortie) else { afficher("La caméra ne lit pas de codes."); return }
            session.addOutput(sortie)
            sortie.setMetadataObjectsDelegate(self, queue: .main)
            sortie.metadataObjectTypes = [.qr]
            let couche = AVCaptureVideoPreviewLayer(session: session)
            couche.videoGravity = .resizeAspectFill
            view.layer.addSublayer(couche)
            apercu = couche
            // `startRunning` bloque le temps d'ouvrir la caméra : jamais sur
            // le fil principal. La session est à nous seuls ; AVFoundation ne
            // la déclare pas `Sendable`, d'où la boîte.
            let boite = Boite(session)
            DispatchQueue.global(qos: .userInitiated).async { boite.session.startRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            apercu?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning { session.stopRunning() }
        }

        private struct Boite: @unchecked Sendable {
            let session: AVCaptureSession
            init(_ session: AVCaptureSession) { self.session = session }
        }

        private func afficher(_ message: String) {
            let etiquette = UILabel()
            etiquette.text = message
            etiquette.textColor = .white
            etiquette.textAlignment = .center
            etiquette.numberOfLines = 0
            etiquette.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(etiquette)
            NSLayoutConstraint.activate([
                etiquette.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                etiquette.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                etiquette.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            ])
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objets: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !lu, let code = objets.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first?.stringValue else { return }
            lu = true
            session.stopRunning()
            surLecture?(code)
        }
    }
}

/// Recevoir une invitation : la lire à la caméra, ou la coller. Les deux
/// mènent au même endroit ; le champ n'est pas un pis-aller mais le chemin
/// d'un simulateur, d'une caméra refusée, ou d'un code envoyé par message.
struct ReceptionInvitation: View {
    let attendu: String
    let surInvitation: (Invitation) -> Void
    @State private var texte = ""
    @State private var lecteur = false
    @State private var refus: String?

    var body: some View {
        Section {
            Button {
                lecteur = true
            } label: {
                Label("Lire le code à la caméra", systemImage: "qrcode.viewfinder")
            }
            TextField("ou collez-le ici", text: $texte, axis: .vertical)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .lineLimit(2 ... 4)
                .onSubmit { recevoir(texte) }
            if !texte.isEmpty {
                Button("Valider") { recevoir(texte) }
            }
            if let refus {
                Text(refus).font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            Text(attendu)
        }
        .sheet(isPresented: $lecteur) {
            NavigationStack {
                LecteurQR { code in
                    lecteur = false
                    recevoir(code)
                }
                .ignoresSafeArea()
                .navigationTitle("Lire le code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Annuler") { lecteur = false } }
            }
        }
    }

    private func recevoir(_ candidat: String) {
        guard let invitation = Invitation.analyser(candidat) else {
            refus = "Ce n'est pas un code de cette application."
            return
        }
        refus = nil
        surInvitation(invitation)
    }
}
