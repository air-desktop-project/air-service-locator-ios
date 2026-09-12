import Foundation

extension AnnuaireSimule {
    /// Un annuaire déjà peuplé de ce que les maquettes montraient : un compte,
    /// cinq machines, des services dans chaque état, des autorisations dans les
    /// deux sens. **Ce sont des données inventées**, et l'écran d'accueil reste
    /// le premier écran : le compte n'est ouvert que quand l'utilisateur le fait.
    static func deDemonstration() async -> AnnuaireSimule {
        let annuaire = AnnuaireSimule()
        await annuaire.peuplerDemonstration()
        return annuaire
    }

    /// Ouvre le compte ET pose les données. Appelé par le bouton de l'accueil
    /// en mode démonstration, pour que la suite ait quelque chose à montrer.
    func ouvrirCompteDeDemonstration(avec signataire: any Signataire) async throws -> Compte {
        let compte = try await ouvrirCompte(avec: signataire)
        await peuplerDemonstration()
        return compte
    }

    private func peuplerDemonstration() async {
        guard let compte = try? await compte(), (try? await machines())?.isEmpty ?? false else { return }
        let maintenant = Date()
        func il(ya secondes: TimeInterval) -> Date { maintenant.addingTimeInterval(-secondes) }
        func id(_ genre: Genre, _ graine: UInt8) -> Identifiant {
            Identifiant(genre: genre, entropie: (0..<16).map { UInt8(truncatingIfNeeded: Int($0) * 37 + Int(graine) * 11 + 5) })
        }
        func tcp(_ port: UInt16) -> PointEcoute { PointEcoute(protocole: .tcp, port: port) }
        func udp(_ port: UInt16) -> PointEcoute { PointEcoute(protocole: .udp, port: port) }

        let vero = id(.utilisateur, 1), marc = id(.utilisateur, 2), collegue = id(.utilisateur, 3), test = id(.utilisateur, 4)
        inscrireAutreCompte(vero, alias: "vero")
        inscrireAutreCompte(marc, alias: "marc")
        inscrireAutreCompte(collegue, alias: nil)
        inscrireAutreCompte(test, alias: nil)

        let grenier = Machine(
            id: id(.machine, 10), nom: "grenier", capacites: [.annonce], cle: .enrolee(le: il(ya: 7 * 86_400)),
            services: [
                Service(
                    id: id(.service, 11), nom: "depot-de-messages", points: [tcp(49_152), udp(49_152)],
                    etat: .annonce(depuis: il(ya: 3_600)),
                    joignabilite: [tcp(49_152): .joignable(depuis: il(ya: 120), candidat: "[2001:db8::1c2d]:49152"), udp(49_152): .nonSonde],
                    candidats: [
                        Candidat(protocole: .tcp, adresse: "2001:db8::1c2d", port: 49_152, origine: .reflexif),
                        Candidat(protocole: .tcp, adresse: "192.168.1.20", port: 49_152, origine: .annonce),
                    ]
                ),
                Service(
                    id: id(.service, 12), nom: "sauvegarde", points: [tcp(8_443)],
                    etat: .annonce(depuis: il(ya: 900)),
                    joignabilite: [tcp(8_443): .injoignable(depuis: il(ya: 300))],
                    candidats: [Candidat(protocole: .tcp, adresse: "203.0.113.4", port: 8_443, origine: .reflexif)]
                ),
                Service(
                    id: id(.service, 13), nom: "metriques", points: [udp(9_100)],
                    etat: .annonce(depuis: il(ya: 3_600)), joignabilite: [udp(9_100): .nonSonde],
                    candidats: [Candidat(protocole: .udp, adresse: "203.0.113.4", port: 9_100, origine: .reflexif)]
                ),
            ]
        )
        let bureau = Machine(
            id: id(.machine, 20), nom: "bureau", capacites: [.annonce, .lecture], cle: .enrolee(le: il(ya: 5 * 86_400)),
            services: [Service(
                id: id(.service, 21), nom: "depot-de-messages", points: [tcp(49_160)],
                etat: .annonce(depuis: il(ya: 60)),
                joignabilite: [tcp(49_160): .enCours],
                candidats: [Candidat(protocole: .tcp, adresse: "2001:db8::77", port: 49_160, origine: .reflexif)]
            )]
        )
        let portable = Machine(id: id(.machine, 30), nom: "portable-vero", capacites: [.lecture], cle: .enrolee(le: il(ya: 2 * 86_400)), services: [])
        var nas = Machine(
            id: id(.machine, 40), nom: "nas", capacites: [.annonce], cle: .enrolee(le: il(ya: 30 * 86_400)),
            services: [
                Service(
                    id: id(.service, 41), nom: "partage", points: [tcp(445)],
                    etat: .annonce(depuis: il(ya: 12)),
                    joignabilite: [tcp(445): .joignable(depuis: il(ya: 10), candidat: "[2001:db8::40]:445")],
                    candidats: [Candidat(protocole: .tcp, adresse: "2001:db8::40", port: 445, origine: .reflexif)]
                ),
                Service(
                    id: id(.service, 42), nom: "horloge", points: [udp(123)],
                    etat: .parti(volontaire: true, le: il(ya: 86_400 + 3_000)), joignabilite: [:], candidats: []
                ),
            ]
        )
        nas.services[0].oscille = true
        let cave = Machine(
            id: id(.machine, 50), nom: "serveur-cave", capacites: [.annonce],
            cle: .attendue(code: CodeEnrolement(entropie: [0x4A, 0x6E, 0x9D, 0x1C, 0x83, 0x2F, 0xD0, 0x00], emisLe: il(ya: 240))),
            services: []
        )
        for machine in [cave, grenier, bureau, portable, nas] { poser(machine) }

        poser(Appareil(id: id(.appareil, 60), nom: "Fairphone 5", biometrie: .empreinte, enroleLe: il(ya: 5 * 86_400), revoqueLe: nil, estCeluiCi: false))
        poser(Appareil(id: id(.appareil, 61), nom: "iPad", biometrie: .empreinte, enroleLe: il(ya: 40 * 86_400), revoqueLe: il(ya: 3 * 86_400), estCeluiCi: false))

        let moi = compte.identifiant
        recevoir(Autorisation(id: id(.autorisation, 70), accordeePar: moi, accordeeA: vero, portee: .tout, etiquette: "maison", accordeeLe: il(ya: 20 * 86_400), revoqueeLe: nil))
        recevoir(Autorisation(id: id(.autorisation, 71), accordeePar: moi, accordeeA: collegue, portee: .machine(grenier.id), etiquette: "collègue", accordeeLe: il(ya: 10 * 86_400), revoqueeLe: nil))
        recevoir(Autorisation(id: id(.autorisation, 72), accordeePar: moi, accordeeA: test, portee: .service(id(.service, 12)), etiquette: "test", accordeeLe: il(ya: 15 * 86_400), revoqueeLe: il(ya: 9 * 86_400)))
        recevoir(Autorisation(id: id(.autorisation, 73), accordeePar: marc, accordeeA: moi, portee: .tout, etiquette: "", accordeeLe: il(ya: 2 * 86_400), revoqueeLe: nil))
    }
}
