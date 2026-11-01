-- VIGIROAD — base centrale (comptes, appareils, sessions, administration,
-- supervision, sauvegardes). Appliquée automatiquement par l'API
-- d'administration au démarrage (table schema_migrations).
--
-- Principes :
--   * aucun mot de passe en clair (Argon2id), aucun jeton en clair (SHA-256) ;
--   * aucune adresse IP complète conservée (préfixe /24 ou /48 seulement) ;
--   * la suppression d'un compte supprime en cascade toutes ses données ;
--   * localisation désactivée par défaut, uniquement avec consentement.

CREATE TABLE users (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pseudonym             text NOT NULL CHECK (char_length(pseudonym) BETWEEN 3 AND 32),
  display_name          text CHECK (char_length(display_name) <= 80),
  email                 text CHECK (email IS NULL OR (char_length(email) <= 254 AND email LIKE '%_@_%')),
  password_hash         text NOT NULL,
  status                text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
  region_consent        boolean NOT NULL DEFAULT false,
  location_consent      boolean NOT NULL DEFAULT false,
  country               text,
  app_version           text,
  total_active_seconds  bigint NOT NULL DEFAULT 0,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  last_login_at         timestamptz,
  last_seen_at          timestamptz
);
CREATE UNIQUE INDEX users_pseudonym_key ON users (lower(pseudonym));
CREATE UNIQUE INDEX users_email_key ON users (lower(email)) WHERE email IS NOT NULL;
CREATE INDEX users_created_idx ON users (created_at);
CREATE INDEX users_last_seen_idx ON users (last_seen_at);

-- Appareil = installation de l'application (identifiant aléatoire généré par
-- l'application, révocable et renouvelable ; aucun identifiant matériel).
CREATE TABLE devices (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  installation_id  text NOT NULL CHECK (char_length(installation_id) BETWEEN 16 AND 64),
  brand            text CHECK (char_length(brand) <= 64),
  model            text CHECK (char_length(model) <= 64),
  os               text CHECK (os IN ('android', 'ios', 'other')),
  os_version       text CHECK (char_length(os_version) <= 32),
  app_version      text CHECK (char_length(app_version) <= 32),
  country          text,
  first_seen_at    timestamptz NOT NULL DEFAULT now(),
  last_seen_at     timestamptz NOT NULL DEFAULT now(),
  revoked_at       timestamptz
);
CREATE UNIQUE INDEX devices_installation_key ON devices (installation_id) WHERE revoked_at IS NULL;
CREATE INDEX devices_user_idx ON devices (user_id);
CREATE INDEX devices_last_seen_idx ON devices (last_seen_at);

CREATE TABLE sessions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  device_id       uuid REFERENCES devices (id) ON DELETE SET NULL,
  token_hash      text NOT NULL UNIQUE,
  started_at      timestamptz NOT NULL DEFAULT now(),
  last_seen_at    timestamptz NOT NULL DEFAULT now(),
  ended_at        timestamptz,
  end_reason      text CHECK (end_reason IN ('logout', 'revoked', 'expired', 'disabled', 'password_reset', 'device_revoked')),
  active_seconds  integer NOT NULL DEFAULT 0,
  heartbeats      integer NOT NULL DEFAULT 0,
  app_version     text,
  country         text,
  ip_prefix       text
);
CREATE INDEX sessions_user_idx ON sessions (user_id, started_at DESC);
CREATE INDEX sessions_device_idx ON sessions (device_id);
CREATE INDEX sessions_open_idx ON sessions (last_seen_at) WHERE ended_at IS NULL;
CREATE INDEX sessions_started_idx ON sessions (started_at);

CREATE TABLE admin_accounts (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email            text NOT NULL CHECK (email LIKE '%_@_%'),
  display_name     text NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 80),
  password_hash    text NOT NULL,
  role             text NOT NULL CHECK (role IN ('owner', 'admin', 'operator', 'viewer')),
  status           text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
  -- Secret TOTP chiffré (AES-256-GCM, clé hors base).
  totp_secret_enc  text,
  totp_confirmed   boolean NOT NULL DEFAULT false,
  totp_last_step   bigint NOT NULL DEFAULT 0,
  failed_attempts  integer NOT NULL DEFAULT 0,
  locked_until     timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  created_by       uuid REFERENCES admin_accounts (id) ON DELETE SET NULL,
  last_login_at    timestamptz
);
CREATE UNIQUE INDEX admin_accounts_email_key ON admin_accounts (lower(email));

CREATE TABLE admin_sessions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id      uuid NOT NULL REFERENCES admin_accounts (id) ON DELETE CASCADE,
  token_hash    text NOT NULL UNIQUE,
  client        text,
  ip_prefix     text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  last_seen_at  timestamptz NOT NULL DEFAULT now(),
  expires_at    timestamptz NOT NULL,
  revoked_at    timestamptz
);
CREATE INDEX admin_sessions_admin_idx ON admin_sessions (admin_id);

-- Connexions réussies et échouées (utilisateurs et administrateurs).
CREATE TABLE login_events (
  id          bigserial PRIMARY KEY,
  at          timestamptz NOT NULL DEFAULT now(),
  kind        text NOT NULL CHECK (kind IN ('user', 'admin')),
  user_id     uuid REFERENCES users (id) ON DELETE CASCADE,
  admin_id    uuid REFERENCES admin_accounts (id) ON DELETE CASCADE,
  device_id   uuid REFERENCES devices (id) ON DELETE SET NULL,
  success     boolean NOT NULL,
  reason      text NOT NULL,
  ip_prefix   text,
  country     text
);
CREATE INDEX login_events_at_idx ON login_events (at DESC);
CREATE INDEX login_events_user_idx ON login_events (user_id, at DESC);
CREATE INDEX login_events_failed_idx ON login_events (at DESC) WHERE NOT success;

