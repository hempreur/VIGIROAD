# Installation du VIGIROAD Control Center

## 1. Mettre à jour le serveur (VPS Ubuntu)

Sur le VPS, en SSH, relancer la même commande qu'à l'installation :

```bash
curl -fsSL https://raw.githubusercontent.com/hempreur/VIGIROAD/main/server/deploy/install.sh -o install.sh
sudo bash install.sh
```

Le script **conserve** la clé de l'application, le domaine et le pare-feu, et ajoute :

- PostgreSQL 16 (volume `pg_data`, jamais exposé) ;
- l'API d'administration, l'agent de supervision et le service de sauvegarde ;
- les secrets manquants dans `server/deploy/.env` (`VR_DB_PASSWORD`, `VR_ADMIN_SECRET`,
  `VR_AGENT_TOKEN`, `VR_ADMIN_SETUP_TOKEN`), droits `600` ;
- la base de pays DB-IP Lite (renouvelée chaque mois) ;
- la mise à jour à distance (unités systemd `vigiroad-deploy.path/.service`).

Aucun nouveau port n'est ouvert : tout passe par HTTPS (443) via Caddy.

À la fin, le script affiche le **jeton d'installation** (tant qu'aucun administrateur n'existe).

## 2. Premier administrateur

1. Installer une des applications (ci-dessous) et saisir l'adresse du serveur
   (par exemple `15-235-120-182.sslip.io`).
2. L'application propose « Créer le premier administrateur » : saisir le jeton d'installation,
   un nom, une adresse e-mail et un mot de passe (12 caractères minimum).
3. Scanner le QR code avec une application d'authentification (Google Authenticator,
   Microsoft Authenticator, Aegis, 1Password…) et saisir le code à 6 chiffres.

Ce compte est **Propriétaire**. Le jeton d'installation ne sert plus ensuite. Les autres
administrateurs sont créés depuis la page « Administrateurs » (rôles : Administrateur,
Opérateur serveur, Lecture seule) ; chacun active sa double authentification à sa première connexion.

## 3. VIGIROAD ADMIN MANAGER (Windows)

Les applications d'administration **ne sont pas publiées sur GitHub** (1.7) : la CI les dépose
sur votre serveur, qui ne les remet qu'à un administrateur connecté.

**Une seule fois** : copier la valeur `VR_RELEASE_TOKEN` affichée par `install.sh` (ou
`sudo grep VR_RELEASE_TOKEN /opt/vigiroad/server/deploy/.env`) dans le secret GitHub du même nom
(Settings → Secrets and variables → Actions). Chaque release dépose alors les fichiers dans
`/opt/vigiroad/desktop` sur le VPS.

Première installation sur un PC Windows (PowerShell, avec votre accès SSH) :

```powershell
scp ubuntu@<ip-du-vps>:/opt/vigiroad/desktop/vigiroad-*-admin-manager-setup.exe .
```

(le dossier n'est lisible que par root : `sudo cp /opt/vigiroad/desktop/vigiroad-*-setup.exe ~ && sudo chown ubuntu ~/vigiroad-*-setup.exe`
sur le VPS avant le `scp`). L'installateur crée les raccourcis Bureau et menu Démarrer, sans droits
administrateur.

Windows SmartScreen peut avertir au premier lancement (« Informations complémentaires » →
« Exécuter quand même ») tant que l'installateur n'est pas signé par un certificat de signature de code.

**Mises à jour automatiques** : vérifiées à la connexion puis toutes les 15 minutes ; une version
plus récente est téléchargée depuis votre serveur, vérifiée (SHA-256), installée sans clic, puis
l'application redémarre. Une version antérieure à la dernière déposée est refusée par le serveur
(et la mise à jour s'installe aussitôt).

## 4. VIGIROAD SERVER CONTROL (Linux)

Sur un poste Ubuntu/Debian :

```bash
sudo apt install ./vigiroad-<version>-server-control-amd64.deb   # copié depuis /opt/vigiroad/desktop du VPS
```

ou rendre exécutable l'AppImage (`chmod +x`, puis double-clic). L'application apparaît dans le menu
Système.

### Sur le VPS lui-même (session graphique distante)

Le VPS n'a pas d'écran. Le script suivant installe un bureau **léger** (XFCE), le bureau à distance
**xrdp limité à 127.0.0.1** et l'application :

```bash
sudo bash /opt/vigiroad/server/deploy/install-desktop.sh
```

- Il vérifie d'abord la RAM et le disque (2 Go / 3 Go libres recommandés) ; une session XFCE
  consomme environ 300 Mo ; le serveur VIGIROAD n'est pas arrêté.
- Il crée l'utilisateur `vigiroad` (mot de passe affiché une fois, à changer avec `sudo passwd vigiroad`).
- **Aucun port n'est ouvert** : le bureau à distance n'est joignable que par un tunnel SSH.

Connexion depuis Windows :

```powershell
ssh -L 3389:127.0.0.1:3389 ubuntu@<IP du VPS>
```

puis « Connexion Bureau à distance » (`mstsc`) vers `localhost:3389`, session **Xorg**, utilisateur
`vigiroad`. Lancer « VIGIROAD Server Control » depuis le bureau et se connecter à `https://<domaine>`.

## 5. Application mobile (1.4)

Rien à configurer : le compte utilise le même serveur que le trafic. Le compte est facultatif
(Réglages → Compte VIGIROAD).
