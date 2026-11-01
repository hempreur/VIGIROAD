# Mises à jour de l'application (Android, hors Play Store)

## Pour l'utilisateur

1. À l'ouverture de VIGIROAD (puis toutes les 6 h), l'application vérifie s'il existe une version
   plus récente.
2. Si oui, une fenêtre centrée l'annonce : version installée, nouvelle version, améliorations. La
   mise à jour est **obligatoire** : la fenêtre recouvre l'application tant qu'elle n'est pas faite
   (« Quitter l'application » reste possible).
3. « Mettre à jour maintenant » : la première fois, Android demande d'**autoriser VIGIROAD à
   installer des applications** (« Autoriser cette source ») ; on revient ensuite dans VIGIROAD et
   la mise à jour reprend seule.
4. Téléchargement avec progression, vérification de l'empreinte, puis **confirmation d'Android**
   (« Mettre à jour »). Pas de désinstallation, pas de navigateur ; les données sont conservées.

Sécurité de conduite : si une mise à jour est détectée pendant un guidage, la fenêtre n'apparaît
qu'à l'arrivée ou à l'arrêt du guidage. Sans connexion, aucune version n'est déclarée obsolète :
l'application reste utilisable.

## Fonctionnement

- Chaque release contient `vigiroad-update.json` (version, numéro de compilation, notes, URL et
  empreinte SHA-256 de chaque APK), généré par la CI (`.github/scripts/update_manifest.py`) puis
  relu à l'adresse que lisent les applications pour vérifier qu'il est cohérent.
- L'application lit `https://github.com/hempreur/VIGIROAD/releases/latest/download/vigiroad-update.json`
  (`VR_UPDATE_MANIFEST_URL`), compare le numéro de compilation (`pubspec.yaml`, `+N`) au sien,
  télécharge l'APK de l'architecture principale du téléphone, vérifie l'empreinte et l'installe par
  l'API Android `PackageInstaller`.
- Android refuse toute mise à jour qui n'est pas signée par la clé VIGIROAD INC : un APK modifié ne
  peut pas remplacer l'application.
- Publier une version = pousser une branche `release/vX.Y.Z` (après avoir augmenté `version:` dans
  `pubspec.yaml`) : la CI compile, signe, publie et met à jour le fichier de version. Les notes
  affichées sont les puces de la section `## X.Y.Z` de `docs/RELEASE_NOTES_X.Y.md`.

## Limites

- Android exige toujours une confirmation de l'utilisateur pour installer (seuls le Play Store et
  les téléphones gérés par une entreprise installent sans confirmation).
- iOS : non concerné (installation par Sideloadly / AltStore, voir `INSTALL_IOS.md`).
- Les versions 1.2.x et antérieures n'ont pas ce système : la 1.3.0 s'installe une fois à la main.
