import Foundation

/// La relecture avec différence (`protocole.md` §2.2, « Le repli, partout ») :
/// ce qui a été accordé à ce compte depuis la dernière fois qu'on l'a montré.
///
/// # POURQUOI CE N'EST PAS L'ANNUAIRE QUI LE DIT
///
/// L'annuaire ne tient ni compteur ni date de lecture, et c'est voulu : une
/// « dernière lecture » rangée chez lui serait une donnée de plus sur ce que
/// fait l'utilisateur. C'est l'appareil qui garde l'ensemble des `g-…` reçues
/// qu'il a déjà montrées ; la différence avec `GET /v1/autorisations` est ce
/// qu'il y a de nouveau. C'est ce qui fait marcher l'application SANS
/// notification — et sur iPhone il n'y en a pas : l'ouverture fait le
/// travail. Sur le Mac, la notification ne dit que qu'il y a quelque chose à
/// relire ; c'est encore cette différence qui dit quoi.
///
/// # LA PREMIÈRE LECTURE POSE LA RÉFÉRENCE, ET NE SIGNALE RIEN
///
/// Un ensemble jamais tenu (`nil`) n'est pas un ensemble vide : c'est une
/// application qui vient d'être mise à jour, ou un appareil qui vient de
/// rejoindre le compte. Tout ce qu'il lit alors, il le signalerait comme neuf
/// — des accès de six mois, sous « nouveau ». La première lecture ne signale
/// donc rien : elle dit ce qui est, et c'est à partir d'elle qu'on compare.
///
/// Le modèle est celui d'Android (`Nouveautes.kt`), règle pour règle : deux
/// plates-formes qui compteraient différemment afficheraient deux pastilles
/// différentes pour le même compte.
enum Nouveautes {
    struct Lecture: Equatable, Sendable {
        /// À signaler : reçues, vivantes, jamais montrées.
        let nouvelles: [Autorisation]
        /// L'ensemble à garder une fois qu'elles ont été montrées.
        let aRetenir: Set<Identifiant>
    }

    /// - Parameter dejaVues: les `g-…` reçues déjà montrées ; `nil` si cet
    ///   appareil n'en a jamais tenu la liste.
    static func lire(_ autorisations: [Autorisation], moi: Identifiant, dejaVues: Set<Identifiant>?) -> Lecture {
        let recues = autorisations.filter { $0.accordeeA == moi && $0.accordeePar != moi }
        // Un accès qu'on m'a retiré avant que je l'aie vu n'est pas une
        // nouvelle à annoncer.
        let nouvelles = dejaVues.map { vues in recues.filter { !$0.estRevoquee && !vues.contains($0.id) } } ?? []
        // Toutes les reçues, révoquées comprises : un identifiant ne resert
        // jamais, et une révoquée ne doit pas revenir comme neuve. Ce que la
        // liste ne rend plus n'a pas à rester : il ne reviendra pas.
        return Lecture(nouvelles: nouvelles, aRetenir: Set(recues.map(\.id)))
    }
}

/// Les accès déjà montrés, retenus par cet appareil — et rien de ce que les
/// nouvelles disent, puisqu'elles ne disent rien.
///
/// **Hors du `Carnet` de l'annuaire réel** : le banc en mémoire en a besoin
/// aussi, la relecture avec différence marchant sans annuaire.
///
/// **Rangés sous le compte.** Un appareil qui efface son compte et en ouvre
/// un autre, ou qui en rejoint un, ne sait rien du nouveau par ce qu'il a vu
/// de l'ancien : un autre compte, c'est une première lecture.
struct CarnetNouveautes: @unchecked Sendable {
    // `UserDefaults` est sûr entre fils par contrat de Foundation ; le
    // compilateur ne le sait pas. Un essai passe sa propre suite.
    private let defauts: UserDefaults

    init(defauts: UserDefaults = .standard) {
        self.defauts = defauts
    }

    func dejaVues(_ compte: Identifiant) -> Set<Identifiant>? {
        guard defauts.string(forKey: "nouveautes.compte") == compte.texte else { return nil }
        let textes = defauts.stringArray(forKey: "nouveautes.vues") ?? []
        return Set(textes.compactMap { try? Identifiant.analyser($0, genre: .autorisation) })
    }

    func retenirVues(_ compte: Identifiant, _ vues: Set<Identifiant>) {
        defauts.set(compte.texte, forKey: "nouveautes.compte")
        defauts.set(vues.map(\.texte).sorted(), forKey: "nouveautes.vues")
    }
}
