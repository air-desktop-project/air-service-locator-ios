import SwiftUI

extension Service {
    /// La teinte d'un service dans une liste : le verdict de la sonde s'il y
    /// en a un, l'accent pour un service vivant sans verdict — ou sans
    /// détail (``sansDetail``) —, le gris d'un parti.
    var teinte: Color {
        switch etat {
        case .annonce:
            switch resume {
            case .joignable: Couleurs.joignable
            case .injoignable: Couleurs.attention
            default: Couleurs.accent
            }
        case .parti: Couleurs.parti
        }
    }
}

/// Les services d'une machine rangée dans un domaine, sous son nom : le
/// même sur l'iPhone et sur le Mac.
///
/// `nil` : on ne les lit pas — la machine d'un autre compte, dans un domaine
/// qui ne donne ni `voir` ni `localiser`. Un service vu par `voir` seul ne
/// montre ni points ni adresses : on ne nous les donne pas, et une case vide
/// dirait qu'il n'en a pas.
struct ServicesRangesVue: View {
    let services: [Service]?

    var body: some View {
        if let services {
            if services.isEmpty {
                Text(TextesDomaines.aucunService).font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(services) { service in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle().fill(service.teinte).frame(width: 7, height: 7)
                            Text(service.nom).font(.system(.caption, design: .monospaced))
                            Text(service.libelleEtat).font(.caption)
                            if !service.sansDetail, !service.points.isEmpty {
                                Text(service.pointsTexte).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            if !service.detailEtat.isEmpty {
                                Text(service.detailEtat).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}
