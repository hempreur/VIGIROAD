# Protocole de tests sur appareil

Ces tests exigent un vrai téléphone et ne peuvent pas être automatisés en CI. Ils complètent les
tests automatiques (voir `TEST_REPORT.md`). Reporter les résultats dans le tableau en fin de document.

## Préparation

- Installer l'APK release (`vigiroad-1.0.0-arm64.apk`) ou dev, accorder caméra, position et micro.
- Importer une liste de test contenant **uniquement des plaques de véhicules dont vous avez l'accord**
  (ex. véhicules personnels ou de l'entreprise).
- Support voiture, téléphone en portrait, câble de charge **débranché** pour les mesures de batterie.

## Scénarios

| # | Test | Procédure | Attendu |
|---|---|---|---|
| T1 | Démarrage | Lancer l'application à froid | Splash < 3 s, carte affichée, position trouvée |
| T2 | Navigation | Saisir une adresse à 10–20 km, suivre le guidage | Tracé, consignes vocales aux bons moments, ETA cohérente |
| T3 | Sortie d'itinéraire | Prendre volontairement une autre route | Recalcul en < 20 s, annonce « Itinéraire recalculé » |
| T4 | Lecture de plaques | Activer la caméra, suivre/se garer derrière un véhicule de la liste à 3–5 m, 10–15 m, 20 m | Plaque confirmée en < 3 s à 3–15 m de jour |
| T5 | Alerte | Même véhicule | Encadré rouge, son, annonce SENTRIX, entrée dans l'historique |
| T6 | Non-correspondance | Véhicule absent de la liste | Aucune alerte, rien dans l'historique |
| T7 | Nuit / faible lumière | T4 de nuit | Avertissement « luminosité faible » ; noter le taux de lecture |
| T8 | Simultanéité | Guidage + caméra + commande SENTRIX pendant 30 min | Carte fluide, pas de voix superposées, consignes prioritaires |
| T9 | SENTRIX | Dire chaque commande de l'aide | Commande exécutée et confirmée |
| T10 | Interruption | Recevoir un appel pendant le guidage avec caméra | Caméra libérée ; reprise au retour dans l'application |
| T11 | Réseau | Couper les données pendant la navigation, puis rechercher une adresse | Message clair, guidage existant conservé, recalcul retenté au retour du réseau |
| T12 | Autorisations | Retirer la caméra dans les réglages système puis revenir | Message « Autorisez la caméra », pas de plantage |
| T13 | Batterie | 60 min guidage + caméra, écran allumé, luminosité 70 % | Noter la consommation (% / h) en mode Équilibré puis Économie |
| T14 | Température | Même session, téléphone en plein soleil derrière le pare-brise | Noter si le système signale une surchauffe ; l'intervalle d'analyse doit s'allonger |
| T15 | Fonctionnement prolongé | 3 h de guidage + caméra | Pas de plantage, mémoire stable (Paramètres développeur > Mémoire) |
| T16 | Lisibilité | Conduite de jour en plein soleil | Consigne, vitesse et alerte lisibles d'un coup d'œil |
| T17 | iOS | T1, T2, T4, T9 sur iPhone (iOS 15.5+) | Mêmes résultats |

## Mesures de lecture (T4/T7)

Pour chaque passage : plaque confirmée juste / fausse / aucune, distance, délai.

- **Précision** = justes / (justes + fausses)
- **Rappel** = justes / passages
- **Délai médian** de confirmation

## Résultats

| # | Téléphone (modèle, OS) | Date | Résultat | Mesures / remarques |
|---|---|---|---|---|
| T1 | | | | |
| … | | | | |
