# Module de lecture des plaques (OCR)

## Chaîne de traitement

| Étape | Implémentation | Fichier |
|---|---|---|
| Capture | Caméra arrière, 720p, flux d'images (CameraX sur Android en NV21, AVFoundation sur iOS en BGRA) | `plates/data/plate_scanner.dart` |
| Cadence | Une seule analyse à la fois ; intervalle adaptatif 150 ms – 1 s (1,5 × la durée mesurée de l'OCR, lissée) | `plates/domain/frame_analysis.dart` |
| Netteté | Variance du laplacien sur la luminance sous-échantillonnée ; images sous le seuil (12) écartées sans OCR | `frame_analysis.dart` |
| Luminosité | Moyenne de luminance ; avertissement « luminosité faible » sous 35/255 | `frame_analysis.dart` |
| OCR | Google ML Kit Text Recognition (latin), **sur l'appareil** ; aucune image n'est envoyée | `plate_scanner.dart` |
| Localisation | Lignes et blocs de texte ML Kit, retenus s'ils contiennent un format de plaque valide | `plate_scanner.dart` |
| Formats | France SIV (AA-123-AA) avec règles officielles (I, O, U exclus, SS interdit, 000 interdit) ; ancien FNI (1234 AB 75) seulement si les blocs sont séparés | `plates/domain/plate_format.dart` |
| Correction | Confusions lettre/chiffre corrigées selon la position attendue (8→B, 0→D, I→1…), 2 corrections au plus, chacune pénalise la confiance | `plate_format.dart` |
| Vote | ≥ 3 lectures identiques en 2,5 s, majoritaires (≥ 60 %) face aux variantes à 1 caractère près, confiance agrégée ≥ 0,7 ; pas de réémission avant 10 s | `plates/domain/plate_voter.dart` |
| Cycle de vie | Caméra libérée dès que l'application passe en arrière-plan, reprise au retour | `plates/application/plate_scanning_controller.dart` |

Ajouter un pays : implémenter `PlateFormat` et l'ajouter à `PlateFormats.all`.

## Mesures

### Chaîne post-OCR (automatique, à chaque CI)

`test/plates/pipeline_benchmark_test.dart` simule 2 000 véhicules par scénario avec des erreurs
OCR typiques (images ratées, confusions lettre/chiffre, caractère faux, bruit, textes parasites).
Le rapport est publié sur la branche `ci-logs/quality` (`alpr_pipeline_benchmark.md`).
Exigence vérifiée : précision ≥ 99 % dans tous les scénarios.

**Limite :** ces chiffres mesurent la robustesse de l'extraction et du vote, pas la qualité de
lecture de ML Kit sur de vraies photos. Aucun taux de reconnaissance réel n'est annoncé tant qu'il
n'a pas été mesuré sur appareil.

### Lecture réelle (sur téléphone)

En version de développement, le panneau caméra affiche le temps d'analyse de chaque image et la
netteté. Protocole proposé pour la mesure réelle (phase 9) :

1. Constituer une liste de test avec les plaques de véhicules dont vous avez l'accord.
2. Rouler ou se garer derrière chaque véhicule à 3–5 m, 10–15 m et 20 m, de jour et de nuit.
3. Noter pour chaque passage : plaque confirmée (juste / fausse / aucune) et délai de confirmation.
4. Calculer précision = justes / (justes + fausses) et rappel = justes / passages.

## Limites connues

- iOS : ML Kit ne fournit pas de confiance par ligne ; une valeur par défaut de 0,85 est utilisée.
- La position du cadre lumineux sur l'aperçu suppose un téléphone en portrait.
- Plaques étrangères : seuls les formats français sont actifs.
- La caméra ne fonctionne qu'application au premier plan.
