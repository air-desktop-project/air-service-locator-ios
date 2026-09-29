import Foundation
import Testing
@testable import AirServiceLocator

/// L'état d'un annuaire local (décisions 70 et 86) : `paire` et `voie` lus
/// avec tolérance, et la règle vivant / parti / pas de nouvelles.
struct EtatAnnuaireLocalEssais {
    private static let speedy = "n-7MSV5RPCXBZH25PQM4ZPE5X87P"
    private static let helium = "n-4EQRD1VWYQQB1Y9C3T49Z8F8Z9"

    private static func liste(_ champsSpeedy: String, _ champsHelium: String) -> [AnnuaireLocal] {
        ReponsesDomaines.annuaires(Data("""
        [{"membre":"\(speedy)","annuaire":"\(speedy)","etat":"acceptée","adresse":"[2a01:cb19:d27:2f00:3ac9:86ff:fe47:9d54]:6630"\(champsSpeedy)},
         {"membre":"\(helium)","annuaire":"\(speedy)","etat":"acceptée","adresse":"[2a01:cb19:d27:2f00:dea6:32ff:fe55:730]:6630"\(champsHelium)}]
        """.utf8))
    }

    @Test func lesDeuxChampsSeLisent() {
        let membres = Self.liste(#","paire":"reglee","voie":"ouverte""#, #","paire":"sans-peer","voie":"tombee""#)
        #expect(membres.map(\.paire) == [.reglee, .sansPeer])
        #expect(membres.map(\.voie) == [.ouverte, .tombee])
        #expect(TextesDomaines.voie(membres[1].voie) == "Voie tombée")
    }

    /// Un champ absent, une valeur inconnue, vide, `null`, un booléen ou un
    /// nombre à la place d'une chaîne : la liste se lit, et l'écran dit « — ».
    @Test func unChampAbsentOuInconnuSeLitSansCasser() {
        let membres = Self.liste(#","paire":"autre-chose","voie":"entrouverte""#, #","paire":true,"voie":1"#)
        #expect(membres.count == 2)
        #expect(membres[0].paire == .inconnue("autre-chose"))
        #expect(membres[0].voie == .inconnue("entrouverte"))
        #expect(membres[1].paire == nil)
        #expect(membres[1].voie == nil)
        #expect(TextesDomaines.voie(membres[0].voie) == "—")
        #expect(TextesDomaines.voie(nil) == "—")
        #expect(TextesDomaines.paireFautive(membres[0]) == nil)
        let vides = Self.liste(#","paire":"","voie":"""#, #","paire":null,"voie":null"#)
        #expect(vides.map(\.paire) == [nil, nil])
        #expect(vides.map(\.voie) == [nil, nil])
    }

    @Test func vivantSiUnMembreALaVoieOuverte() {
        #expect(EtatDeLAnnuaire(membres: Self.liste(#","voie":"tombee""#, #","voie":"ouverte""#)) == .vivant)
        #expect(EtatDeLAnnuaire(membres: Self.liste(#","voie":"ouverte""#, "")) == .vivant)
    }

    @Test func partiSiAucunNestOuvertEtUnEstTombe() {
        #expect(EtatDeLAnnuaire(membres: Self.liste(#","voie":"tombee""#, "")) == .parti)
        #expect(EtatDeLAnnuaire(membres: Self.liste(#","voie":"tombee""#, #","voie":"tombee""#)) == .parti)
    }

    /// Aucune voie connue — la racine vient de redémarrer — : on n'affirme
    /// rien. Une valeur inconnue ne compte pas non plus.
    @Test func pasDeNouvellesSansVoieConnue() {
        #expect(EtatDeLAnnuaire(membres: Self.liste("", "")) == .pasDeNouvelles)
        #expect(EtatDeLAnnuaire(membres: Self.liste(#","voie":"entrouverte""#, "")) == .pasDeNouvelles)
        #expect(EtatDeLAnnuaire(membres: []) == .pasDeNouvelles)
    }

    /// Seuls comptent les membres acceptés : une voie ouverte sur une
    /// inscription en attente ne rend pas l'annuaire vivant.
    @Test func seulsLesMembresAcceptesComptent() {
        let membres = ReponsesDomaines.annuaires(Data("""
        [{"membre":"\(Self.helium)","annuaire":"\(Self.speedy)","etat":"en attente","adresse":"a:1","voie":"ouverte"}]
        """.utf8))
        #expect(EtatDeLAnnuaire(membres: membres) == .pasDeNouvelles)
    }

    /// La phrase nomme le membre par son rôle et son identité abrégée, pas
    /// par une adresse IPv6.
    @Test func unePaireMalRegleeSeDitAvecQuoiFaire() throws {
        let membres = Self.liste(#","paire":"sans-peer""#, #","paire":"peer-inconnu""#)
        let titulaire = try Identifiant.analyser(Self.speedy, genre: .annuaire).abrege
        let second = try Identifiant.analyser(Self.helium, genre: .annuaire).abrege
        #expect(TextesDomaines.paireFautive(membres[0]) == "Le titulaire (\(titulaire)) tourne sans --peer : la paire ne se réplique pas ; réglez --peer et --peer-key sur cette machine.")
        #expect(TextesDomaines.paireFautive(membres[1]) == "Le second membre (\(second)) désigne par --peer un annuaire qui n'est pas l'autre membre de la paire ; corrigez --peer et --peer-key sur cette machine.")
        for autre in [#","paire":"reglee""#, #","paire":"seul""#, ""] {
            #expect(TextesDomaines.paireFautive(Self.liste(autre, "")[0]) == nil)
        }
    }
}
