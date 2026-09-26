import Observation
import OSLog
import SwiftUI

/// Ce que tous les écrans partagent : l'annuaire à qui parler, et le compte
/// de cet appareil.
@MainActor
@Observable
final class Session {
    /// À qui parler. **Change** quand l'utilisateur choisit une autre racine
    /// (``choisirAnnuaire(_:)``) : les écrans le relisent à chaque appel.
    private(set) var annuaire: any Annuaire
    private(set) var compte: Compte?
    let identite = IdentiteLocale()
    private static let journal = Logger(subsystem: "org.airdesktop.servicelocator", category: "session")

    /// Comment on ouvre un compte — séparé de l'annuaire parce qu'en
    /// démonstration, l'ouverture peuple aussi l'annuaire.
    private var ouverture: @Sendable (any Signataire, CodeInvitation?) async throws -> Compte
    /// D'où vient la clé : la Secure Enclave sur un appareil, une clé
    /// logicielle dans un essai.
    private let signataire: @Sendable () throws -> any Signataire

    /// Les accès reçus déjà montrés par cet appareil (``Nouveautes``).
    let carnetNouveautes: CarnetNouveautes

    init(
        annuaire: any Annuaire,
        signataire: @escaping @Sendable () throws -> any Signataire = { try CleAppareil.ouOuvrir() },
        carnetNouveautes: CarnetNouveautes = CarnetNouveautes(),
        ouverture: @escaping @Sendable (any Signataire, CodeInvitation?) async throws -> Compte
    ) {
        self.annuaire = annuaire
        self.signataire = signataire
        self.carnetNouveautes = carnetNouveautes
        self.ouverture = ouverture
    }

    // MARK: - La racine

    /// Les annuaires entre lesquels choisir (``ChoixDAnnuaire``) — vide sur
    /// le banc ; un seul, et il n'y a rien à choisir.
    private(set) var annuaires: [AnnuaireReel.Reglages] = []
    /// Celui auquel on parle, parmi ``annuaires``.
    private(set) var annuaireChoisi: AnnuaireReel.Reglages?
    private var preference = PreferenceDAnnuaire()
    /// Ce qui fabrique l'annuaire d'une racine — le transport réel dans
    /// l'application, un banc dans les essais.
    private var fabrique: (@Sendable (AnnuaireReel.Reglages) -> any Annuaire)?

    /// La session d'une application qui parle à un vrai annuaire : la
    /// racine retenue par ``PreferenceDAnnuaire``, ou la première.
    static func reelle(
        annuaires: [AnnuaireReel.Reglages],
        preference: PreferenceDAnnuaire = PreferenceDAnnuaire(),
        fabrique: @escaping @Sendable (AnnuaireReel.Reglages) -> any Annuaire = { AnnuaireReel(reglages: $0) { try CleAppareil.ouOuvrir() } },
        signataire: @escaping @Sendable () throws -> any Signataire = { try CleAppareil.ouOuvrir() },
        carnetNouveautes: CarnetNouveautes = CarnetNouveautes()
    ) -> Session? {
        guard let choisi = preference.choisi(parmi: annuaires) else { return nil }
        let annuaire = fabrique(choisi)
        let session = Session(annuaire: annuaire, signataire: signataire, carnetNouveautes: carnetNouveautes) { signataire, invitation in
            try await annuaire.ouvrirCompte(avec: signataire, invitation: invitation)
        }
        session.annuaires = annuaires
        session.annuaireChoisi = choisi
        session.preference = preference
        session.fabrique = fabrique
        return session
    }

    /// Passe à une autre racine.
    ///
    /// **L'ancienne est fermée d'abord** — son écoute des nouvelles arrêtée,
    /// sa connexion libérée —, puis la nouvelle est fabriquée, **sans se
    /// connecter** : c'est la relecture qui suit, lancée par l'écran, qui
    /// reprouve la clé, et c'est un geste — Touch ID, Face ID. Jamais de
    /// reconnexion silencieuse. Le compte, lui, ne bouge pas : il est le même
    /// sur toutes les racines, et le carnet local reste.
    func choisirAnnuaire(_ reglages: AnnuaireReel.Reglages) async {
        guard reglages != annuaireChoisi, let fabrique else { return }
        await annuaire.fermer()
        let nouvel = fabrique(reglages)
        annuaire = nouvel
        ouverture = { signataire, invitation in try await nouvel.ouvrirCompte(avec: signataire, invitation: invitation) }
        annuaireChoisi = reglages
        preference.retenir(reglages)
        Self.journal.notice("annuaire choisi : \(reglages.adresse, privacy: .public)")
    }

    /// Combien d'accès reçus n'ont pas encore été montrés — la pastille de
    /// l'onglet « Accès » sur iPhone, de la ligne « Accès » sur le Mac. Tenu
    /// par ``constater(_:)``, remis à zéro par ``montrees(_:)``.
    private(set) var nouveautes = 0

    /// Ce que ces autorisations ont de neuf pour cet appareil — et la
    /// pastille qui le dit. La première lecture d'un compte sur cet appareil
    /// pose la référence tout de suite, sans rien signaler.
    @discardableResult
    func constater(_ autorisations: [Autorisation]) -> Nouveautes.Lecture? {
        guard let moi = compte?.identifiant else { return nil }
        let dejaVues = carnetNouveautes.dejaVues(moi)
        let lecture = Nouveautes.lire(autorisations, moi: moi, dejaVues: dejaVues)
        if dejaVues == nil { carnetNouveautes.retenirVues(moi, lecture.aRetenir) }
        nouveautes = lecture.nouvelles.count
        return lecture
    }

