import LocalAuthentication

/// Ce que l'appareil peut confirmer de l'identité de son porteur, et rien de
/// plus.
///
/// # La contrainte du produit, et ce qu'elle veut RÉELLEMENT dire
///
/// `air-service-locator` ne se déploie que sur des appareils capables de
/// confirmer localement l'identité de leur porteur — Face ID ou Touch ID.
///
/// **Cette confirmation a lieu SUR L'APPAREIL, et son résultat ne quitte pas
/// l'appareil.** iOS ne rend jamais un gabarit facial ni une empreinte : ces
/// données vivent dans la Secure Enclave, et aucune API ne les expose. Ce que ce
/// type obtient est un booléen — « le porteur a été reconnu » — et un booléen
/// n'est pas une preuve : un client modifié en renverrait un aussi.
///
/// **Le serveur ne doit donc jamais croire ce type.** Ce qui vaut preuve auprès
/// de l'annuaire est une SIGNATURE produite par une clé qui vit elle-même dans
/// la Secure Enclave, créée avec un contrôle d'accès qui exige la biométrie pour
/// s'en servir (`kSecAccessControlBiometryCurrentSet`). La confirmation devient
/// alors une condition d'usage de la clé, vérifiée par le matériel, plutôt qu'un
/// résultat que le code transporte.
///
/// Ce fichier ne fait que la PREMIÈRE moitié : constater ce dont l'appareil est
/// capable. La seconde — la clé, son contrôle d'accès, la signature — reste à
/// écrire, et sa spécification est dans `docs/protocole.md` du dépôt serveur.
struct IdentiteLocale {
    /// Ce que l'appareil sait faire.
    enum Etat: CustomStringConvertible {
        /// Reconnaissance faciale disponible et enrôlée.
        case visage
        /// Empreinte digitale disponible et enrôlée.
        case empreinte
        /// Le matériel existe, mais rien n'y est enrôlé — l'utilisateur peut le
        /// corriger dans les réglages, donc ce n'est PAS un refus définitif.
        case rienEnrole
        /// Aucune biométrie sur cet appareil. **C'est le cas qui exclut
        /// l'application**, et il doit se dire clairement plutôt que d'échouer
        /// plus tard.
        case indisponible(raison: String)

        var description: String {
            switch self {
            case .visage: "Identité confirmable par reconnaissance faciale."
            case .empreinte: "Identité confirmable par empreinte digitale."
            case .rienEnrole: "Aucune biométrie enrôlée sur cet appareil."
            case let .indisponible(raison): "Biométrie indisponible : \(raison)"
            }
        }
    }

    /// Interroge l'appareil.
    ///
    /// **Un contexte NEUF à chaque appel, et ce n'est pas du zèle.** Un
    /// `LAContext` mémorise le résultat d'une évaluation précédente ; le
    /// réutiliser rendrait une réponse qui décrit le passé, alors que
    /// l'utilisateur a pu enrôler un doigt ou retirer un visage entre-temps.
    func etat() -> Etat {
        let contexte = LAContext()
        var erreur: NSError?

        guard contexte.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &erreur
        ) else {
            // `LAError.biometryNotEnrolled` se distingue du reste : le matériel
            // est là, et l'utilisateur peut y remédier lui-même.
            if let erreur, LAError.Code(rawValue: erreur.code) == .biometryNotEnrolled {
                return .rienEnrole
            }
            return .indisponible(
                raison: erreur?.localizedDescription ?? "cause non rapportée"
            )
        }

        switch contexte.biometryType {
        case .faceID: return .visage
        case .touchID: return .empreinte
        default:
            // `canEvaluatePolicy` a dit oui, mais le type n'est ni l'un ni
            // l'autre — un `opticID` sur Vision Pro, ou un cas qu'Apple
            // ajoutera. On ne l'affirme pas comme un refus.
            return .indisponible(raison: "type de biométrie non pris en charge")
        }
    }
}
