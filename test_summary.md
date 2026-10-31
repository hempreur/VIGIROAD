# Résumé des tests

- Tests réussis : **177**, échoués : **0**, ignorés : 0
- Couverture des lignes (code Dart) : **79.6 %** (2851/3583)

| Module | Couverture |
|---|---|
| app | 82 % (42/51) |
| core | 91 % (237/260) |
| features/history | 93 % (103/111) |
| features/navigation | 78 % (703/899) |
| features/onboarding | 90 % (47/52) |
| features/plates | 70 % (717/1028) |
| features/search | 91 % (123/135) |
| features/sentrix | 84 % (375/446) |
| features/settings | 91 % (208/229) |
| features/splash | 100 % (60/60) |
| features/traffic | 76 % (236/312) |

# Banc de mesure post-OCR (synthétique)

2000 véhicules par scénario, images toutes les 250 ms, graine fixe 2026.
Taux par caractère : miss = image sans lecture, benign = confusion lettre/chiffre, harmful = autre caractère valide.

| Scénario | Images/véh. | miss | benign | harmful | Précision | Rappel | Fausses plaques | Temps moyen/image |
|---|---|---|---|---|---|---|---|---|
| Conditions favorables | 8 | 0.15 | 0.03 | 0.01 | 99.59 % | 96.3 % | 8 | 7 µs |
| Conditions moyennes | 8 | 0.3 | 0.06 | 0.03 | 99.87 % | 79.4 % | 2 | 4 µs |
| Conditions difficiles | 10 | 0.5 | 0.1 | 0.06 | 99.91 % | 55.9 % | 1 | 2 µs |

