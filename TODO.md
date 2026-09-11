# TODO — ce que le serveur attend de l'app iOS

Ce fichier dit **précisément** ce que la vérification côté serveur attend de
toi, pour que tu puisses le produire sans aller-retour. Il y a deux livrables,
dans cet ordre : faire compiler, puis rendre UNE capture App Attest réelle.

Tout le reste de l'app (écrans, modèle) n'est PAS demandé ici — n'y touche pas.

## Livrable 1 — l'app compile et tourne sur un appareil

1. Générer le projet (`xcodegen`, ou le script du dépôt) et l'ouvrir dans Xcode.
2. Le faire **compiler** sur un simulateur. La CI échoue actuellement sur
   « Unable to find a device matching the provided destination specifier » : la
   destination de simulateur codée dans `.github/workflows` ne correspond plus à
   l'image du runner. **Corrige-la** (une destination générique comme
   `generic/platform=iOS Simulator` évite de dépendre d'un modèle précis), et
   vérifie que la CI repasse au vert.
3. Le faire **compiler et se lancer sur un appareil réel** (App Attest est inerte
   au simulateur).

Commite chaque correctif (français, signé GPG, `Signed-off-by`, aucune mention
d'outil) et lis la CI après push.

## Livrable 2 — une capture App Attest réelle

Le but : `asl-apple`, côté serveur, est écrit d'après la documentation d'Apple
et n'a JAMAIS vu de vraie attestation. Cette capture confirme (ou corrige) nos
constantes. Le mode d'emploi détaillé est dans le dépôt serveur,
`docs/attestation/capture-reelle.md`.

1. Intégrer `outils-capture/CaptureAppAttest.swift`, appeler
   `capturerUneAttestation()` une fois (bouton, ou `applicationDidBecomeActive`).
2. Lancer **sur l'appareil**, lire la console Xcode, récupérer le bloc imprimé.
3. **Compléter l'`APP_ID`** avec le Team ID à 10 caractères (Xcode ne le donne
   pas à l'exécution : il est dans *Signing & Capabilities*).

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
