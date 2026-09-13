# Consignes — air-service-locator-ios

Tu travailles sur l'**application iOS** d'air-service-locator — et sur
l'**application macOS** qui vit dans ce même dépôt (`Sources/Mac/`, une
cible XcodeGen à part, le même `Coeur`). Ce fichier te dit
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

Les **onze écrans sont écrits** (SwiftUI, iOS 17+) et **parlent au vrai
annuaire** par le transport d'`asl-client` (`Sources/Coeur/Reseau/Reel/`),
ou au banc en mémoire (`Sources/Coeur/Reseau/Simulation/`) quand aucun
annuaire n'est configuré (`README.md`, « Parler à un vrai annuaire »). Tout
compile sans avertissement et les essais passent (`xcodebuild test`,
simulateur iPhone 17). Les maquettes validées sont dans `../maquettes/` (hors
dépôt). Vérifié de bout en bout sur simulateur contre `asl-server` : compte,
machine, enrôlement, annonce, service joignable.

Ce qui manque, dans l'ordre où ça se fera :

1. ~~La clé P-256 dans la Secure Enclave~~ — **faite**
   (`Sources/Coeur/Identite/CleAppareil.swift`, `Messages.swift`) : CryptoKit
   rend `r ‖ s` et la clé SEC1 compressée sans rien déplier. La représentation
   opaque vit dans un fichier protégé, pas dans le Keychain (qui refuse sans
   identité de signature). Sur simulateur, la biométrie est un `LAContext`.
2. ~~Le transport~~ — **fait** (`AnnuaireReel.swift`) : l'ABI `asl_appareil_*`
   d'`asl-client-ffi`, en xcframework, la signature par rappel (le natif
   rappelle depuis son fil ; on bloque ce fil le temps que l'enclave signe),
   la connexion tenue. Le serveur (`2cf05dc`) rend les machines, les
   appareils, les services nommés avec leur état ; le `Carnet` local
   (UserDefaults) ne garde que ce qu'il ne range pas — dates, code en cours,
   révocation — et l'écran dit « inconnu » plutôt qu'une date inventée.
3. **La capture App Attest** (`outils-capture/`), qui exige un iPhone réel — il
   n'y en a pas sous la main, seulement le simulateur.
4. ~~Les écrans restants~~ — **faits** : le détail d'un service
   (`ServiceVue.swift`, verdict par point, candidats, ce que l'annuaire a
   répondu au daemon), et le second appareil par échange de QR codes
   (`Invitation.swift`, `EnrolerAppareilVue.swift` côté ancien,
   `RejoindreVue.swift` côté nouveau ; `CodeQR.swift` trace et lit). Les
   expositions restent un libellé tant que le serveur rend `501`.
5. ~~Un état de chargement au lancement~~ — **fait** : `Session` dit quand la
   première relecture n'a pas conclu, et l'écran attend au lieu de montrer
   l'accueil. Hors ligne, le compte connu reste ; seule une preuve refusée
   par l'annuaire le retire (et libère le handle natif, qui portait cette
   identité).
6. ~~L'application macOS~~ — **faite** (`Sources/Mac/`, cible
   `ServiceLocatorMac`) : une icône dans la barre de menus, le même `Coeur`,
   Touch ID par la Secure Enclave, le bac à sable avec `network.server` (le
   `bind` UDP de QUIC l'exige — vérifié). Compte créé sur `nitrogen` depuis ce
   Mac, en attestation « aucune » (App Attest n'existe pas sur macOS).
7. ~~L'icône~~ — **faite** (`Outils/Icone/generer.py`) : un dessin, trois
   plates-formes (iOS, macOS, Android — le dépôt Android copie les
   VectorDrawable produits ici).

Tu es sur un Mac (oxygen, MacBook Pro 2019 Intel, T2, Touch ID) avec Xcode 26.
Un vieil iPad en iOS 12 est parfois branché : `xcodebuild` s'en plaint
bruyamment, sans conséquence. L'application macOS s'y construit signée
(identité de développement, équipe dans `project.yml`) : c'est ce qui rend
la Secure Enclave utilisable.

## Ce qu'il faut tenir en écrivant un écran

- **Les écrans parlent à `Annuaire`, jamais au banc.** `AnnuaireSimule` n'est
  nommé que dans la composition et les essais.
- **Le vocabulaire est celui de `modele.md` §4.2** : `annoncé`, `joignable`
  (avec sa date), `parti (volontaire / inactivité)`, UDP `non sondé`. Le mot
  « en ligne » n'apparaît nulle part.
- **Un identifiant se compare sur ses octets** (`Identifiant`), jamais comme
  une chaîne ; il ne s'affiche que par `.texte` ou `.abrege`.
- **Ce que l'on ne sait pas faire se dit à l'écran** (`ContentUnavailableView`),
  on ne le simule pas.
- Les dates s'affichent en français quel que soit le réglage de l'appareil
  (`Date.relatif`, `Date.jour`).

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
