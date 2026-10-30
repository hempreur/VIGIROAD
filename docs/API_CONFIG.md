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

Les sources OpenStreetMap ne fournissent **pas** de trafic en temps réel. Conformément à la règle de
transparence, l'application affiche « Trafic indisponible » plutôt que des couleurs inventées.
Le module `traffic` exposera une interface `TrafficProvider` pour brancher ultérieurement un
fournisseur (TomTom Traffic, HERE, Mapbox) ; ces services sont payants au-delà d'un quota gratuit
et demandent une clé, à placer dans `config/<env>.local.env` (jamais commitée).

## Ajouter une clé secrète

1. Créer `config/prod.local.env` (ignoré par git) avec la variable.
2. Compiler avec `--dart-define-from-file=config/prod.local.env`.
3. En CI, stocker la valeur dans *Settings → Secrets and variables → Actions* et générer le
   fichier au moment du build.

Une clé embarquée dans une application mobile reste extractible : préférer des clés restreintes
(par identifiant d'application) ou un proxy serveur.
