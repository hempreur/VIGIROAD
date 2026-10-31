# Banc de mesure post-OCR (synthétique)

2000 véhicules par scénario, images toutes les 250 ms, graine fixe 2026.
Taux par caractère : miss = image sans lecture, benign = confusion lettre/chiffre, harmful = autre caractère valide.

| Scénario | Images/véh. | miss | benign | harmful | Précision | Rappel | Fausses plaques | Temps moyen/image |
|---|---|---|---|---|---|---|---|---|
| Conditions favorables | 8 | 0.15 | 0.03 | 0.01 | 99.59 % | 96.3 % | 8 | 17 µs |
| Conditions moyennes | 8 | 0.3 | 0.06 | 0.03 | 99.87 % | 79.4 % | 2 | 7 µs |
| Conditions difficiles | 10 | 0.5 | 0.1 | 0.06 | 99.91 % | 55.9 % | 1 | 6 µs |
