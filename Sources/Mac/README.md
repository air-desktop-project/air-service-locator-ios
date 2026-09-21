# L'application macOS

Deux surfaces, deux rôles.

**Le widget** sous l'icône de la barre de menus ne fait que *dire*, d'un coup
d'œil : le compte (l'identifiant en entier, à copier), les machines avec leur
puce d'état, leur nom, leur identifiant abrégé et leur état, la version de
l'annuaire et celle de l'application. Un seul bouton, « Ouvrir Service
Locator » ; un clic sur une machine ouvre la fenêtre dessus. Aucun geste n'y
vit : un popover se ferme dès qu'il perd le focus, et Touch ID le lui fait
perdre.

**La fenêtre** est une vraie fenêtre d'application (`FenetreVue`) : une barre
latérale — Compte, Machines (chacune sous son nom, avec sa puce), Appareils,
Accès, les versions en pied — et des pages où rien n'est tronqué :
identifiants complets, dates, verdicts de sonde, commande `asl` entière, et
tous les gestes (déclarer, enrôler, révoquer, émettre un code, renommer,
accorder un accès, alias). La barre d'outils porte « Ajouter une machine »,
« Faire de ce Mac une machine » et « Relire l'annuaire » ; le menu
« Machines » les reprend avec leurs raccourcis (⌘N, ⇧⌘M, ⌘R) ; Préférences
(⌘,) dit l'annuaire et les identités de ce Mac. Tant que la fenêtre est
ouverte, l'application est dans le Dock et ⌘-Tab ; fermée, elle se retire
dans la barre de menus (`LSUIElement`, et le va-et-vient de politique
d'activation dans `FenetreVue`).

Tout le cœur est celui de l'application iOS, compilé tel quel pour macOS :
`Sources/Coeur/` (modèle, `Annuaire`, clé dans la Secure Enclave, transport
QUIC) et `Session`. Ce dossier ajoute le widget, la fenêtre, ses pages, et
`Donnees` — ce que l'annuaire a rendu, tenu une fois pour les deux surfaces.
Les maquettes validées sont dans `../maquettes/macos/` (hors dépôt).

## Ce Mac est aussi une machine — si on le lui demande

Un Mac est un **appareil** (il administre le compte, sous Touch ID) et peut
être une **machine** (il héberge des daemons, avec une clé qui signe sans
personne). Deux rôles, deux clés, deux identifiants — `modele.md` §2.2 et
§2.3, et `MachineDeCeMac.swift` pour la raison. Le panneau propose « Faire de
ce Mac une machine » : Touch ID la déclare, et le code d'enrôlement est
consommé sur place par la voie des daemons d'`asl-client` — le même chemin
qu'`asl enroll` sur un Linux, sans terminal. Le **lien** entre les deux
identités (« la machine *bureau* est ce Mac ») vit dans le conteneur de
l'application et n'en sort pas : c'est ce Mac qui le sait, pas l'annuaire.

L'identité de machine est écrite **au format d'`asl`** (`identite`, deux
lignes, mode 0600) dans `Application Support/asl/` du conteneur, et
l'utilitaire la lit tel quel — le panneau montre la commande à copier :

```sh
asl --state "~/Library/Containers/org.airdesktop.servicelocator.mac/Data/Library/Application Support/asl" announce depot tcp:8080
```

Une seule clé de machine sur ce Mac, donc : celle que l'app a enrôlée.

## Ce qui est propre au Mac

- **La Secure Enclave du T2 ou de la puce Apple**, et Touch ID à chaque
  signature — la même `CleAppareil` que sur iPhone, sans branche spéciale.
  Elle exige une **application signée** (`project.yml` porte l'équipe) :
  non signée, l'enclave refuse. Et **une application non signée n'est pas
  dans le bac à sable** : elle lit `~/Library/Application Support` au lieu du
  conteneur, n'y trouve ni clé ni carnet, et propose d'ouvrir un compte —
  un compte de trop, orphelin dès qu'on relance la vraie app. Voir
  « Construire et lancer ».
- **Le bac à sable**, avec `network.client` **et `network.server`** : QUIC
  vit sur UDP et la pile lie un socket pour recevoir les datagrammes, ce que
  le bac à sable range côté serveur. Sans ce droit, « aucun annuaire ne
  répond » — vérifié. Rien n'écoute pour autant.
- **Pas d'attestation** : App Attest n'existe pas sur macOS. Le compte se
  crée en « aucune », que les annuaires de test acceptent. Ce que cette app
  prouve, c'est la chaîne clé-preuve-transport sur du vrai matériel Apple
  (`docs/attestation/enrolement-macos.md` du serveur).
- **L'annuaire** : `Sources/Mac/Ressources/annuaire.json` et
  `annuaire-racine.pem`, non versionnés, comme sur iOS — `nitrogen` par
  défaut dans les consignes du serveur.

## Construire et lancer

**Toujours signée, avec l'identité Developer ID, et par `-target`.**

```sh
xcodegen generate     # après tout changement de project.yml ou fichier ajouté
xcodebuild build -project AirServiceLocator.xcodeproj -target ServiceLocatorMac \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application: Thierry DELHAISE (SB7H9B6TY8)"
open "$(xcodebuild -project AirServiceLocator.xcodeproj -target ServiceLocatorMac -showBuildSettings 2>/dev/null | awk '/BUILT_PRODUCTS_DIR/ {print $3}')/Service Locator.app"
```

Pourquoi ces deux réglages, et pas un `xcodebuild build -scheme` nu :

- **Sans identité sur la ligne de commande, la construction sort une app NON
  signée** — `Automatic` dans `project.yml` ne suffit pas à `xcodebuild`
  hors Xcode. Non signée, l'app n'est pas sandboxée : elle lit
  `~/Library/Application Support` et non le conteneur
  `~/Library/Containers/org.airdesktop.servicelocator.mac/`, ne trouve pas la
  clé, et ouvre un compte de plus sur l'annuaire (c'est ainsi qu'un compte
  orphelin est né, effacé depuis). L'identité Developer ID est aussi celle
  qui laisse le pare-feu du Mac écouter.
- **`-target`, pas `-scheme`** : une identité passée sur la ligne de commande
  s'applique à toutes les cibles que le schéma entraîne, dont la cible
  d'essais iOS, qui n'a pas d'`Info.plist` à signer et fait échouer la
  construction. `-target` ne construit que l'app macOS.

Le xcframework doit porter la tranche macOS : `scripts/construire-mobile.sh
apple` dans le dépôt client.
