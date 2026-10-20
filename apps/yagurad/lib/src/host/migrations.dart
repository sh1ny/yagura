import 'database.dart';

/// Every schema migration, in order. A released migration is never edited:
/// later groups append numbered migrations (ADR 0008).
const List<Migration> allMigrations = [
  Migration(1, '''
CREATE TABLE instances (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  plugin_id TEXT NOT NULL,
  plugin_version TEXT NOT NULL,
  directory TEXT NOT NULL,
  state TEXT NOT NULL,
  state_reason TEXT NOT NULL DEFAULT '',
  warning TEXT NOT NULL DEFAULT '',
  settings_json TEXT NOT NULL,
  steam_account_id TEXT NOT NULL DEFAULT '',
  restart_policy TEXT NOT NULL DEFAULT 'on_crash',
  autostart INTEGER NOT NULL DEFAULT 1,
  last_requested_state TEXT NOT NULL DEFAULT '',
  restart_required INTEGER NOT NULL DEFAULT 0,
  settings_invalid INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  state_changed_at INTEGER NOT NULL
);

CREATE TABLE instance_ports (
  instance_id TEXT NOT NULL REFERENCES instances(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  number INTEGER NOT NULL,
  protocol TEXT NOT NULL,
  purpose TEXT NOT NULL,
  exposed INTEGER NOT NULL,
  PRIMARY KEY (instance_id, name)
);

-- Operation rows outlive their instance (design D25), so no foreign key.
CREATE TABLE operations (
  id TEXT PRIMARY KEY,
  instance_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  status TEXT NOT NULL,
  current_step TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  started_at INTEGER,
  ended_at INTEGER,
  result_reason TEXT NOT NULL DEFAULT '',
  result_message TEXT NOT NULL DEFAULT '',
  warnings_json TEXT NOT NULL DEFAULT '[]',
  last_sequence INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX operations_by_instance ON operations (instance_id, created_at);
'''),
  // Where each log source of each instance was read up to (design D6).
  Migration(2, '''
CREATE TABLE log_offsets (
  instance_id TEXT NOT NULL,
  source TEXT NOT NULL,
  file TEXT NOT NULL,
  offset INTEGER NOT NULL,
  PRIMARY KEY (instance_id, source)
);
'''),
  // Run records and crash timestamps (design D2, D14, D17). Times are epoch
  // milliseconds; `*_created` are the platform's process start times.
  Migration(3, '''
CREATE TABLE runs (
  run_id TEXT PRIMARY KEY,
  instance_id TEXT NOT NULL,
  directory TEXT NOT NULL,
  state TEXT NOT NULL,
  relay_pid INTEGER NOT NULL DEFAULT 0,
  relay_created INTEGER NOT NULL DEFAULT 0,
  relay_executable TEXT NOT NULL DEFAULT '',
  server_pid INTEGER NOT NULL DEFAULT 0,
  server_created INTEGER NOT NULL DEFAULT 0,
  executable TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  stop_requested_at INTEGER,
  stop_grace_ms INTEGER NOT NULL DEFAULT 0,
  stop_clears_requested INTEGER NOT NULL DEFAULT 1,
  stopped_by TEXT NOT NULL DEFAULT '',
  exit_code INTEGER,
  ended_at INTEGER,
  end_reason TEXT NOT NULL DEFAULT ''
);

CREATE INDEX runs_by_instance ON runs (instance_id, created_at);

CREATE TABLE crashes (
  instance_id TEXT NOT NULL,
  at INTEGER NOT NULL
);

CREATE INDEX crashes_by_instance ON crashes (instance_id, at);
'''),
  // M2: secrets, revisions, devices, audit and the rest of the secure-host
  // state (design D3, D4, D5, D6, D8, D11, D12). Times are epoch milliseconds.
  // Only the shapes live here; the behaviour arrives with later groups.
  Migration(4, '''
-- DPAPI blobs; scope_sid is the SID whose scope protected the row. A row of
-- an instance goes with the instance.
CREATE TABLE secrets (
  id TEXT PRIMARY KEY,
  instance_id TEXT REFERENCES instances(id) ON DELETE CASCADE,
  setting TEXT NOT NULL DEFAULT '',
  blob BLOB NOT NULL,
  scope_sid TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE INDEX secrets_by_instance ON secrets (instance_id);

ALTER TABLE instances ADD COLUMN revision INTEGER NOT NULL DEFAULT 1;
ALTER TABLE instances ADD COLUMN acl_layout INTEGER NOT NULL DEFAULT 0;
ALTER TABLE runs ADD COLUMN launched_ports TEXT NOT NULL DEFAULT '[]';

CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  enrolled_at INTEGER NOT NULL,
  last_seen_at INTEGER,
  last_address TEXT NOT NULL DEFAULT '',
  revoked_at INTEGER,
  revoked_by TEXT NOT NULL DEFAULT ''
);

CREATE TABLE device_certificates (
  device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  sha256 TEXT NOT NULL PRIMARY KEY,
  not_after INTEGER NOT NULL
);

CREATE INDEX device_certificates_by_device ON device_certificates (device_id);

CREATE TABLE pairing_codes (
  code_hash TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  used_at INTEGER
);

CREATE TABLE audit (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  time INTEGER NOT NULL,
  device_id TEXT NOT NULL,
  method TEXT NOT NULL,
  target TEXT NOT NULL DEFAULT '',
  result TEXT NOT NULL
);

CREATE TABLE auth_failures (
  address TEXT NOT NULL,
  window_start INTEGER NOT NULL,
  count INTEGER NOT NULL,
  last_reason TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (address, window_start)
);

CREATE INDEX auth_failures_by_window ON auth_failures (window_start);

-- Instance roots added by an administrator; the default root is implicit.
CREATE TABLE instance_roots (
  path TEXT PRIMARY KEY,
  added_at INTEGER NOT NULL
);

-- SteamCMD installations marked ready, and the last known size of each app,
-- moved out of files the low-privilege account could write.
CREATE TABLE steamcmd_installations (
  installation TEXT PRIMARY KEY,
  ready_at INTEGER NOT NULL
);

CREATE TABLE steam_app_sizes (
  app_id INTEGER PRIMARY KEY,
  bytes INTEGER NOT NULL,
  recorded_at INTEGER NOT NULL
);
'''),
  // M2: the daemon identity (design D1, D4). The CA key and the server key
  // are in the secret store; this row holds the public parts. The audit log
  // records the address of the caller.
  Migration(5, '''
CREATE TABLE daemon_identity (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  daemon_id TEXT NOT NULL,
  ca_certificate BLOB NOT NULL,
  server_certificate BLOB NOT NULL,
  created_at INTEGER NOT NULL
);

ALTER TABLE audit ADD COLUMN remote_address TEXT NOT NULL DEFAULT '';
'''),
  // M2: when a device certificate was issued and when it first authenticated
  // a call. A renewal from the previous certificate is accepted only while
  // the newest is unused and was issued less than 26 hours ago (design D4).
  // Certificates that exist now count as used and as old.
  Migration(6, '''
ALTER TABLE device_certificates ADD COLUMN first_used_at INTEGER;
ALTER TABLE device_certificates ADD COLUMN issued_at INTEGER NOT NULL DEFAULT 0;
UPDATE device_certificates SET first_used_at = CAST(strftime('%s', 'now') AS INTEGER) * 1000;
'''),
  // M3: Steam accounts, mods, the content store and the config binder (design
  // D1, D6, D7, D8, D9, D11). Times are epoch milliseconds. Only the shapes
  // live here; the behaviour arrives with later groups.
  Migration(7, '''
-- D1: id is acct_<12 hex>; status is adding, ready or reauth_required. The
-- password is a row of `secrets`, kept by id.
CREATE TABLE steam_accounts (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL,
  status TEXT NOT NULL,
  password_secret_id TEXT NOT NULL DEFAULT '',
  last_login_at INTEGER,
  created_at INTEGER NOT NULL
);

CREATE UNIQUE INDEX steam_accounts_by_username ON steam_accounts (username);

-- An account operation stores instance_id = '' and its account here.
ALTER TABLE operations ADD COLUMN account_id TEXT NOT NULL DEFAULT '';

CREATE INDEX operations_by_account ON operations (account_id, created_at);

-- D6: a row exists only for a published directory.
CREATE TABLE content_versions (
  source TEXT NOT NULL,
  app TEXT NOT NULL,
  item TEXT NOT NULL,
  version TEXT NOT NULL,
  size_bytes INTEGER NOT NULL DEFAULT 0,
  published_at INTEGER NOT NULL,
  unreferenced_since INTEGER,
  PRIMARY KEY (source, app, item, version)
);

-- D7: the mods of an instance, in order. stage_kind is link, copy or empty;
-- status is pending, downloading, staged, failed or unavailable.
CREATE TABLE instance_mods (
  instance_id TEXT NOT NULL REFERENCES instances(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  source TEXT NOT NULL,
  item_id TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT '',
  staged_name TEXT NOT NULL DEFAULT '',
  stage_kind TEXT NOT NULL DEFAULT '',
  desired_version TEXT NOT NULL DEFAULT '',
  staged_version TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending',
  last_error TEXT NOT NULL DEFAULT '',
  warnings_json TEXT NOT NULL DEFAULT '[]',
  remote_updated INTEGER NOT NULL DEFAULT 0,
  update_available INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (instance_id, position)
);

CREATE UNIQUE INDEX instance_mods_by_item
  ON instance_mods (instance_id, source, item_id);

-- D8: key files placed for an instance, owned per mod.
CREATE TABLE placed_keys (
  instance_id TEXT NOT NULL REFERENCES instances(id) ON DELETE CASCADE,
  file_name TEXT NOT NULL,
  content_hash TEXT NOT NULL DEFAULT '',
  providers_json TEXT NOT NULL DEFAULT '[]',
  PRIMARY KEY (instance_id, file_name)
);

-- D9: the hash of each file the config binder last wrote.
CREATE TABLE bound_files (
  instance_id TEXT NOT NULL REFERENCES instances(id) ON DELETE CASCADE,
  path TEXT NOT NULL,
  hash TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (instance_id, path)
);

-- D11: the secret a setting held before it was replaced.
CREATE TABLE replaced_secrets (
  instance_id TEXT NOT NULL REFERENCES instances(id) ON DELETE CASCADE,
  setting TEXT NOT NULL,
  blob BLOB NOT NULL,
  replaced_at INTEGER NOT NULL,
  PRIMARY KEY (instance_id, setting)
);
'''),
];
