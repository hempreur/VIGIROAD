# Mot d'activation « Sentrix »

SENTRIX peut s'activer en disant « Sentrix » sur l'écran de navigation (Réglages → SENTRIX →
« Mot d'activation »). Désactivé par défaut.

## Fonctionnement

- Moteur libre **openWakeWord** (Apache 2.0) : melspectrogramme et plongements de parole
  (`assets/wakeword/melspectrogram.onnx`, `embedding_model.onnx`), puis un petit classifieur
  VIGIROAD (`sentrix.onnx`) sur 1,28 s d'audio, toutes les 80 ms.
- **Tout est calculé sur le téléphone**, rien n'est envoyé. Le micro n'écoute que sur l'écran de
  navigation, application au premier plan, option activée ; il se met en pause pendant que SENTRIX
  écoute une commande ou parle, et une détection pendant une annonce vocale de l'application est
  ignorée.
- Décision : score ≥ 0,9995 sur **3 blocs consécutifs** de 80 ms, puis 2 s de garde
  (`assets/wakeword/sentrix.json`).

## Mesures (données jamais vues à l'entraînement)

| Mesure | Résultat | Objectif |
|---|---|---|
| Détection des « Sentrix » du propriétaire | **90 %** (47/52 : 13 enregistrements mis de côté × 4 positions et bruits) | — |
| Fausses activations, parole française (MLS test, 8 h) | **0,12 / h** | ≤ 0,5 |
| Fausses activations, parole, musique, bruit (validation openWakeWord, 10,7 h) | **0,19 / h** | ≤ 0,5 |
| Détection calculée en flux (comme sur le téléphone) | 90 % (identique) | — |

L'échantillon de la voix du propriétaire est petit (13 enregistrements de test) : le taux réel
est à confirmer à l'usage. Le modèle est adapté à **la voix du propriétaire** ; une autre personne
sera moins bien reconnue.

## Historique

1. Voix de synthèse seules (≈ 130 voix Piper françaises) : 87 % de détection mais 14 fausses
   activations par heure ; réglé pour ≤ 0,5/h, seulement ≈ 40 % de détection. Non intégré.
2. Avec 50 « Sentrix » enregistrés par le propriétaire (écran « Entraîner Sentrix avec ma voix ») :
   résultats ci-dessus. 9 enregistrements au début coupé ont été écartés (corrigé depuis :
   l'invite « Parlez maintenant » attend que le micro enregistre réellement).

## Réentraîner

Les enregistrements de voix ne sont **jamais versionnés** (`.gitignore`). Avec l'archive exportée
par l'application et les caractéristiques calculées par la CI (`wakeword.yml`, pré-release
`wakeword-data`) :

```bash
cd tools/wakeword
python focus.py sentrix-features.npz vigiroad_sentrix_voix.zip work/   # variantes et grille seuil × confirmation
python parity.py - vigiroad_sentrix_voix.zip work/                    # parité calcul en flux / en une fois
```
