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
