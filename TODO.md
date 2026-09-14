# TODO — ce que le serveur attend de l'app iOS

Ce fichier dit **précisément** ce que la vérification côté serveur attend de
toi, pour que tu puisses le produire sans aller-retour. Il y avait deux
livrables ; le premier est rendu, le second attend un iPhone.

Tout le reste de l'app (écrans, modèle, transport) est décrit dans `CLAUDE.md`,
« L'état réel, sans fard » — ce fichier ne parle que de l'attestation.

## Livrable 1 — l'app compile et tourne — FAIT

- La CI compile sur une destination de simulateur générique et lance les
  essais (`14b603c`) : verte.
- Construite et lancée sur oxygen : simulateur iPhone 17, et la cible macOS
  signée sur le Mac lui-même (`322922e`). Vérifiée de bout en bout contre
  `asl-server`, puis contre `nitrogen`.
- Ce qui n'a PAS été fait : la lancer sur un **iPhone réel**. Il n'y en a pas
  sous la main — seulement un iPad en iOS 12, trop vieux pour la cible (iOS
  17+) et sans App Attest.

## Livrable 2 — une capture App Attest réelle — BLOQUÉ (pas d'iPhone)

Le but : `asl-apple`, côté serveur, est écrit d'après la documentation d'Apple
et n'a JAMAIS vu de vraie attestation. Cette capture confirme (ou corrige) nos
constantes. Le mode d'emploi détaillé est dans le dépôt serveur,
`docs/attestation/capture-reelle.md`.

Ce qui bloque est matériel : **App Attest est inerte au simulateur et n'existe
pas sur macOS**. L'app macOS d'enrôlement a validé la chaîne clé-d'appareil
P-256 (Secure Enclave + Touch ID) sur du vrai matériel Apple, en attestation
« aucune » — elle valide `asl-cle` et l'enrôlement, pas `asl-apple`.

Le jour où un iPhone (iOS 17+) est là :

1. Intégrer `outils-capture/CaptureAppAttest.swift` (il n'est pas encore dans
   la cible — rien ne l'appelle), appeler `capturerUneAttestation()` une fois
   (bouton, ou `applicationDidBecomeActive`).
2. Lancer **sur l'appareil**, lire la console Xcode, récupérer le bloc imprimé.
3. **Compléter l'`APP_ID`** avec le Team ID à 10 caractères (Xcode ne le donne
   pas à l'exécution : il est dans *Signing & Capabilities*, ou dans
   `project.yml`).

### Ce que tu me rends, EXACTEMENT

Cinq valeurs, en clair, dans ta réponse à Thierry :

```
ATTESTATION_B64=<le base64 imprimé>
DEFI_B64=<le base64 imprimé>
APP_ID=<TeamID à 10 caractères>.<bundle id, ex. org.airdesktop.servicelocator>
ENVIRONNEMENT=developpement          # 'production' seulement si TestFlight/App Store
KEY_ID_B64=<le base64 imprimé>       # facultatif, pour recouper
```

Rien là-dedans n'est un secret : une attestation est publique par nature, la clé
qu'elle certifie n'a pas encore de compte, et le défi est jetable. Tu peux donc
coller ce bloc tel quel.

### Ce que le serveur en fera

Décoder `ATTESTATION_B64` et `DEFI_B64` en fichiers, écrire `APP_ID` et
`ENVIRONNEMENT`, puis rejouer contre la vraie racine d'Apple :
`cargo run --example verifier-une-capture -- capture/`. S'il dit **✔ VÉRIFIÉE**,
nos constantes tiennent. Sinon, il dira laquelle corriger — la façon de hacher
la clé, ou la forme de l'extension —, et je te le répercuterai.

## Ce dont tu n'as PAS besoin

- Pas de compte Apple payant supplémentaire au-delà de ton équipe de signature
  habituelle : une attestation de **développement** (lancée depuis Xcode) suffit
  pour la première capture.
- Pas d'entitlement spécial pour une capture de développement.

## Les règles

Commite chaque correctif (français, signé GPG, `Signed-off-by`, aucune mention
d'outil) et lis la CI après push. Le détail est dans `CLAUDE.md`.
