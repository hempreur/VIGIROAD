# VigiRoadTrafficAggregator

Service qui collecte les perturbations routières des sources officielles, les convertit vers un
modèle unique, fusionne les doublons, écarte les données obsolètes et les sert à l'application
VIGIROAD par une API sécurisée. Aucune circulation n'est simulée.

## Lancer en local

```bash
cd server
dart pub get
VR_API_KEYS="une-cle-dau-moins-16-caracteres" dart run bin/server.dart
curl -H "X-Api-Key: une-cle-dau-moins-16-caracteres" "http://localhost:8080/v1/events?bbox=1.5,48.3,3.2,49.2"
```

## Installation sur un VPS (Debian / Ubuntu)

Une commande installe Docker, le serveur, Caddy (HTTPS Let's Encrypt automatique), le pare-feu, et
génère la clé d'accès :

```bash
curl -fsSL https://raw.githubusercontent.com/hempreur/VIGIROAD/main/server/deploy/install.sh -o install.sh
sudo bash install.sh                       # adresse https://<ip>.sslip.io (aucun nom de domaine requis)
sudo bash install.sh trafic.mondomaine.fr  # ou votre domaine, DNS déjà pointé vers le VPS
```

Le script affiche à la fin les deux secrets GitHub à créer (`VR_TRAFFIC_API_URL`,
`VR_TRAFFIC_API_KEY`). Relancer la même commande met à jour le serveur (clé et réglages conservés
dans `/opt/vigiroad/server/deploy/.env`, où l'on ajoute aussi les clés TfL, 511…). Journaux :
`cd /opt/vigiroad/server/deploy && docker compose logs -f`.

## Image Docker (tout hébergeur)

```bash
# depuis la racine du dépôt
docker build -f server/Dockerfile -t vigiroad-traffic .
docker run -p 8080:8080 -e VR_API_KEYS="…" vigiroad-traffic
```

L'image est autonome (binaire compilé, ~15 Mo) et fonctionne sur Cloud Run, un VPS, Fly.io,
Render… Le HTTPS est assuré par l'hébergeur ou un proxy (Caddy, nginx).

## Configuration

| Variable | Obligatoire | Rôle |
|---|---|---|
| `VR_API_KEYS` | oui | Clés autorisées (≥ 16 caractères), séparées par des virgules |
| `PORT` | non | Port d'écoute (8080) |
| `VR_TFL_APP_KEY` | non | Active Transport for London |
| `VR_511_SFBAY_KEY` | non | Active 511 SF Bay (WZDx) |
| `VR_AZ511_KEY` | non | Active AZ511 |
| `VR_WAZE_FEED_URL` | non | Active Waze for Cities (accès partenaire obtenu uniquement) |
| `VR_DATEX2_FEEDS` | non | Flux DATEX II 2.x supplémentaires : `id\|PAYS\|url\|mention\|licence;…` |
| `VR_DISABLE_SOURCES` | non | Identifiants de sources à désactiver |
| `VR_WAZE_BBOX` | non | Zone de l'accord Waze (`minLng,minLat,maxLng,maxLat`) |
| `VR_OVERPASS_URL` | non | Instance Overpass des limitations de vitesse (`overpass-api.de` par défaut) |
| `VR_SPEEDLIMITS` | non | `off` pour désactiver les limitations de vitesse |

## API

Toutes les routes `/v1/*` exigent l'en-tête `X-Api-Key`. Limite : 120 requêtes/minute par clé.

| Route | Description |
|---|---|
| `GET /health` | État, nombre de sources, couverture (sans clé) |
| `GET /v1/sources` | Sources, licences, mentions, santé, basculement |
| `GET /v1/events?bbox=minLng,minLat,maxLng,maxLat` | Événements d'une zone (≤ 250 000 km²) |
| `POST /v1/speedlimits` | `{"route": [[lng,lat],…]}` (≤ 60 km) → `{"limits": [50, null, …], "complete": true}`, une valeur par segment, `null` = inconnue |
| `GET /v1/reports?bbox=minLng,minLat,maxLng,maxLat` | signalements « Chicken » actifs de la zone (2 h après le dernier signalement au même endroit) |
| `POST /v1/reports` | `{"position": [lng,lat], "heading": 87.5 \| null, "side": "mine" \| "opposite"}` → `201 {"report": …}` ; même endroit (200 m) et même sens = confirmation ; 1/min et 12/h par connexion |
| `POST /v1/events/route` | `{"route": [[lng,lat],…], "bufferMeters": 150}` → événements sur l'itinéraire, avec distance depuis le départ |

Réponse type :

```json
{
  "generatedAt": "2026-10-30T21:00:00Z",
  "coverage": ["FR"],
  "attributions": [{"source": "fr-bison-fute", "text": "Information fournie par Bison Futé", "url": "…"}],
  "events": [{
    "id": "fr-bison-fute:…", "type": "accident", "position": [2.2475, 48.5869],
    "road": "N20", "direction": "positive", "severity": "high",
    "startTime": "…", "updatedAt": "…", "fetchedAt": "…",
    "sources": ["fr-bison-fute"], "description": "…", "country": "FR"
  }]
}
```

`area.known` indique si une source à jour couvre la zone demandée (emprise de chaque source) :
sinon l'état est **inconnu**. `coverage` liste les pays disposant de données fraîches.

Sources, licences et fréquences : [`SOURCES.md`](SOURCES.md).
