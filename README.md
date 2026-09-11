# air-service-locator-ios

L'application iOS d'**air-service-locator** : ouvrir un compte, déclarer ses
machines, et voir quels daemons y écoutent — et sur quel port.

> ## État : les huit écrans, sur un annuaire simulé
>
> L'application compile (Xcode 26, Swift 6, concurrence stricte, avertissements
> en erreurs) et tourne sur le simulateur. Elle porte les huit écrans arrêtés
> avec les maquettes — accueil, machines, machine, déclaration, code
> d'enrôlement, accès, accorder, compte — et vingt-huit essais.
>
> **Elle ne parle à aucun serveur.** Les écrans s'adressent à l'interface
> `Annuaire` (`Sources/Coeur/Reseau/Annuaire.swift`), et c'est
> `AnnuaireSimule` qui répond : un banc en mémoire qui tient les refus de
> `docs/protocole.md` §2 — un appareil ne se révoque pas lui-même, un alias
> pris rend `409`, un objet absent et un objet d'un autre compte rendent le même
> `404`.
>
> **La clé de l'appareil est réelle** : P-256 dans la Secure Enclave, sous
> `biometryCurrentSet`. Ouvrir un compte est une vraie preuve de possession —
> le corps de `POST /v1/comptes` : clé SEC1 compressée, signature `r ‖ s` sur
> le défi de l'annuaire — que le banc vérifie comme le serveur le fera. Face ID
> est demandé au moment de signer, par l'enclave. Le transport — la pile QUIC
> d'`asl-client`, et la liaison de canal, qui vaut zéro d'ici là — reste à
> embarquer, et c'est la composition dans `AirServiceLocatorApp.swift` qui
> changera, pas les écrans.
>
> Le simulateur émule une enclave mais refuse d'y lier une clé à la
> biométrie : sur simulateur seulement, un `LAContext` fait le geste avant de
> signer (`CleAppareil.swift` le dit et le borne).
>
> Trois choses sont dites « pas encore possible » à l'écran plutôt que
> simulées : enrôler un second appareil, les expositions (`501` côté serveur),
> et l'attestation App Attest, qui exige un iPhone réel.

## La condition de déploiement

**Cette application ne s'installe que sur un appareil capable de confirmer
localement l'identité de son porteur** — Face ID ou Touch ID.

Ce que cela veut *réellement* dire mérite d'être écrit, parce que la version
courte induit en erreur :

- La confirmation a lieu **sur l'appareil**. iOS ne rend jamais un gabarit facial
  ni une empreinte — ces données vivent dans la Secure Enclave, et aucune API ne
  les expose.
- Ce que le code obtient est un **booléen**, et un booléen n'est pas une preuve :
  un client modifié en renverrait un aussi.
- Ce qui vaut preuve auprès de l'annuaire est une **signature** produite par une
  clé qui vit elle-même dans la Secure Enclave, créée avec un contrôle d'accès
  qui exige la biométrie pour s'en servir. La confirmation devient alors une
  condition d'usage de la clé, vérifiée par le matériel.

Le serveur ne voit donc jamais l'identité de personne ; il voit une signature
qu'un appareil enrôlé n'a pu produire qu'après une confirmation locale. Cette
distinction est écrite aux deux bouts — ici, et dans `crates/asl-auth` du dépôt
serveur.

## Construire

Le `.xcodeproj` **n'est pas versionné** : c'est une sortie, produite depuis
[`project.yml`](project.yml). Un projet Xcode est du XML généré que deux branches
ne savent pas fusionner.

```sh
brew install xcodegen
xcodegen generate
xcodebuild test -project AirServiceLocator.xcodeproj -scheme AirServiceLocator \
    -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

Sur le simulateur, enrôlez Face ID (*Features › Face ID › Enrolled*) avant
d'ouvrir un compte : l'accueil refuse un appareil sans biométrie, et c'est
voulu.

## L'arborescence

| Répertoire | Ce qu'il porte |
|---|---|
| `Sources/Coeur/Modele/` | Identifiant (base32 de Crockford, seize octets), code d'enrôlement, compte, appareil, machine, service, autorisation — la forme de `docs/modele.md`. |
| `Sources/Coeur/Reseau/` | L'interface `Annuaire`, ses erreurs, et `Simulation/` — le banc en mémoire et ses données de démonstration. |
| `Sources/Coeur/Identite/` | Ce que l'appareil sait confirmer, et le geste de confirmation. |
| `Sources/Ecrans/` | `Compte/`, `Machines/`, `Acces/`, et `Composants/` pour ce qu'ils partagent. |
| `Sources/Application/` | Le point d'entrée, la `Session`, les onglets. |
| `Tests/` | Essais Swift Testing : la grammaire des identifiants et des codes, les règles du banc. |

## Ce que ce dépôt ne contient pas, et où c'est

Le modèle et le protocole sont spécifiés **dans le dépôt serveur** — trois copies
vieilliraient, et deux d'entre elles en silence.

| Question | Où elle est traitée |
|---|---|
| Utilisateurs, machines, services, baux | `air-service-locator-server`, `docs/modele.md` |
| Ce que l'application envoie et reçoit | `air-service-locator-server`, `docs/protocole.md` §2 |
| Ce que le serveur constate d'une identité | `air-service-locator-server`, `crates/asl-auth` |

## Les trois dépôts

| Dépôt | Ce qu'il porte |
|---|---|
| `air-service-locator-server` | Le service, en Rust. Porte aussi les spécifications. |
| `air-service-locator-ios` | Ce dépôt. |
| `air-service-locator-android` | L'application Android (Kotlin). |

## Licence

MPL-2.0 — voir [LICENSE](LICENSE).