-- Temps d'utilisation réel (battements de cœur), agrégé par jour.
CREATE TABLE usage_statistics (
  day             date NOT NULL,
  user_id         uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  active_seconds  integer NOT NULL DEFAULT 0,
  sessions        integer NOT NULL DEFAULT 0,
  heartbeats      integer NOT NULL DEFAULT 0,
  PRIMARY KEY (day, user_id)
);
CREATE INDEX usage_statistics_user_idx ON usage_statistics (user_id, day);

-- Même mesure par heure (statistiques sur 24 h), conservée 35 jours.
CREATE TABLE usage_hourly (
  hour            timestamptz NOT NULL,
  user_id         uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  active_seconds  integer NOT NULL DEFAULT 0,
  PRIMARY KEY (hour, user_id)
);

-- Positions approximatives (arrondies à ~5 km), uniquement avec le
-- consentement explicite de l'utilisateur ; durée de conservation réglable.
CREATE TABLE location_history (
  id        bigserial PRIMARY KEY,
  user_id   uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  at        timestamptz NOT NULL DEFAULT now(),
  lat       numeric(6, 2) NOT NULL CHECK (lat BETWEEN -90 AND 90),
  lng       numeric(6, 2) NOT NULL CHECK (lng BETWEEN -180 AND 180),
  country   text
);
CREATE INDEX location_history_user_idx ON location_history (user_id, at DESC);
CREATE INDEX location_history_at_idx ON location_history (at);

-- Codes de réinitialisation à usage unique (créés par un administrateur).
CREATE TABLE password_resets (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  code_hash   text NOT NULL,
  created_by  uuid REFERENCES admin_accounts (id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  expires_at  timestamptz NOT NULL,
  used_at     timestamptz
);
CREATE INDEX password_resets_user_idx ON password_resets (user_id);

CREATE TABLE admin_audit_logs (
  id           bigserial PRIMARY KEY,
  at           timestamptz NOT NULL DEFAULT now(),
  admin_id     uuid REFERENCES admin_accounts (id) ON DELETE SET NULL,
  admin_email  text,
  action       text NOT NULL,
  target_type  text,
  target_id    text,
  success      boolean NOT NULL DEFAULT true,
  details      jsonb NOT NULL DEFAULT '{}'::jsonb,
  ip_prefix    text
);
CREATE INDEX admin_audit_logs_at_idx ON admin_audit_logs (at DESC);
CREATE INDEX admin_audit_logs_admin_idx ON admin_audit_logs (admin_id, at DESC);

-- Mesures du VPS (une par minute).
CREATE TABLE server_metrics (
  at            timestamptz PRIMARY KEY,
  cpu_percent   real,
  load1         real,
  load5         real,
  load15        real,
  mem_total     bigint,
  mem_used      bigint,
  mem_available bigint,
  disk_total    bigint,
  disk_used     bigint,
  net_rx_bps    bigint,
  net_tx_bps    bigint,
  temp_c        real,
  traffic_ok    boolean,
  traffic_latency_ms integer
);

-- État de chaque flux routier (toutes les 5 minutes).
CREATE TABLE traffic_source_metrics (
  at             timestamptz NOT NULL,
  source_id      text NOT NULL,
  healthy        boolean NOT NULL,
  events         integer,
  last_success   timestamptz,
  last_error     text,
  PRIMARY KEY (source_id, at)
);
CREATE INDEX traffic_source_metrics_at_idx ON traffic_source_metrics (at);

-- Requêtes entrantes agrégées par minute et par service.
CREATE TABLE request_metrics (
  minute     timestamptz NOT NULL,
  service    text NOT NULL,
  route      text NOT NULL,
  count      integer NOT NULL,
  errors     integer NOT NULL,
  p50_ms     real,
  p95_ms     real,
  PRIMARY KEY (service, route, minute)
);
CREATE INDEX request_metrics_minute_idx ON request_metrics (minute);

CREATE TABLE backup_jobs (
  id            bigserial PRIMARY KEY,
  kind          text NOT NULL CHECK (kind IN ('scheduled', 'manual', 'restore_test')),
  status        text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'success', 'failed')),
  requested_by  uuid REFERENCES admin_accounts (id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  started_at    timestamptz,
  finished_at   timestamptz,
  file_name     text,
  size_bytes    bigint,
  sha256        text,
  message       text
);
CREATE INDEX backup_jobs_created_idx ON backup_jobs (created_at DESC);
CREATE INDEX backup_jobs_pending_idx ON backup_jobs (created_at) WHERE status = 'pending';

-- Réglages modifiables depuis les applications d'administration.
CREATE TABLE settings (
  key         text PRIMARY KEY,
  value       jsonb NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  uuid REFERENCES admin_accounts (id) ON DELETE SET NULL
);
INSERT INTO settings (key, value) VALUES
  ('retention.login_events_days', '180'),
  ('retention.sessions_days', '365'),
  ('retention.location_days', '30'),
  ('retention.metrics_days', '30'),
  ('retention.audit_days', '730'),
  ('sessions.idle_expiry_days', '30'),
  ('geo.enabled', 'true'),
  ('backups.keep', '14');
