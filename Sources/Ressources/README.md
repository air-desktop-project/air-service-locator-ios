# Ressources

`Info.plist` et les catalogues d'actifs.

**`Info.plist` N'EST PAS VERSIONNÉ ICI** : il est produit par `xcodegen generate`
à partir du bloc `info:` de `project.yml`. Deux fichiers diraient la même chose,
et c'est celui qu'on ne relit pas qui finirait par diverger.

C'est donc dans `project.yml` que se trouve `NSFaceIDUsageDescription` — la
phrase que l'utilisateur lit avant de poser son doigt, et sans laquelle iOS
refuse de lancer une application qui lie `LocalAuthentication`.
