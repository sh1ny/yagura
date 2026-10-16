# Spec Delta

## Purpose

Runs the daemon as a long-lived host service that starts at boot, with a predictable data layout and a safe startup sequence.

## ADDED Requirements

### Requirement: Windows service install and control
`yagurad service install` SHALL register the daemon as a Windows service that starts automatically, runs as LocalSystem and restarts on failure; `service uninstall` and `service status` SHALL remove and report it. Both require an elevated prompt.

#### Scenario: Install as a service
- **WHEN** an admin runs `yagurad service install` in an elevated prompt
- **THEN** a service `yagurad` exists with start type automatic, and it is running after the command returns

#### Scenario: Not elevated
- **WHEN** the command runs without elevation
- **THEN** it exits non-zero with `elevation_required` and no service is registered

### Requirement: Linux service
On Linux the daemon SHALL install a systemd unit through `yagurad service install`, with game servers started in their own transient scopes so stopping the unit does not stop them.

#### Scenario: Unit installed
- **WHEN** an admin runs `sudo yagurad service install` on Linux
- **THEN** `yagurad.service` is enabled and active

#### Scenario: systemd not available
- **WHEN** `yagurad service install` runs on a Linux host without systemd
- **THEN** it exits non-zero with `systemd_required` and installs nothing

#### Scenario: Stopping the unit keeps servers
- **WHEN** `systemctl stop yagurad` runs while two instances are running
- **THEN** both game server processes are still running afterwards

### Requirement: Game servers run under a low-privilege account
Service install SHALL create a local account for game servers with no administrative rights and no interactive logon, and the daemon SHALL start every game server under it with the directory permissions from the architecture (instance read-write, content store read-only, data directory no access).

#### Scenario: Server process identity
- **WHEN** a DayZ instance is started on a host where the service is installed
- **THEN** the server process runs as `yagura-srv`, and it cannot open `yagura.db`

#### Scenario: Logon fails
- **WHEN** the game-server account's logon fails (for example it was disabled)
- **THEN** the start fails with `launch_logon_failed` and the Windows error, and the instance stays `stopped`

### Requirement: Servers survive service stop and upgrade
Stopping, restarting or upgrading the daemon service SHALL NOT stop running game servers.

#### Scenario: Service restart
- **WHEN** the service is restarted while two instances run
- **THEN** both server processes keep their PIDs and the daemon re-attaches to both

#### Scenario: Server exits while the daemon is down
- **WHEN** a server exits while the service is stopped
- **THEN** after the service starts the instance shows the exit code from the relay's exit record

## MODIFIED Requirements

### Requirement: Data directory layout
The daemon SHALL keep its state in one data directory (default `%ProgramData%\Yagura`, `/var/lib/yagura` on Linux) containing the database, SteamCMD installations, the content store, plugins and daemon logs; instance directories default under it and may be placed elsewhere per instance. Instance roots are added and removed only with `yagurad roots add|remove` over the local admin channel; the gRPC API cannot change them.

#### Scenario: Default layout created
- **WHEN** the daemon starts for the first time with no configuration
- **THEN** `%ProgramData%\Yagura` contains `yagura.db`, `steamcmd/`, `content/`, `plugins/`, `instances/` and `logs/`

#### Scenario: Instance root added locally
- **WHEN** an administrator runs `yagurad roots add D:\servers`
- **THEN** creating an instance under `D:\servers` is allowed and no remote call can add or remove a root

#### Scenario: Data directory not writable
- **WHEN** the daemon cannot create its data directory
- **THEN** it exits non-zero with `data_dir_unwritable` and the path

#### Scenario: Instance on another drive
- **WHEN** `D:\servers` is a configured instance root and an instance is created with directory `D:\servers\dayz-main`
- **THEN** its files live there and the content store stays in the data directory

### Requirement: Startup sequence
On start the daemon SHALL lock the data directory, open and migrate the database, open the secret store and load its identity (failures here exit non-zero naming the step), then load plugins, recover instances, reconcile the firewall and start log tailing, where failures are reported as notices and health flags, and then open the API listener.

#### Scenario: Migration with backup
- **WHEN** a new daemon version starts on a database with an older schema
- **THEN** a backup `yagura.db.bak-<version>` is written, migrations run in a transaction, and the daemon serves calls afterwards

#### Scenario: Firewall unavailable at startup
- **WHEN** the Windows Firewall service is stopped when the daemon starts
- **THEN** the daemon serves calls, `GetHealth` reports `firewall_ok: false`, and the daemon does not exit

#### Scenario: Migration fails
- **WHEN** a migration fails
- **THEN** the transaction rolls back, the database is unchanged, the daemon exits non-zero with `migration_failed` and the migration number, and running game servers are untouched
