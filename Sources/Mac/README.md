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
  Elle exige une **application signée** (une identité de développement
  suffit ; `project.yml` porte l'équipe) : non signée, l'enclave refuse.
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

```sh
xcodegen generate
xcodebuild build -project AirServiceLocator.xcodeproj -scheme ServiceLocatorMac -destination 'platform=macOS'
open "$(xcodebuild -project AirServiceLocator.xcodeproj -scheme ServiceLocatorMac -showBuildSettings 2>/dev/null | awk '/BUILT_PRODUCTS_DIR/ {print $3}')/Service Locator.app"
```

Le xcframework doit porter la tranche macOS : `scripts/construire-mobile.sh
apple` dans le dépôt client.
