# Guide d'installation

## Android (téléphone sous Android 7.0 ou plus récent)

### Installer l'APK

1. Ouvrir la page **Releases** du dépôt GitHub sur le téléphone.
2. Version stable : release **v1.0.0**, fichier `vigiroad-1.0.0-arm64.apk` (téléphones 64 bits, la
   quasi-totalité depuis 2017) ou `vigiroad-1.0.0-arm32.apk` (anciens modèles 32 bits).
   Version de test : pré-release **apk-dev**, fichier `vigiroad-dev-debug.apk`.
3. Ouvrir le fichier téléchargé ; si le téléphone le demande, autoriser l'installation depuis le
   navigateur (*Paramètres > Applications > Accès spécial > Installer des applis inconnues*).
4. Au premier lancement, accorder **Position**, **Caméra** et **Microphone**.

> L'APK n'est signé avec une clé de distribution que si elle a été configurée (voir plus bas).
> Sinon il est signé avec la clé de débogage : installable, mais non publiable sur le Play Store,
> et une mise à jour signée différemment exigera de désinstaller la version précédente.

### Publier sur le Google Play Store

1. Créer une clé : `keytool -genkey -v -keystore vigiroad.jks -keyalg RSA -keysize 2048 -validity 10000 -alias vigiroad`
2. Dans GitHub, *Settings > Secrets and variables > Actions*, créer :
   `VR_KEYSTORE_BASE64` (`base64 -w0 vigiroad.jks`), `VR_KEYSTORE_PASSWORD`, `VR_KEY_ALIAS`, `VR_KEY_PASSWORD`.
3. Les compilations de `main` et des étiquettes `v*` sont alors signées pour la distribution.
4. Pour le Play Store, produire un bundle : `flutter build appbundle --release --dart-define-from-file=config/prod.env`.

Conservez la clé en lieu sûr : sans elle, aucune mise à jour de l'application publiée n'est possible.

## iOS (iPhone sous iOS 15.5 ou plus récent)

La CI vérifie que le projet iOS compile (build non signé). L'installation sur iPhone nécessite :

1. Un Mac avec Xcode et CocoaPods, et un compte **Apple Developer** (99 $/an pour TestFlight / App Store).
2. `flutter pub get`, puis ouvrir `ios/Runner.xcworkspace` dans Xcode.
3. *Signing & Capabilities* : choisir l'équipe, garder l'identifiant `fr.vigiroad.vigiroad` (ou le modifier).
4. Test direct : brancher l'iPhone, `flutter run --release --dart-define-from-file=config/prod.env`.
5. TestFlight : `flutter build ipa --dart-define-from-file=config/prod.env`, puis envoyer
   `build/ios/ipa/*.ipa` avec l'application *Transporter*.

## Compiler depuis les sources

```bash
# Prérequis : Flutter 3.47.9, JDK 21, Android SDK (API 37)
git clone https://github.com/hempreur/VIGIROAD.git && cd VIGIROAD
flutter pub get
flutter test --exclude-tags screenshots
flutter build apk --release --split-per-abi --dart-define-from-file=config/prod.env
```

## Configuration

Les services (carte, itinéraires, recherche, synchronisation de la liste) se règlent dans
`config/<env>.env` — voir [`API_CONFIG.md`](API_CONFIG.md). Avant une exploitation réelle, remplacer
les serveurs publics de démonstration (OSRM, Photon) par des instances hébergées.

## Premiers pas

1. **Plaques** : menu SENTRIX (appui long sur le robot) > *Plaques à surveiller* > *Importer* un
   fichier CSV/JSON (format : [`PLATES_FORMAT.md`](PLATES_FORMAT.md)) ou *Ajouter*.
2. **Navigation** : toucher *Où allez-vous ?*, choisir une adresse ; le guidage démarre.
3. **Lecture des plaques** : toucher le panneau *Caméra arrière* (téléphone sur support, caméra
   dégagée vers la route).
4. **SENTRIX** : toucher le robot puis parler (« Active la détection », « Quelle est ma vitesse ? »…).
5. **Réglages** : seuils, sons, conservation de l'historique, performance.
