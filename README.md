# air-service-locator-ios

L'application iOS d'**air-service-locator** : ouvrir un compte, déclarer ses
machines, et voir quels daemons y écoutent — et sur quel port.

> ## État : onze écrans, sur le vrai annuaire
>
> L'application compile (Xcode 26, Swift 6, concurrence stricte, avertissements
> en erreurs) et tourne sur le simulateur. Elle porte les huit écrans arrêtés
> avec les maquettes — accueil, machines, machine, déclaration, code
> d'enrôlement, accès, accorder, compte —, trois écrans de plus — le détail
> d'un service, enrôler un second appareil, rejoindre un compte — et
> trente-deux essais.
>
> **Elle parle à un annuaire réel** quand on lui en donne un (voir
> « Construire ») : HTTP/3 sur QUIC, par la pile Rust d'`asl-client`
> embarquée en xcframework (`Sources/Coeur/Reseau/Reel/AnnuaireReel.swift`).
> La connexion est **tenue** : un geste biométrique par connexion, pas par
> requête. Sans annuaire configuré, c'est `AnnuaireSimule` qui répond : un
> banc en mémoire qui tient les refus de `docs/protocole.md` §2 — un appareil
> ne se révoque pas lui-même, un alias pris rend `409`, un objet absent et un
> objet d'un autre compte rendent le même `404`. Les écrans ne voient que
> l'interface `Annuaire` ; c'est `AirServiceLocatorApp.swift` qui choisit.
>
> **La clé de l'appareil est réelle** : P-256 dans la Secure Enclave, sous
> `biometryCurrentSet`. Ouvrir un compte est une vraie preuve de possession —
> le corps de `POST /v1/comptes` : clé SEC1 compressée, signature `r ‖ s` sur
> le défi de l'annuaire et la liaison du canal TLS — que le serveur vérifie.
> Face ID est demandé au moment de signer, par l'enclave, quand le transport
> le rappelle. Vérifié de bout en bout contre un serveur `asl-server` :
> compte, machine, enrôlement par `asl enrole`, annonce, service joignable.
>
> Le simulateur émule une enclave mais refuse d'y lier une clé à la
> biométrie : sur simulateur seulement, un `LAContext` fait le geste avant de
> signer (`CleAppareil.swift` le dit et le borne).
>
> **Le serveur fait foi** : la liste des machines, des appareils, des
> services avec leur nom et leur état viennent de lui (serveur `2cf05dc`).
> Ce qu'il ne range pas — les dates, le code d'enrôlement en cours, la trace
> d'une révocation — n'est connu que du téléphone qui a agi, et s'affiche
> quand il le sait, jamais inventé : « enrôlée » sans date vaut « enrôlée
> depuis un autre appareil ». Deux choses sont dites « pas encore possible »
> à l'écran plutôt que simulées : les expositions (`501` côté serveur), et
> l'attestation App Attest, qui exige un iPhone réel.
>
> **Un second appareil s'enrôle par un échange de QR codes** (`POST
> /v1/appareils`, `Sources/Coeur/Modele/Invitation.swift`) : le nouveau montre
> sa clé publique, l'ancien la lit à la caméra — ou la colle —, la poste, et
> montre en retour le compte et l'identifiant rendus ; le nouveau les lit et
> prouve sa clé sur sa propre connexion. Rien de secret ne passe. Vérifié
> entre le simulateur et un Fairphone 5, dans les deux sens.

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

### Parler à un vrai annuaire

Le transport est le xcframework produit par le dépôt client, attendu à
`../air-service-locator-client/target/mobile/AslClient.xcframework`
(`scripts/construire-mobile.sh` là-bas). Sans lui, l'édition de liens échoue :
c'est voulu, la simulation n'est pas un mode de secours silencieux.

L'annuaire se donne par deux fichiers **non versionnés** à la racine, copiés
dans le paquet à la construction :

```sh
echo '{"adresse": "192.168.1.102:6630", "nom": "speedy"}' > annuaire.json
cp /où/est/la/racine.pem annuaire-racine.pem
```

`nom` est le nom que porte le certificat du serveur ; `annuaire-racine.pem`,
la racine qui l'a signé. Sans ces deux fichiers, l'application tourne sur le
banc en mémoire, peuplé de démonstration.

## L'arborescence

| Répertoire | Ce qu'il porte |
|---|---|
| `Sources/Coeur/Modele/` | Identifiant (base32 de Crockford, seize octets), code d'enrôlement, compte, appareil, machine, service, autorisation — la forme de `docs/modele.md` — et l'invitation qu'échangent deux téléphones. |
| `Sources/Coeur/Reseau/` | L'interface `Annuaire`, ses erreurs ; `Reel/` — le transport QUIC d'`asl-client` et le carnet local ; `Simulation/` — le banc en mémoire et ses données de démonstration. |
| `Sources/Coeur/Identite/` | Ce que l'appareil sait confirmer, et le geste de confirmation. |
| `Sources/Ecrans/` | `Compte/`, `Machines/`, `Acces/`, et `Composants/` pour ce qu'ils partagent — dont le QR code et son lecteur (`CodeQR.swift`, AVFoundation, la seule caméra de l'application). |
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
