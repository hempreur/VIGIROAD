# Architecture

## Principes

- **Modules par fonctionnalité** (`lib/features/<module>`), chacun découpé en couches
  `domain` (règles métier pures, sans Flutter), `data` (accès aux plugins, réseau, SQLite)
  et `presentation` (widgets, contrôleurs Riverpod).
- **Dépendances vers l'intérieur** : `presentation → domain ← data`. Le domaine ne connaît
  ni Flutter ni les plugins ; il est testable en Dart pur.
- **Injection par Riverpod** : chaque service natif est exposé derrière une interface
  (`PermissionService`, futurs `LocationSource`, `PlateReader`, `VoiceEngine`…) et remplacé par
  un faux dans les tests via `ProviderScope.overrides`.
- **Aucun écran ne présente une donnée simulée comme réelle** (règle 2) : les faux services
  n'existent que dans `test/`.

## Arborescence

```
lib/
  main.dart                    point d'entrée
  app/                         assemblage : app, routeur, providers globaux
  core/
    config/                    configuration injectée à la compilation
    permissions/               façade sur les autorisations système
    theme/                     palette, typographie, thème
    widgets/                   composants graphiques réutilisables
  features/
    splash/                    écran de démarrage
    onboarding/                demande d'autorisations
    home/                      accueil provisoire (phase 1)
    sentrix/                   assistant : états, tête animée (+ moteur vocal, phase 6)
    navigation/   (phase 3)    position, recherche, itinéraire, guidage
    traffic/                   client du serveur de trafic, état connu/inconnu, annonces SENTRIX
    plates/       (phases 4-5) caméra, OCR, normalisation, base, correspondance, alertes
    history/      (phase 8)    journal des correspondances
    settings/     (phase 8)    réglages
test/                          tests unitaires, widgets, captures
config/                        fichiers --dart-define par environnement
```

## Configuration et environnements

`AppConfig.fromEnvironment()` lit les `--dart-define` produits par
`--dart-define-from-file=config/<env>.env`. Trois environnements : `dev`, `test`, `prod`.
Les valeurs par défaut permettent de lancer l'application sans fichier.

## Chaîne de lecture des plaques (cible phases 4-5)

```
Caméra (flux YUV, ~30 i/s)
  └─ limiteur de fréquence adaptatif (≈ 4-8 analyses/s selon charge et température)
      └─ filtre de netteté (variance du laplacien) → images floues rejetées
          └─ OCR ML Kit (sur l'appareil) → blocs de texte + boîtes
              └─ extraction de candidats par format (SIV AA-123-AA, FNI…)
                  └─ normalisation (majuscules, confusions O/0, I/1, B/8…)
                      └─ vote multi-images (N lectures concordantes, fenêtre glissante)
                          └─ correspondance exacte avec la base SQLite chiffrée
                              └─ alerte (anti-répétition) + journal
```

Les images ne quittent pas le téléphone ; seules les plaques **correspondant à la liste**
sont conservées (voir `PRIVACY.md`).

## Cohabitation des modules (cible phase 7)

- L'OCR s'exécute hors du thread d'interface (le plugin ML Kit traite en natif) ; une seule
  analyse en vol à la fois, les images arrivant pendant l'analyse sont abandonnées.
- File d'annonces vocales à priorité (`core/audio/voice_queue.dart`) : guidage > alerte > réponse
  SENTRIX ; jamais deux voix simultanées. Une consigne interrompt une réponse SENTRIX ; une alerte
  interrompue est répétée ; seule la consigne la plus récente reste en attente ; une annonce en
  attente depuis plus de 12 s est abandonnée.
- Au retour au premier plan (appel terminé, réglages système), les autorisations sont relues et le
  GPS est relancé s'il avait échoué.
- La caméra est arrêtée quand l'application passe en arrière-plan (contrainte iOS et Android) ;
  le guidage GPS peut continuer.

## CI

`.github/workflows/ci.yml` : `quality` (analyse, tests, captures) puis `android` (APK) et
`ios` (build non signé) en parallèle. Les journaux et captures de chaque job sont aussi
publiés sur la branche `ci-logs/<job>`.
