-- Blocage d'un appareil précis (1.7.1). L'application envoie un identifiant
-- d'installation aléatoire (aucun identifiant matériel) ; seule son empreinte
-- SHA-256 est conservée.
ALTER TABLE app_version_events ADD COLUMN install_hash text CHECK (char_length(install_hash) = 64);
CREATE INDEX app_version_events_install_idx ON app_version_events (install_hash);

CREATE TABLE blocked_installs (
  install_hash  text PRIMARY KEY CHECK (char_length(install_hash) = 64),
  reason        text CHECK (char_length(reason) <= 300),
  platform      text,
  model         text,
  version       text,
  blocked_at    timestamptz NOT NULL DEFAULT now(),
  blocked_by    uuid REFERENCES admin_accounts (id) ON DELETE SET NULL
);
