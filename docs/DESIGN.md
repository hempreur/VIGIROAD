# Design system VIGIROAD

L'image `docs/reference/fiche_technique.png` est la **référence visuelle officielle**.
Ce document trace les choix qui en sont tirés ; toute nouvelle couleur ou composant doit y figurer.

## Palette (mesurée sur la référence)

Valeurs obtenues par médiane des pixels de chaque famille de teinte de l'image, pas à l'œil.

| Rôle | Jeton | Valeur |
|---|---|---|
| Fond | `VrColors.background` | `#02050A` |
| Fond relevé | `VrColors.backgroundRaised` | `#010C15` |
| Panneau | `VrColors.panel` / `panelLight` | `#07131E` / `#0E1B27` |
| Cyan lumineux | `VrColors.cyan` / `cyanBright` | `#19CFF4` / `#48E6FF` |
| Bleu électrique | `VrColors.electric` | `#066DD3` |
| Cœur d'itinéraire | `VrColors.routeCore` | `#C9FFFF` |
| Alerte | `VrColors.alert` / `alertText` | `#F6282F` / `#F8484D` |
| Trafic fluide / ralenti / bouché | `trafficFluid` / `trafficSlow` / `trafficJam` | `#4EAA33` / `#F09E1B` / `#F72119` |

## Typographie

- **Rajdhani** (700/600/500) : titres en capitales, chiffres de navigation, plaques — proche
  des intitulés condensés de la référence.
- **Inter** : textes courants, lisible à petite taille en conduite.

## Composants

| Composant | Rôle dans la référence |
|---|---|
| `GlowPanel` | cartouche de guidage, légende trafic, fenêtre OCR, encadré d'alerte (`PanelTone.alert`) |
| `VrButton` | pastilles « Commandes vocales » ; cible ≥ 52 px |
| `VrBackdrop` | fond nocturne avec halo bleu bas d'écran |
| `BrandWordmark` | titre bicolore blanc / cyan |
| `SentrixHead` | robot : casque nacré, visière à trame de points, yeux en arc, écouteurs lumineux, micro-perche |

## États de SENTRIX

| État | Rendu |
|---|---|
| Repos | yeux en arc cyan, clignement toutes les 4 s |
| Écoute | arcs + pulsation des écouteurs et du micro |
| Analyse | points qui balayent de gauche à droite |
| Réponse | arcs + onde vocale sous les yeux |
| Notification | yeux ronds rouges pulsés |
| Erreur | yeux en croix orange |

L'animation respecte le réglage système « réduire les animations ».

## Écran principal (cible phase 2) — relevé de la référence

De haut en bas sur le téléphone : cartouche de manœuvre (flèche, distance en grand, consigne,
direction) avec à droite trois boutons carrés (couches, recentrage, signalement) ; carte sombre
avec itinéraire bleu lumineux ; légende trafic à droite ; compteur de vitesse circulaire et
panneau de limitation à gauche ; marqueur de position en flèche dans un disque bleu ;
panneau « Caméra arrière » avec cadre lumineux sur la plaque détectée ; fenêtre « Lecture OCR »
avec plaque au format européen, vignette, confiance, pays, type ; encadré d'alerte rouge en bas.

## Captures de comparaison

La CI génère les captures (`test/screenshots`) à chaque push ; elles sont publiées dans
l'artefact `quality-report` et sur la branche `ci-logs/quality`.
