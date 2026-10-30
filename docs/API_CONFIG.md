# Configuration des services externes

Toutes les URL se règlent dans `config/<env>.env` (modèle : `.env.example`).
La pile retenue (MapLibre + OpenStreetMap) ne demande **aucune clé API**.

| Variable | Service par défaut | Usage | Limites à connaître |
|---|---|---|---|
| `VR_MAP_STYLE_URL` | CARTO Dark Matter | fond de carte sombre | Gratuit avec attribution ; un usage commercial à grande échelle nécessite un accord CARTO ou un fond auto-hébergé (ex. OpenMapTiles). |
| `VR_ROUTING_URL` | `router.project-osrm.org` | calcul d'itinéraire | Serveur **de démonstration** : débit limité, pas de garantie de service. En production, héberger OSRM (ou Valhalla/GraphHopper via un adaptateur). |
| `VR_GEOCODING_URL` | `photon.komoot.io` | recherche d'adresse | Usage raisonnable toléré ; en production, héberger Photon. |
| `VR_PLATES_SYNC_URL` | désactivé | synchronisation de la liste | HTTPS obligatoire. Format décrit en phase 5. |
| `VR_USER_AGENT` | `VIGIROAD/1.0 (…)` | identification | Exigé par les politiques OSM. |

## Trafic en temps réel

Le trafic vient du serveur **VigiRoadTrafficAggregator** (`server/`), qui agrège les sources
officielles (Bison Futé, points d'accès nationaux, TfL, 511…). Droits, licences et fréquences :
[`server/SOURCES.md`](../server/SOURCES.md).

| Variable | Rôle |
|---|---|
| `VR_TRAFFIC_API_URL` | Adresse HTTPS du serveur de trafic. Vide = trafic désactivé. |
| `VR_TRAFFIC_API_KEY` | Clé d'accès au serveur (une des `VR_API_KEYS` du serveur). |

En CI, ces valeurs viennent des secrets GitHub du même nom (`Settings → Secrets → Actions`) ;
sans eux l'APK affiche « Source non configurée ». La clé limite l'accès au serveur mais, embarquée
dans l'application, ne doit pas être considérée comme secrète : les clés des fournisseurs restent
sur le serveur.

Ce que l'application affiche — **jamais de trafic simulé** :

- « **État inconnu ici** » quand aucune source à jour ne couvre la zone (le serveur renvoie
  `area.known = false`) ;
- « **Aucun incident signalé** » quand une source à jour couvre la zone sans rien signaler (et non
  « fluide » : les sources décrivent des incidents, pas la vitesse de circulation) ;
- les perturbations sur la carte (couleur = gravité), le détail au toucher, la mention de chaque
  source et l'heure de mise à jour (obligations Bison Futé) ;
- après 5 minutes sans réponse du serveur, plus aucune donnée n'est affichée.

## Ajouter une clé secrète

1. Créer `config/prod.local.env` (ignoré par git) avec la variable.
2. Compiler avec `--dart-define-from-file=config/prod.local.env`.
3. En CI, stocker la valeur dans *Settings → Secrets and variables → Actions* et générer le
   fichier au moment du build.

Une clé embarquée dans une application mobile reste extractible : préférer des clés restreintes
(par identifiant d'application) ou un proxy serveur.
