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
];
