# VIGIROAD 1.4 — comptes et VIGIROAD Control Center

## 1.4.1

- Mise à jour automatique : si le téléphone refuse l'installation directe (« INSTALL_FAILED_INTERNAL_ERROR: Permission Denied », fréquent sur Xiaomi, Redmi, POCO avec MIUI / HyperOS), l'installateur du système s'ouvre avec le fichier déjà vérifié

Depuis une version 1.3.x ou 1.4.0 qui affiche cette erreur : installer la 1.4.1 une fois à la main (fichier `vigiroad-1.4.1-arm64.apk` de cette page) ; les mises à jour suivantes passeront.

## 1.4.0

- Compte VIGIROAD facultatif (Réglages → Compte VIGIROAD) : créer un compte, se connecter, retrouver ses appareils et ses sessions
- Enregistrement volontaire de l'appareil avec un identifiant aléatoire, renouvelable à tout moment (aucun identifiant matériel)
- Région et position approximatives désactivées par défaut, uniquement avec votre accord ; le retrait efface les données
- Export de vos données et suppression définitive du compte depuis l'application
- Aucune image de caméra, plaque lue ni voix envoyée au serveur ; GPS, lecture des plaques, trafic et SENTRIX inchangés

## Administration (nouveau)

- **VIGIROAD ADMIN MANAGER** (Windows, installateur `.exe`) : tableau de bord, utilisateurs, appareils, sessions, statistiques, géographie
- **VIGIROAD SERVER CONTROL** (Linux, `.deb` et AppImage) : supervision du VPS, Docker, services VIGIROAD, maintenance, sauvegardes
- Double authentification obligatoire pour les administrateurs, journal d'audit, sauvegardes automatiques testées chaque semaine

Guide : [docs/admin/INSTALLATION.md](admin/INSTALLATION.md)
