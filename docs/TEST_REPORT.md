# Rapport de tests — VIGIROAD 1.0

Rapport généré à partir de la CI (Flutter 3.47.9). Le détail de chaque exécution (journaux,
couverture `lcov.info`, captures) est publié sur la branche `ci-logs/quality`, fichier
`test_summary.md`.

## Synthèse

| Indicateur | Valeur |
|---|---|
| Tests automatiques | **156 réussis, 0 échec** |
| Couverture des lignes (code Dart) | **81 %** |
| Analyse statique (`flutter analyze`) | aucun problème |
| APK Android debug / release | compilés |
| Build iOS (non signé) | compilé |

## Couverture par exigence du cahier des charges (§13)

| Test exigé | Couverture | Où |
|---|---|---|
| Tests unitaires | ✅ automatisé | `test/**` (domaine : formats, vote, itinéraire, import, commandes…) |
| Tests d'intégration | ✅ automatisé | `test/integration/simultaneous_test.dart`, parcours d'écrans |
| Reconnaissance OCR | ✅ chaîne post-OCR (banc synthétique) · 📱 lecture réelle sur appareil | `test/plates/pipeline_benchmark_test.dart` · protocole T4/T7 |
| Comparaison des plaques | ✅ automatisé | `test/plates/alert_flow_test.dart`, `watchlist_import_test.dart` |
| Fiabilité des alertes | ✅ automatisé (seuil, vote, anti-répétition, non-listée = rien) | `alert_flow_test.dart` |
| Navigation | ✅ automatisé (OSRM, suivi, recalcul, annonces) · 📱 trajet réel | `route_tracker_test.dart`, `navigation_session_test.dart` · T2/T3 |
| Trafic | ✅ affichage honnête « non configuré » | `navigation_screen_test.dart` |
| Microphone et synthèse vocale | ✅ logique (moteur simulé) · 📱 voix réelle | `sentrix/*`, `voice_queue_test.dart` · T9 |
| Caméra et GPS simultanés | ✅ logique · 📱 performance réelle | `simultaneous_test.dart` · T8 |
| Perte de réseau | ✅ recherche et itinéraire | `robustness_test.dart`, `navigation_screen_test.dart` · T11 |
| Consommation batterie | 📱 sur appareil | T13 |
| Surchauffe | 📱 sur appareil (cadence OCR adaptative testée) | `frame_analysis_test.dart` · T14 |
| Fonctionnement prolongé | ✅ 3 h de lecture simulées, 20 000 positions · 📱 3 h réelles | `robustness_test.dart` · T15 |
| Compatibilité Android/iOS | ✅ compilation des deux plateformes · 📱 essais | CI · T17 |
| Accessibilité et lisibilité | ✅ contrastes WCAG AA, 360×640, texte ×1,3, cibles ≥ 48 px, libellés | `test/quality/accessibility_test.dart` · T16 |

✅ = vérifié automatiquement à chaque modification · 📱 = à réaliser sur téléphone selon
[`DEVICE_TEST_PROTOCOL.md`](DEVICE_TEST_PROTOCOL.md).

## Banc de mesure post-OCR (synthétique)

2 000 véhicules par scénario, lectures OCR simulées avec erreurs typiques.

| Scénario | Précision | Rappel | Fausses plaques |
|---|---|---|---|
| Conditions favorables | 99,59 % | 96,3 % | 8 |
| Conditions moyennes | 99,87 % | 79,4 % | 2 |
| Conditions difficiles | 99,91 % | 55,9 % | 1 |

Ce banc a révélé un défaut corrigé avant livraison (17 % de fausses plaques dues au département
de la bande droite lu comme une plaque FNI). **Il ne mesure pas la lecture réelle par ML Kit** : aucun
taux de reconnaissance sur route n'est annoncé tant qu'il n'a pas été mesuré sur appareil.

## Défauts trouvés et corrigés par les tests

| Défaut | Détecté par | Correction |
|---|---|---|
| Fausses plaques FNI sur « AA-123-BB 75 » | banc synthétique | priorité SIV sur la ligne |
| Option `maxspeed` refusée par OSRM | vérification de la documentation OSRM | option retirée |
| Débordements sur petit écran et texte agrandi | tests d'accessibilité | panneaux adaptatifs, mode compact |
| Texte atténué sous le contraste WCAG | test de contrastes | couleur éclaircie |
| `ref.read` pendant la destruction (Riverpod 3) | tests de session | capture préalable |

## Captures d'écran

Générées à chaque exécution de la CI (`ci-logs/quality/screenshots/`) ; comparaison avec la
référence dans [`SCREENSHOTS.md`](SCREENSHOTS.md).
