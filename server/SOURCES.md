# Sources de trafic — droits, contraintes et fréquences

Chaque connecteur n'est activé qu'après vérification de ces points. « Vérifié » signifie que le
format a été confirmé sur le flux réel, pas seulement sur la documentation.

| Source | Pays | Format | Accès | Licence / conditions | Fréquence retenue | Vérifié |
|---|---|---|---|---|---|---|
| **Bison Futé** (Tipi, réseau routier national non concédé) | FR | DATEX II 2.x (SOAP) | Public, sans inscription | Licence de réutilisation des données dynamiques Bison Futé ; données statiques en Licence Ouverte 2.0 | 2 min | ✅ 30/10/2026 |
| **transport.data.gouv.fr** (secours Bison Futé) | FR | DATEX II 2.x | Public | Licence Ouverte 2.0 | 5 min, seulement si Bison Futé échoue 3 fois | — |
| **Points d'accès nationaux NAPCORE** (configurables) | UE | DATEX II 2.x | Selon le pays (souvent public ou inscription gratuite) | Selon le pays : à renseigner pour chaque flux ajouté | 5 min | à faire par flux |
| **Transport for London** (Road Disruptions) | GB | JSON | Clé gratuite (`app_key`) | Conditions TfL Open Data ; mention « Powered by TfL Open Data » | 2 min | ❌ schéma à confirmer avec une clé |
| **511 SF Bay** (WZDx) | US | GeoJSON WZDx | Jeton gratuit | Conditions 511 SF Bay Open Data ; 60 requêtes/heure par défaut | 2 min (30/h) | ❌ à confirmer avec un jeton |
| **AZ511** (511 API v2) | US | JSON | Clé développeur gratuite | Conditions AZ511 ; 10 appels/minute | 2 min | ❌ à confirmer avec une clé |
| **Waze for Cities** | Mondial | JSON partenaire | **Programme partenaire uniquement** | Accord de partenariat Waze ; usage strictement selon l'accord | 2 min | ❌ pas d'accès |

## Obligations reprises dans l'application

- **Bison Futé** : mention « Information fournie par Bison Futé » sans laisser croire à un soutien
  officiel ; affichage de la date de dernière mise à jour ; données non altérées (le format peut
  changer, pas le contenu) ; priorité aux déviations officielles. L'API renvoie la mention et
  chaque événement porte sa date de mise à jour source (`updatedAt`) et de collecte (`fetchedAt`).
- **TfL** : mention « Powered by TfL Open Data ».
- **Toutes sources** : la mention de chaque source utilisée est renvoyée avec les événements
  (`attributions`) et affichée par l'application.

## Fréquences et basculement

- Une source n'est jamais interrogée plus souvent que sa fréquence retenue (`minInterval`).
- En cas d'échec : nouvel essai avec attente doublée (2, 4, 8, 16 min…, au plus 30 min).
- Après 3 échecs consécutifs, la source de secours de la même zone prend le relais ; elle est
  abandonnée dès que la source principale répond de nouveau.
- Si une zone n'a plus de collecte réussie depuis 30 min, ses événements ne sont plus diffusés et
  elle sort de la couverture : l'application affiche l'état **inconnu**. Aucune circulation n'est
  jamais simulée.

## Ajouter un pays

- **Flux DATEX II 2.x d'un point d'accès national** : sans code, via
  `VR_DATEX2_FEEDS="id|PAYS|url|mention|licence;…"`.
- **Autre format** : écrire un connecteur (`TrafficConnector`) dans `lib/src/connectors/`, avec
  sa `SourceInfo` (licence, mention, fréquence), des tests sur un exemple réel, puis l'ajouter à
  `ServerConfig.chains()`.

## Sources étudiées, non intégrées

- **DGT (Espagne)** : DATEX II **v3** — nécessite un analyseur DATEX II 3 (différent du 2.x).
- **NDW (Pays-Bas)** : DATEX II avec codes de localisation VILD propriétaires — conversion nécessaire.
- **Highways England / Traffic Scotland** : DATEX II, inscription requise.
- **511NY** : documentation de l'API non accessible publiquement lors de l'étude.
