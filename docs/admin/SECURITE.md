# Sécurité et données personnelles

## Accès administrateur

- Mot de passe (12 caractères minimum) haché en **Argon2id** (19 Mio, 2 itérations, sel aléatoire).
- **Double authentification TOTP obligatoire** (RFC 6238) ; chaque code ne sert qu'une fois ;
  secret chiffré en base (AES-256-GCM, clé `VR_ADMIN_SECRET` hors base).
- Verrouillage 15 min après 5 échecs ; limitation par adresse ; réponses identiques pour un compte
  inconnu (pas d'énumération).
- Session de 12 h au plus, fermée après 30 min sans requête ; les applications se verrouillent
  après 30 min sans action de l'utilisateur.
- Rôles vérifiés **côté serveur** pour chaque requête : Propriétaire, Administrateur,
  Opérateur serveur, Lecture seule. Il reste toujours au moins un propriétaire actif.
- **Journal d'audit** : connexions, actions sur les comptes, Docker, sauvegardes, réglages,
  exports et refus de droits (conservé 2 ans par défaut).

## Transport et exposition

- HTTPS uniquement (Caddy, Let's Encrypt, HSTS). Les applications refusent le HTTP en clair,
  sauf vers l'ordinateur local (tunnel SSH).
- Seuls les ports 22, 80 et 443 sont ouverts. PostgreSQL, l'agent et le socket Docker ne sont
  joignables que sur le réseau Docker interne (sans accès Internet).
- Le bureau à distance du VPS écoute sur 127.0.0.1 (tunnel SSH obligatoire).

## Comptes de l'application mobile

- Mot de passe Argon2id ; jeton de session aléatoire (256 bits), seule son empreinte SHA-256 est
  conservée ; stockage chiffré sur le téléphone (Keystore / Trousseau).
- Inscription et connexion réservées à l'application (clé applicative) et limitées en débit.
- **Aucune image de caméra, plaque lue ni voix** n'est envoyée pour cette fonctionnalité.
- Identifiant d'appareil : aléatoire, propre à VIGIROAD, renouvelable ; aucun identifiant matériel.
- Adresses IP : seul le réseau (/24, /48) est conservé, jamais l'adresse complète.
- Pays : seulement avec le consentement « région approximative » (désactivé par défaut).
- Position : seulement avec le consentement « position approximative » (désactivé par défaut),
  arrondie à ~5 km, au plus toutes les 15 min, conservée 30 jours (réglable).
- Retrait d'un consentement = effacement immédiat des données correspondantes.
- Export de toutes ses données et suppression définitive du compte depuis l'application ;
  un administrateur peut aussi exporter ou supprimer (confirmation par saisie du pseudonyme).

## Durées de conservation (réglables dans Paramètres)

| Donnée | Par défaut |
|---|---|
| Historique des connexions | 180 jours |
| Sessions terminées | 365 jours |
| Positions approximatives | 30 jours |
| Mesures du serveur et des flux | 30 jours |
| Journal d'audit | 730 jours |
| Expiration d'une session inactive | 30 jours |
| Sauvegardes | 14 dernières |

La conservation est appliquée automatiquement chaque heure.
