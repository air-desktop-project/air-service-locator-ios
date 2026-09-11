# Consignes — air-service-locator-ios

Tu travailles sur l'**application iOS** d'air-service-locator. Ce fichier te dit
la mission, l'état réel, la première tâche, et les règles qui ne se négocient
pas. Lis-le en entier avant de toucher au code.

## Ce que l'application est

Le client mobile d'un **annuaire fédéré de daemons** : un utilisateur ouvre un
compte, déclare ses machines (des Linux), et voit quels services y écoutent et
sur quel port. L'application ADMINISTRE le compte ; ce sont les machines qui
annoncent, pas elle.

Le serveur et le protocole vivent dans le dépôt **air-service-locator-server**
(public, `github.com/air-desktop-project/air-service-locator-server`). Sa
`docs/protocole.md` est la source de vérité du fil ; `docs/modele.md` du modèle.
Si tu as besoin du détail, clone-le à côté et lis-le — ne devine pas le
protocole.

## L'état réel, sans fard

Le dépôt porte une **arborescence** (XcodeGen, `project.yml`), sa CI, et un seul
type qui fait quelque chose (`Sources/Coeur/Identite/IdentiteLocale.swift`).
**Rien n'a jamais été compilé** : tout a été posé depuis une machine Linux, sans
Xcode. Tu es sur un Mac (oxygene) avec Xcode : **la première construction est un
contrôle qui n'a jamais été passé.** Attends-toi à ce qu'elle échoue, et
corrige ce qui bloque avant d'ajouter quoi que ce soit.

## Ta première tâche, concrète

**Faire compiler et produire une capture App Attest réelle**, dans cet ordre :

1. Générer le projet (`scripts/`, ou `xcodegen`), l'ouvrir dans Xcode, le faire
   **compiler** sur un simulateur, puis sur un **appareil réel** (App Attest est
   inerte au simulateur).
2. Intégrer [`outils-capture/CaptureAppAttest.swift`](outils-capture/CaptureAppAttest.swift) :
   il tire un défi, génère une clé dans la Secure Enclave, appelle `attestKey`,
   et imprime l'attestation et le défi en base64.
3. Lancer sur l'appareil, **récupérer le bloc imprimé**, et le rendre à Thierry.
   Ce bloc débloque la vérification côté serveur : `asl-apple` est écrit d'après
   la documentation d'Apple et n'a jamais vu de vraie attestation ; cette
   capture confirme (ou corrige) nos constantes.

Le mode d'emploi complet — pré-requis, ce qu'il faut noter, comment le rendre —
est dans le serveur : `docs/attestation/capture-reelle.md`.

## Le protocole, l'essentiel que l'app devra tenir

- **La clé de l'appareil est P-256, dans la Secure Enclave**, sous contrôle
  biométrique (`kSecAccessControlBiometryCurrentSet`). Ed25519 est réservé aux
  machines ; l'enclave ne fait que P-256.
- **Ouvrir un compte** : `GET /v1/defi` rend un défi (32 octets) ; l'appareil
  signe une preuve de possession, et poste `POST /v1/comptes` dont le corps est
  `plateforme (1) ‖ clé (33, SEC1 compressé) ‖ preuve (64, r‖s) ‖ attestation`.
  La plate-forme vaut 1 pour Apple. Le défi de l'attestation lie la clé et la
  connexion (voir `docs/protocole.md` §2.1).
- **Aucun mot de passe** : un compte est un jeu d'appareils enrôlés. La biométrie
  est une condition d'usage de la clé, appliquée par le matériel — jamais une
  donnée envoyée.
- **Aucune donnée personnelle** hébergée, hormis un alias public facultatif.

N'écris PAS les écrans tant que le modèle n'est pas arrêté : des vues sur des
données supposées sont des vues à jeter. Concentre-toi sur le noyau (identité,
clé, réseau) et la capture.

## Les règles qui ne se négocient pas

- **Ce dépôt est PUBLIC.** Aucun secret dans un commit, un message, un fichier :
  ni clé privée, ni jeton, ni identifiant d'équipe si Thierry le juge sensible.
- **Commits** : en français, *conventional commits*, **signés GPG** (clé
  `C99EBB9BA26773011F924C4CA9F56C4D9F59EE03`), avec
  `Signed-off-by: Thierry DELHAISE <thierry.delhaise@gmail.com>`. **Aucune
  mention d'Anthropic, de Claude, ni de `Co-Authored-By`**, nulle part.
- **Ne commits et ne pushes que si Thierry le demande.** Sur la branche par
  défaut, branche d'abord.
- **Après chaque push, lis la CI** (`gh run watch`), et rapporte ce qu'elle dit.
- Le style du dépôt est exigeant et EXPLIQUÉ : le code dit pourquoi, pas
  seulement quoi. Lis un fichier existant avant d'en écrire un, et tiens le même
  registre.
