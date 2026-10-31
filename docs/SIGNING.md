# Signature de l'application

Les APK de VIGIROAD sont signés par **VIGIROAD INC (CODEX HEMPREUR)**.

| | |
|---|---|
| Titulaire du certificat | `CN=CODEX HEMPREUR, O=VIGIROAD INC` |
| Algorithme | RSA 4096 bits |
| Validité | 100 ans (jusqu'en 2126) |
| Empreinte SHA-256 | `C5:A9:67:94:B8:C2:F6:33:3B:FC:87:15:E7:E7:7C:B2:A1:EE:FC:85:26:E2:81:5D:E2:E4:28:FE:16:3D:B0:99` |

Vérifier un APK téléchargé :

```bash
apksigner verify --print-certs vigiroad-x.y.z-arm64.apk
```

L'empreinte doit être exactement celle ci-dessus.

## Fonctionnement en CI

La clé n'est **jamais** dans le dépôt. La CI la lit dans quatre secrets GitHub
(`Settings → Secrets and variables → Actions`) :

| Secret | Contenu |
|---|---|
| `VR_KEYSTORE_BASE64` | fichier `vigiroad-release.jks` encodé en base64 |
| `VR_KEYSTORE_PASSWORD` | mot de passe du fichier |
| `VR_KEY_ALIAS` | `vigiroad` |
| `VR_KEY_PASSWORD` | mot de passe de la clé (identique) |

À chaque APK release, la CI affiche le certificat (`signature.txt` dans les journaux) et échoue si
la clé est fournie mais que l'APK n'est pas signé par VIGIROAD INC. Sans les secrets, l'APK est
signé avec une clé de débogage (avertissement dans la CI).

## Important

- **Conserver `vigiroad-release.jks` et son mot de passe en lieu sûr** (deux copies hors ligne) :
  sans eux, aucune mise à jour de l'application ne peut être publiée sous la même identité.
- Les versions jusqu'à 1.0.1 étaient signées avec une clé de débogage. Android refuse d'installer
  par-dessus une application signée par une autre clé : pour passer à une version signée VIGIROAD
  INC, **désinstaller l'ancienne version** une fois (exporter d'abord la liste de plaques depuis
  l'écran Plaques si besoin).
- iOS : la signature exige un compte Apple Developer au nom de VIGIROAD INC ; la CI compile
  actuellement l'application iOS sans signature.