    /// L'écran des accès a montré cette lecture : ce qu'elle portait de neuf
    /// ne l'est plus.
    func montrees(_ lecture: Nouveautes.Lecture) {
        guard let moi = compte?.identifiant else { return }
        carnetNouveautes.retenirVues(moi, lecture.aRetenir)
        nouveautes = 0
    }

    /// La relecture avec différence (`protocole.md` §2.2) :
    /// `GET /v1/autorisations`, puis ``constater(_:)``. C'est elle, et non la
    /// notification, qui dit ce qui a changé.
    ///
    /// `sansGeste` : seulement si la connexion tient encore. Un retour au
    /// premier plan ne demande pas Face ID pour mettre une pastille à jour ;
    /// la prochaine ouverture, qui en demande un de toute façon, relira.
    /// Une relecture qui échoue ne dit rien : ce n'est qu'une pastille.
    func relire(sansGeste: Bool = false) async {
        guard compte != nil else { return }
        if sansGeste, !(await annuaire.connexionTenue()) { return }
        guard let autorisations = try? await annuaire.autorisations() else { return }
        constater(autorisations)
    }

    /// Ce que la dernière relecture n'a pas pu faire, dit à l'écran : hors
    /// ligne, geste annulé. Un compte connu reste affiché ; seule une preuve
    /// refusée par l'annuaire le retire.
    private(set) var erreurDeRelecture: String?
    /// Vrai tant que la première relecture n'a pas conclu : l'écran ne doit
    /// dire ni « aucun compte » ni « compte » avant de savoir.
    private(set) var premiereRelectureEnCours = true

    /// Relit le compte que l'annuaire connaît pour cet appareil.
    func rafraichirCompte() async {
        defer { premiereRelectureEnCours = false }
        do {
            compte = try await annuaire.compte()
            erreurDeRelecture = nil
            if compte != nil { await seDecrire() }
        } catch ErreurAnnuaire.preuveInvalide {
            compte = nil
            erreurDeRelecture = ErreurAnnuaire.preuveInvalide.message
        } catch {
            // Le compte qu'on connaît reste ; l'annuaire n'a juste pas répondu.
            erreurDeRelecture = error.messageAnnuaire
        }
    }

    /// Ouvre le compte : la clé de l'appareil prouve qu'elle est détenue, sur
    /// le défi de l'annuaire et la liaison du canal.
    ///
    /// **C'est là que la biométrie est demandée**, par la Secure Enclave, au
    /// moment de signer — et nulle part avant. Sans confirmation, la clé ne
    /// signe pas, et rien ne part.
    /// ``invitation`` n'est attendue que d'une racine en posture
    /// ``PostureAnnuaire/invitation`` ; ailleurs, `nil`.
    func ouvrirCompte(invitation: CodeInvitation? = nil) async throws {
        compte = try await ouverture(try signataire(), invitation)
        await seDecrire()
    }

    /// Dit à l'annuaire ce que cet appareil est — plate-forme et modèle,
    /// jamais le nom que l'utilisateur lui a donné (`docs/modele.md` §2.2).
    /// Juste après chaque preuve : c'est le moment où l'appareil parle de
    /// lui sur sa propre connexion.
    ///
    /// **Une étiquette qui n'a pas pu se poser n'est pas une panne.** Un
    /// annuaire qui ne sert pas encore ce verbe rend `404` ; le compte, lui,
    /// est là. On ne le dit pas à l'écran, et l'annuaire réel n'en garde pas
    /// trace comme posée — elle repartira à la prochaine preuve.
    private func seDecrire() async {
        do {
            try await annuaire.decrire(Appareil.Description.deCetAppareil())
        } catch {
            Self.journal.notice("la description de cet appareil n'a pas été posée : \(error.messageAnnuaire, privacy: .public)")
        }
    }

    /// La clé publique de cet appareil — ce que le nouveau téléphone montre à
    /// l'ancien. La lire ne demande aucun geste : seule la signature en
    /// demande un.
    func clePublique() throws -> [UInt8] {
        try signataire().clePublique
    }

    /// Rejoint un compte, depuis ce téléphone-ci, avec l'invitation que
    /// l'autre a rendue. Le geste est demandé au moment de prouver la clé.
    func rejoindre(compte: Identifiant, appareil: Identifiant) async throws {
        self.compte = try await annuaire.rejoindre(compte: compte, appareil: appareil, avec: try signataire())
        await seDecrire()
    }

    func definirAlias(_ alias: String?) async throws {
        try await annuaire.definirAlias(alias)
        await rafraichirCompte()
    }

    /// Efface le compte — le dernier acte de la clé de cet appareil
    /// (`modele.md` §2.1). L'annuaire d'abord ; puis, ici, la clé est
    /// détruite (elle est révoquée là-bas, la garder ne prouverait plus
    /// rien), le carnet est vidé, et `compte` revient à `nil` : l'écran
    /// d'accueil reprend, comme au premier lancement. `apresLAnnuaire` est
    /// ce que la plate-forme a de plus à oublier — sur le Mac, l'identité de
    /// machine, dont la clé est révoquée avec le compte.
    func effacerCompte(apresLAnnuaire: @MainActor () throws -> Void = {}) async throws {
        try await annuaire.effacerCompte()
        do { try CleAppareil.effacer() } catch { Self.journal.error("la clé n'a pas pu être détruite : \(error.localizedDescription, privacy: .public)") }
        do { try apresLAnnuaire() } catch { Self.journal.error("ce qui suit l'effacement n'a pas pu se faire : \(error.localizedDescription, privacy: .public)") }
        compte = nil
        erreurDeRelecture = nil
        nouveautes = 0
    }
}
