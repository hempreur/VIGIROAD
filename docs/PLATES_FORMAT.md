# Base de plaques : formats d'import et stockage

## Fichier CSV

```csv
plate,country,category,priority,note
AA123BB,FR,Surveillance,high,
CC456DD,FR,Surveillance,medium,Utilitaire blanc
EE789FF,FR,Surveillance,high,
```

*(valeurs fictives)*

| Colonne | Obligatoire | Noms acceptés | Valeurs |
|---|---|---|---|
| plaque | oui | `plate`, `plaque`, `immatriculation`, `registration`, `numero` | `AA123BB`, `AA-123-BB`, `aa 123 bb`… (tirets, espaces, casse ignorés) |
| pays | non (FR) | `country`, `pays` | code ISO 3166-1 alpha-2 |
| catégorie | non (« Surveillance ») | `category`, `categorie`, `catégorie`, `type` | texte libre |
| priorité | non (medium) | `priority`, `priorite`, `priorité` | `low`/`basse`/`1`, `medium`/`moyenne`/`2`, `high`/`haute`/`3` |
| note | non | `note`, `commentaire`, `comment` | texte libre |

- Séparateur détecté automatiquement : virgule, point-virgule ou tabulation (exports Excel FR).
- Guillemets RFC 4180 pris en charge (`"Vol, signalé"`, `"dit ""rouge"""`), UTF-8 avec ou sans BOM.
- Sans ligne d'en-tête, les colonnes sont lues dans l'ordre `plate,country,category,priority,note`.

## Fichier JSON

```json
[
  {"plate": "AA-123-BB", "category": "Surveillance", "priority": "high"},
  {"plate": "CC456DD"}
]
```

Également accepté : `{"plates": [...]}` ou `{"entries": [...]}`, et une liste de chaînes
`["AA123BB", "CC456DD"]`. Les noms de champs sont ceux du tableau ci-dessus.

## Validation

- Plaques françaises (`country` = FR) : format SIV `AA-123-AA` (lettres I, O, U exclues, « SS »
  interdit, bloc 000 interdit) ou ancien FNI `1234 AB 75`. Toute autre forme est rejetée.
- Autres pays : 2 à 12 caractères alphanumériques.
- Doublons dans un même fichier : seule la première occurrence est gardée, les autres sont comptées.
- Les lignes invalides sont listées (numéro de ligne + raison) avant confirmation ; les lignes
  valides peuvent être importées sans elles.

## Modes d'import

| Mode | Effet |
|---|---|
| **Ajouter** | Ajoute les nouvelles plaques et met à jour celles qui existent ; le reste est conservé. |
| **Remplacer les imports** | Supprime d'abord les plaques issues d'imports précédents (les saisies manuelles et synchronisées sont conservées). |

## Synchronisation distante (optionnelle)

Si `VR_PLATES_SYNC_URL` est configurée (HTTPS obligatoire), le bouton « Synchroniser » télécharge
un fichier CSV ou JSON au même format et remplace les plaques issues de la synchronisation précédente.

## Stockage

- SQLite chiffré par SQLCipher (AES-256), fichier `vigiroad.db` dans l'espace privé de l'application.
- Clé de 256 bits générée au premier lancement, stockée dans le Keystore Android / Keychain iOS.
- Table `watchlist` : `plate` (clé, forme normalisée), `country`, `category`, `priority`, `note`,
  `source` (manual / import / sync), `updated_at`.
- Table `detections` (historique) : plaque, catégorie, priorité, confiance, date, position GPS.
  Seules les **correspondances** y sont écrites.

## Correspondance

Comparaison **exacte** sur la forme normalisée, via un index en mémoire (temps constant même avec
des dizaines de milliers de plaques). Une alerte n'est déclenchée que pour une lecture confirmée
sur plusieurs images (voir `OCR.md`) avec une confiance ≥ 0,8 ; la même plaque ne redéclenche pas
d'alerte avant 5 minutes.
