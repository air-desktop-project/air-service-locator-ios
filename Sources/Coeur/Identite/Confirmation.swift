import LocalAuthentication

extension IdentiteLocale {
    /// Demande à l'appareil de confirmer l'identité de son porteur, ici et
    /// maintenant.
    ///
    /// **Ce booléen n'est pas une preuve**, et il ne part nulle part. Dans le
    /// produit fini, la confirmation est une condition d'usage de la clé de la
    /// Secure Enclave : c'est la signature qui la déclenche, et le serveur ne
    /// voit que la signature. Tant que la clé n'est pas écrite, ce geste tient
    /// sa place à l'écran — pour que l'utilisateur fasse le même geste, au même
    /// moment.
    func confirmer(raison: String) async -> Bool {
        let contexte = LAContext()
        contexte.localizedCancelTitle = "Annuler"
        do {
            return try await contexte.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: raison)
        } catch {
            return false
        }
    }
}
