# Données personnelles et cadre légal

> Ce document décrit les choix techniques de protection des données. Il ne constitue pas un avis
> juridique ; faire valider l'usage prévu par un juriste ou le DPO de l'organisation exploitante.

## Pourquoi c'est important

En France et dans l'Union européenne, un numéro d'immatriculation est une **donnée personnelle**
(il permet d'identifier indirectement le titulaire du véhicule). La lecture automatisée de plaques
(LAPI) et leur comparaison avec une liste relèvent donc du RGPD. La CNIL encadre strictement ces
dispositifs : ils sont réservés à des finalités et à des acteurs précis (forces de l'ordre, douanes,
gestion d'accès à un site privé, etc.), avec une analyse d'impact et des durées de conservation
limitées. L'exploitant de VIGIROAD doit disposer d'une base légale pour la liste qu'il charge et
pour l'usage qu'il fait des alertes.

## Mesures intégrées dans l'application (privacy by design)

| Mesure | Mise en œuvre |
|---|---|
| Analyse locale | Les images de la caméra sont traitées sur le téléphone et ne sont jamais transmises. |
| Minimisation | Les plaques lues qui **ne correspondent pas** à la liste sont oubliées immédiatement : ni stockées, ni journalisées. |
| Chiffrement | Base SQLite chiffrée (SQLCipher), clé générée aléatoirement et conservée dans le trousseau du système (Keystore / Keychain). |
| Conservation limitée | Durée de conservation de l'historique paramétrable, purge automatique, suppression totale possible. |
| Pas de photo par défaut | La vignette d'un véhicule en correspondance n'est enregistrée que si le réglage est activé. |
| Transparence | Écran d'autorisations expliquant l'usage de chaque capteur ; écoute vocale uniquement à la demande. |
| Pas de pistage | Aucun service d'analyse d'audience ni publicité. |

## Responsabilités de l'exploitant

- Définir la finalité et la base légale du traitement.
- Tenir le registre des traitements et, si nécessaire, réaliser l'analyse d'impact (AIPD).
- Fixer la durée de conservation dans les réglages de l'application.
- Informer les personnes concernées selon les obligations applicables.

## Enregistrements de voix (« Entraîner Sentrix », 1.1.1)

Facultatifs. Les extraits (« Sentrix », lecture d'un texte, bruit de la voiture) sont enregistrés
uniquement quand l'utilisateur appuie sur « Enregistrer », stockés dans l'espace privé de
l'application, jamais envoyés automatiquement. L'export (.zip) est déclenché par l'utilisateur, qui
choisit où l'enregistrer ; « Tout effacer » supprime les enregistrements du téléphone.

## Vérification des mises à jour (1.3)

Au démarrage puis toutes les 6 heures, l'application télécharge le fichier de version public de la
dernière release sur GitHub (github.com). Aucune donnée personnelle n'est envoyée ; comme pour tout
téléchargement, GitHub voit l'adresse IP du téléphone.

## Compte VIGIROAD facultatif (1.4)

- L'application fonctionne entièrement **sans compte**. Le compte sert à retrouver ses appareils
  et ses sessions ; il permet à l'exploitant de suivre l'utilisation du service.
- Données : pseudonyme, e-mail et nom **facultatifs**, mot de passe haché (Argon2id), appareil
  (marque, modèle, version du système, identifiant d'installation aléatoire et renouvelable — aucun
  identifiant matériel), sessions et temps d'utilisation (battements de cœur toutes les 60 s quand
  l'application est ouverte), réseau de connexion réduit (/24).
- **Région** (pays d'après la connexion) et **position approximative** (≈ 5 km) : désactivées par
  défaut, uniquement avec l'accord de l'utilisateur ; le retrait de l'accord efface ces données.
- Jamais envoyé : images de caméra, plaques lues, enregistrements vocaux.
- Droits : export de toutes ses données et suppression définitive du compte depuis l'application.
- Conservation et sécurité : voir [docs/admin/SECURITE.md](admin/SECURITE.md).
