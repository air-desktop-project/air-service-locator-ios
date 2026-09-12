import SwiftUI

/// Un service : ce que l'annuaire en affirme, point d'écoute par point
/// d'écoute, et ce qu'il a répondu au daemon à son annonce.
///
/// L'écran ne résume pas : la liste l'a fait. Ici, chaque point porte son
/// verdict et sa date, chaque candidat son origine — parce que « joignable »
/// se lit avec « depuis où » et « quand », ou ne se lit pas.
struct ServiceVue: View {
    let machine: Machine
    let service: Service

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Pastille(couleur: service.couleur, taille: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.libelleEtat).font(.headline)
                        Text(service.detailEtat).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if case let .annonce(depuis) = service.etat {
                    LabeledContent("Annoncé", value: depuis.relatif)
                }
                if service.oscille {
                    Label("Deux daemons de ce nom se chassent l'un l'autre : chaque annonce remplace la précédente.", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote).foregroundStyle(Couleurs.attention)
                }
            }

            Section {
                ForEach(service.points, id: \.self) { point in
                    LignePoint(point: point, verdict: service.joignabilite[point])
                }
            } header: {
                Text("Points d'écoute")
            } footer: {
                Text("Le verdict est celui de l'annuaire, qui a lui-même essayé d'ouvrir une connexion vers ce port. Un point UDP ne se sonde pas : aucune poignée de main, aucun écho générique.")
            }

            if !service.candidats.isEmpty {
                Section {
                    ForEach(service.candidats, id: \.self) { candidat in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.adresse(candidat)).font(.system(.subheadline, design: .monospaced))
                            Text(candidat.origine == .reflexif ? "observé par l'annuaire sur la connexion d'annonce"
                                 : "annoncé par le daemon — vrai sur son réseau, souvent faux ailleurs")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Candidats")
                } footer: {
                    Text("Où l'on peut essayer de joindre ce service, IPv6 d'abord. C'est ce qu'une machine autorisée reçoit quand elle demande où le joindre.")
                }
            }

            if let diagnostic = service.diagnostic {
                Section {
                    if let vu = diagnostic.vuDepuis {
                        LabeledContent("Vu depuis") {
                            Text(vu).font(.system(.footnote, design: .monospaced))
                        }
                    }
                    if let nat = diagnostic.derriereNat {
                        LabeledContent("Derrière un NAT", value: Self.texte(nat))
                    }
                    if let keepalive = diagnostic.keepaliveSecondes, let inactivite = diagnostic.inactiviteSecondes {
                        LabeledContent("Bail", value: "keepalive \(keepalive) s, inactivité \(inactivite) s")
                    }
                } header: {
                    Text("Ce que l'annuaire a répondu au daemon")
                } footer: {
                    Text("Sous quelle adresse il l'a vu — rien d'autre ne le lui apprend — et s'il le croit derrière un NAT, en comparant ce qui est annoncé à ce qu'il observe. « Indéterminé » : le daemon n'a annoncé aucune adresse locale, il n'y avait rien à comparer.")
                }
            }

            Section("Service") {
                LigneIdentifiant(titre: "Identifiant public", identifiant: service.id, partageable: true)
                LabeledContent("Machine", value: machine.nom)
            }
        }
        .navigationTitle(service.nom)
        .navigationBarTitleDisplayMode(.large)
    }

    private static func adresse(_ candidat: Candidat) -> String {
        let hote = candidat.adresse.contains(":") ? "[\(candidat.adresse)]" : candidat.adresse
        return "\(candidat.protocole.rawValue) \(hote):\(candidat.port)"
    }

    private static func texte(_ nat: Diagnostic.Nat) -> String {
        switch nat {
        case .oui: "oui"
        case .non: "non"
        case .indetermine: "indéterminé"
        }
    }
}

private struct LignePoint: View {
    let point: PointEcoute
    let verdict: Joignabilite?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Pastille(couleur: verdict?.couleur ?? Couleurs.parti).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(point.texte).font(.system(.subheadline, design: .monospaced))
                if let verdict {
                    Text(verdict.libelle).font(.footnote.weight(.semibold))
                    Text(verdict.detail).font(.footnote).foregroundStyle(.secondary)
                    if case let .joignable(_, candidat) = verdict, !candidat.isEmpty {
                        Text("vers \(candidat)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Aucun verdict : le service est parti.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}
