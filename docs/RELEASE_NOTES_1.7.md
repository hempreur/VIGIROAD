# VIGIROAD 1.7 — versions obsolètes bloquées, mises à jour automatiques de l'administration

## 1.7.0

- Une ancienne version de VIGIROAD devient inutilisable dès qu'une nouvelle version est publiée : seul l'écran de mise à jour reste accessible
- Le serveur VIGIROAD refuse les données (trafic, limitations, signalements) aux versions obsolètes
- L'application peut être suspendue à distance depuis ADMIN MANAGER, avec un message affiché aux conducteurs
- iPhone : écran de version obsolète avec la page de téléchargement de la nouvelle version
- Par sécurité, un guidage en cours n'est jamais interrompu : l'écran apparaît à l'arrivée ou à l'arrêt du guidage

## Administration

- ADMIN MANAGER et SERVER CONTROL ne sont plus publiés sur GitHub : ils sont déposés sur votre serveur et téléchargeables uniquement par un administrateur connecté
- Mise à jour automatique dès qu'une version est disponible (vérification au démarrage puis toutes les 15 minutes), installation sans clic
- Nouvelle page « Versions » : tentatives d'utilisation d'une ancienne version (date, appareil, version, pays), versions en circulation, blocage à distance de l'application
