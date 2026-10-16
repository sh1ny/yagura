# Spec Delta

## Purpose

Runs the daemon as a long-lived host service that starts at boot, with a predictable data layout and a safe startup sequence.

## ADDED Requirements

### Requirement: Data directory layout
The daemon SHALL keep its state in one data directory (default `%ProgramData%\Yagura`, `/var/lib/yagura` on Linux) containing the database, SteamCMD installations, the content store, plugins and daemon logs; instance directories are created under its `instances/` folder.

#### Scenario: Default layout created
- **WHEN** the daemon starts for the first time with no configuration
- **THEN** `%ProgramData%\Yagura` contains `yagura.db`, `steamcmd/`, `content/`, `plugins/`, `instances/` and `logs/`

#### Scenario: Data directory not writable
- **WHEN** the daemon cannot create its data directory
- **THEN** it exits non-zero with `data_dir_unwritable` and the path

### Requirement: Startup sequence
On start the daemon SHALL lock the data directory, open and migrate the database (failures here exit non-zero naming the step), then load plugins, recover instances and start log tailing, where failures are reported as notices and health flags, and then open the API listener.

#### Scenario: Migration with backup
- **WHEN** a new daemon version starts on a database with an older schema
- **THEN** a backup `yagura.db.bak-<version>` is written, migrations run in a transaction, and the daemon serves calls afterwards

#### Scenario: Migration fails
- **WHEN** a migration fails
- **THEN** the transaction rolls back, the database is unchanged, the daemon exits non-zero with `migration_failed` and the migration number, and running game servers are untouched

### Requirement: Single daemon per data directory
The daemon SHALL hold an operating-system exclusive lock on a lock file in its data directory, which the OS releases when the holder exits, and refuse to start if another process holds it.

#### Scenario: Second instance refused
- **WHEN** a second `yagurad` starts against the same data directory
- **THEN** it exits non-zero with `data_dir_locked` and the PID of the holder

#### Scenario: Lock file left by a crashed daemon
- **WHEN** a lock file remains from a daemon that crashed, and its recorded PID now belongs to an unrelated process
- **THEN** the new daemon acquires the lock and starts normally
