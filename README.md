# air-service-locator-ios

L'application iOS d'**air-service-locator** : ouvrir un compte, déclarer ses
machines, et voir quels daemons y écoutent — et sur quel port.

> ## État : une arborescence, et un seul type qui fait quelque chose
>
> Le dépôt porte sa structure, sa définition de projet et sa CI. Il ne contient
> **aucun écran** : les spécifications ne sont pas écrites, et dessiner des vues
> avant que le modèle soit arrêté produirait des écrans qui décrivent des données
> supposées.
>
> Le seul code qui fait quelque chose est
> [`IdentiteLocale`](Sources/Coeur/Identite/IdentiteLocale.swift), qui constate
> ce que l'appareil sait confirmer. **Il n'a jamais été compilé** : ce dépôt a
> été posé depuis une machine Linux, sans Xcode. La première construction sur
> macOS est un contrôle qui reste à passer.

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
open AirServiceLocator.xcodeproj
```

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
