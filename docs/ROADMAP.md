# Feuille de route et limitations

## Plan d'implémentation

| # | Phase | Branche | Contenu | Validation |
|---|---|---|---|---|
| 1 | Socle | `feature/phase1-foundation` | Projet Flutter, natif Android/iOS, permissions, design tokens, SENTRIX, splash, CI | CI verte, APK installable |
| 2 | Interface DARK | `feature/phase2-ui` | Écran GPS principal, panneaux caméra/OCR/alerte, recherche, gestion des plaques, historique, réglages, app icon | Captures comparées à la référence |
| 3 | GPS | `feature/phase3-navigation` | Carte MapLibre sombre, suivi de position, recherche Photon, itinéraire OSRM, guidage vocal, ETA, vitesse, recalcul hors trajet, gestion hors-ligne | Trajet réel de bout en bout |
| 4 | Plaques | `feature/phase4-alpr` | Flux caméra, filtre de netteté, OCR ML Kit, extraction SIV/FNI, normalisation, vote multi-images, confiance | Mesures sur jeu d'images annoté (précision, rappel, latence) |
| 5 | Base & alertes | `feature/phase5-watchlist` | SQLite chiffré, import CSV/JSON, CRUD, doublons, priorités, synchronisation, moteur de correspondance, alertes | Plaque test → alerte ; plaque absente → aucune alerte |
| 6 | SENTRIX | `feature/phase6-sentrix` | Reconnaissance et synthèse vocale, registre extensible de commandes, états animés | Commandes exemples exécutées |
| 7 | Intégration | `feature/phase7-integration` | GPS + caméra + SENTRIX simultanés, file vocale à priorité, cycle de vie, interruptions | Session de conduite prolongée |
| 8 | Historique & réglages | `feature/phase8-settings` | Journal filtrable, purge, export, tous les réglages | Tests widgets |
| 9 | Qualité | `feature/phase9-hardening` | Couverture de tests, profilage CPU/batterie/température, accessibilité | Rapport de tests |
| 10 | Livraison | `release/1.0.0` | APK signé, archive iOS, documentation complète, captures finales | — |

## Limitations connues (à ce stade)

- **Trafic temps réel** : non disponible avec OpenStreetMap. Affiché comme indisponible ; un
  fournisseur payant peut être branché plus tard (voir `API_CONFIG.md`).
- **Services publics OSM** : le serveur OSRM de démonstration et Photon public suffisent pour le
  développement mais pas pour une exploitation ; prévoir un hébergement.
- **Limitations de vitesse** : à extraire des données OSM (`maxspeed`), couverture incomplète.
- **Caméra en arrière-plan** : impossible sur iOS et fortement restreinte sur Android ; la lecture
  des plaques ne fonctionne qu'application au premier plan.
- **Détection de plaques** : la première version localise les plaques via l'OCR et le format
  attendu ; un détecteur dédié (modèle embarqué) sera évalué en phase 4 selon les mesures.
- **iOS** : la CI produit un build non signé ; la distribution (TestFlight/App Store) nécessite
  un compte Apple Developer et les certificats du propriétaire.
- **Tests sur appareil** : la CI ne dispose pas de téléphone ; les tests caméra, GPS, batterie et
  température se font sur l'appareil de test du propriétaire, avec un protocole fourni en phase 9.
- **Cadre légal** : voir `PRIVACY.md`.
