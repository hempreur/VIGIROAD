# Résumé des tests

- Tests réussis : **242**, échoués : **0**, ignorés : 0
- Couverture des lignes (code Dart) : **77.3 %** (4082/5280)

| Module | Couverture |
|---|---|
| app | 84 % (46/55) |
| core | 91 % (242/266) |
| features/account | 71 % (294/413) |
| features/history | 93 % (103/111) |
| features/navigation | 76 % (716/940) |
| features/onboarding | 90 % (47/52) |
| features/plates | 69 % (817/1190) |
| features/reports | 73 % (205/280) |
| features/search | 91 % (123/135) |
| features/sentrix | 80 % (765/952) |
| features/settings | 90 % (236/263) |
| features/splash | 100 % (60/60) |
| features/traffic | 76 % (236/312) |
| features/update | 76 % (192/251) |

# Banc de mesure post-OCR (synthétique)

2000 véhicules par scénario, images toutes les 250 ms, graine fixe 2026.
Taux par caractère : miss = image sans lecture, benign = confusion lettre/chiffre, harmful = autre caractère valide.

| Scénario | Images/véh. | miss | benign | harmful | Précision | Rappel | Fausses plaques | Temps moyen/image |
|---|---|---|---|---|---|---|---|---|
| Conditions favorables | 8 | 0.15 | 0.03 | 0.01 | 99.59 % | 96.3 % | 8 | 15 µs |
| Conditions moyennes | 8 | 0.3 | 0.06 | 0.03 | 99.87 % | 79.4 % | 2 | 6 µs |
| Conditions difficiles | 10 | 0.5 | 0.1 | 0.06 | 99.91 % | 55.9 % | 1 | 4 µs |

