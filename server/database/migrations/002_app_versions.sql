-- Contrôle des versions des applications (1.7) : journal des tentatives
-- d'utilisation d'une version obsolète ou bloquée, et versions en
-- circulation (compte quotidien, sans identifiant).
CREATE TABLE app_version_events (
  id          bigserial PRIMARY KEY,
  at          timestamptz NOT NULL DEFAULT now(),
  app         text NOT NULL CHECK (app IN ('gps', 'admin-manager', 'server-control')),
  platform    text NOT NULL CHECK (char_length(platform) BETWEEN 1 AND 16),
  version     text NOT NULL CHECK (char_length(version) BETWEEN 1 AND 32),
  build       integer,
  status      text NOT NULL CHECK (status IN ('outdated', 'blocked')),
  required    text,
  source      text NOT NULL DEFAULT 'app' CHECK (source IN ('app', 'traffic', 'admin')),
  user_id     uuid REFERENCES users (id) ON DELETE SET NULL,
  admin_id    uuid REFERENCES admin_accounts (id) ON DELETE SET NULL,
  model       text CHECK (char_length(model) <= 80),
  os          text CHECK (char_length(os) <= 80),
  ip_prefix   text,
  country     text
);
CREATE INDEX app_version_events_at_idx ON app_version_events (at DESC);

CREATE TABLE app_version_daily (
  day       date NOT NULL,
  app       text NOT NULL,
  platform  text NOT NULL,
  version   text NOT NULL,
  build     integer NOT NULL DEFAULT 0,
  checks    integer NOT NULL DEFAULT 0,
  PRIMARY KEY (day, app, platform, version, build)
);

INSERT INTO settings (key, value) VALUES
  ('app.blocked', 'false'),
  ('app.block_message', '"VIGIROAD est temporairement suspendu. Réessayez plus tard."'),
  ('app.min_build', '0'),
  ('app.force_latest', 'true'),
  ('retention.version_events_days', '90')
ON CONFLICT (key) DO NOTHING;
