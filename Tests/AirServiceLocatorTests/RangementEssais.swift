import Foundation
import Testing
@testable import AirServiceLocator

/// Ranger une machine : seuls les domaines où l'on tient `rattacher` sont
/// proposés — jamais le domaine racine, pas même à son propriétaire —, et un
/// refus se dit en clair.
struct RangementEssais {
    /// Les deux domaines du compte, tels que `GET /v1/domaines` les rend :
    /// le sien, et le domaine racine qu'il administre.
    private static let domaines = ReponsesDomaines.domaines(Data("""
    [{"domaine":"d-4M7FFS0Q7WMYSYF1EZ032XDEVD","proprietaire":"u-5884A5EE7THEKHBQ3BT0VPGJKN","alias":"air-dictator-house","heberge_par":"n-7MSV5RPCXBZH25PQM4ZPE5X87P","droits":["administrer","rattacher","voir","localiser"]},
     {"domaine":"d-7X3ZTW7HP1ZCHZK3D91JR9J35W","proprietaire":"u-5884A5EE7THEKHBQ3BT0VPGJKN","alias":"R","heberge_par":"racines","droits":["administrer"]}]
    """.utf8))

    @Test func leDomaineRacineNEstPasPropose() {
        #expect(Self.domaines.count == 2)
        #expect(Self.domaines.filter(\.recoitDesMachines).map(\.titre) == ["air-dictator-house"])
    }

    /// Même propriétaire : sans `rattacher`, pas de rangement.
    @Test func etrePropriétaireNeSuffitPas() {
        let racine = Self.domaines[1]
        #expect(racine.proprietaire == Self.domaines[0].proprietaire)
        #expect(!racine.recoitDesMachines)
    }

    @Test func unRefusDeRangementSeDitEnClair() {
        #expect(AnnuaireReel.erreurDeRangement(204, versUnDomaine: true) == nil)
        #expect(AnnuaireReel.erreurDeRangement(404, versUnDomaine: true) == .rangementRefuse)
        #expect(AnnuaireReel.erreurDeRangement(403, versUnDomaine: true) == .rattachementInterdit)
        #expect(ErreurAnnuaire.rangementRefuse.message == "Ce domaine ne peut pas recevoir cette machine.")
        // Retirer d'un domaine (DELETE) : un 404 reste un « introuvable ».
        #expect(AnnuaireReel.erreurDeRangement(404, versUnDomaine: false) != .rangementRefuse)
    }

    /// `"sorte":"racine"` (annuaire ≥ 0.39.0) marque le domaine racine ;
    /// absent, inconnu ou d'un autre type : un domaine ordinaire.
    @Test func leDomaineRacineSeReconnaitASaSorte() {
        let lus = ReponsesDomaines.domaines(Data("""
        [{"domaine":"d-7X3ZTW7HP1ZCHZK3D91JR9J35W","proprietaire":"u-5884A5EE7THEKHBQ3BT0VPGJKN","alias":"R","heberge_par":"racines","droits":["administrer","rattacher","voir","localiser"],"sorte":"racine"},
         {"domaine":"d-4M7FFS0Q7WMYSYF1EZ032XDEVD","proprietaire":"u-5884A5EE7THEKHBQ3BT0VPGJKN","heberge_par":"racines","droits":["rattacher"],"sorte":"autre"},
         {"domaine":"d-4M7FFS0Q7WMYSYF1EZ032XDEVE","proprietaire":"u-5884A5EE7THEKHBQ3BT0VPGJKN","heberge_par":"racines","droits":["rattacher"],"sorte":true}]
        """.utf8))
        #expect(lus.map(\.estRacine) == [true, false, false])
        // Avec `rattacher` (0.39.0), R reçoit des machines : c'est `rattacher`
        // qui gouverne le rangement, la sorte ne gouverne que confier et supprimer.
        #expect(lus[0].recoitDesMachines)
        #expect(Self.domaines.allSatisfy { !$0.estRacine })
    }
}
