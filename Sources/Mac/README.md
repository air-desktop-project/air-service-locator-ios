# L'application macOS

Une icône dans la barre de menus, un panneau dessous : le compte, les
machines et leurs services, les appareils — et trois gestes : ouvrir un
compte avec ce Mac (Touch ID), déclarer une machine (et lire son code
d'enrôlement), enrôler un autre appareil ou rejoindre un compte (par le texte
de l'invitation, collé — pas de caméra sur un Mac).

Tout le cœur est celui de l'application iOS, compilé tel quel pour macOS :
`Sources/Coeur/` (modèle, `Annuaire`, clé dans la Secure Enclave, transport
QUIC) et `Session`. Seuls ce dossier et `Couleurs.swift` s'y ajoutent.

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
