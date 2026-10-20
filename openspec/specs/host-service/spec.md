# host-service Specification

## Purpose

Runs the daemon with a predictable data layout and a safe startup sequence.

## Requirements

### Requirement: Data directory layout
The daemon SHALL keep its state in one data directory (default `%ProgramData%\Yagura`, `/var/lib/yagura` on Linux) containing the database, SteamCMD installations, plugins, snapshots and daemon logs. Instance directories default under its `instances/` folder and may be placed under other instance roots, which are added and removed only with `yagurad roots add|remove` over the local admin channel, which makes a root writable only by SYSTEM and Administrators; the gRPC API cannot change them.

#### Scenario: Default layout created
- **WHEN** the daemon starts for the first time with no configuration
- **THEN** `%ProgramData%\Yagura` contains `yagura.db`, `steamcmd/`, `plugins/`, `instances/`, `snapshots/` and `logs/`

#### Scenario: Data directory not writable
- **WHEN** the daemon cannot create its data directory
- **THEN** it exits non-zero with `data_dir_unwritable` and the path

#### Scenario: Instance root added locally
- **WHEN** an administrator runs `yagurad roots add D:\servers`
- **THEN** creating an instance under `D:\servers` is allowed, and no remote call can add or remove a root

#### Scenario: Instance on another drive
- **WHEN** `D:\servers` is a configured instance root and an instance is created with directory `D:\servers\valheim-main`
- **THEN** its files live there and the daemon's own state stays in the data directory

#### Scenario: Root writable by non-administrators
- **WHEN** an administrator runs `yagurad roots add D:\servers` and the daemon cannot make `D:\servers` writable only by SYSTEM and Administrators
- **THEN** the command fails with `root_not_protected` and the root is not added

#### Scenario: Root still in use
- **WHEN** an administrator runs `yagurad roots remove D:\servers` while an instance lives under it
- **THEN** the command fails with `root_in_use` naming the instance, and the root stays configured

### Requirement: Startup sequence
On start the daemon SHALL lock the data directory, in service mode protect the data directory (owner Administrators, a protected SYSTEM/Administrators DACL, and a one-time no-follow walk of its existing contents outside instance directories), open and migrate the database, open the secret store and, in service mode, load its identity (failures here exit non-zero naming the step), then load plugins, recover instances, in service mode set up the service accounts and directory permissions and reconcile the firewall, and start log tailing, where failures are reported as notices and health flags, and then open the API listener. In service mode, secrets protected for another Windows account cannot be read; the daemon SHALL delete them, re-create what it owns, and keep every instance.

#### Scenario: Migration with backup
- **WHEN** a new daemon version starts on a database with an older schema
- **THEN** a backup `yagura.db.bak-<version>` is written, migrations run in a transaction, and the daemon serves calls afterwards

#### Scenario: Migration fails
- **WHEN** a migration fails
- **THEN** the transaction rolls back, the database is unchanged, the daemon exits non-zero with `migration_failed` and the migration number, and running game servers are untouched

#### Scenario: Data directory used by a dev daemon first
- **WHEN** a `--dev` daemon stored a secret setting for instance `A`, and the service then starts on the same data directory
- **THEN** the service starts, instance `A` is kept with that secret setting reported `{"secret": true, "set": false}`, and notice `secrets_reset` names `A`

#### Scenario: Data directory created by an earlier daemon
- **WHEN** the service starts on a data directory whose `snapshots`, `logs` and `yagura.db` were created by an M1 or `--dev` daemon
- **THEN** before the database is opened, those items are owned by Administrators and grant nothing to `Users`, `yagura-srv` or `yagura-steam`

#### Scenario: Data directory is a link
- **WHEN** the service first starts and `%ProgramData%\Yagura` is a junction
- **THEN** the daemon exits non-zero with `data_dir_not_protected` naming that path, and creates nothing behind the junction

#### Scenario: Layout marker planted by a standard user
- **WHEN** the service first starts on a data directory where a standard user created `acl-layout` with the current version
- **THEN** the walk still runs and `yagura.db` grants nothing to `Users`

#### Scenario: Link in the data directory at first service start
- **WHEN** the service first starts on a data directory where `snapshots` contains a junction
- **THEN** the daemon exits non-zero with `data_dir_not_protected` naming the junction's path, without opening the database

#### Scenario: Firewall unavailable at startup
- **WHEN** the Windows Firewall service is stopped when the service starts
- **THEN** the daemon serves calls, `GetHealth` reports `firewall_ok: false`, and the daemon does not exit

### Requirement: Single daemon per data directory
The daemon SHALL hold an operating-system exclusive lock on a lock file in its data directory, which the OS releases when the holder exits, and refuse to start if another process holds it. The lock SHALL cover only a byte range past the holder's PID, which the holder writes at the start of the file, so a refused daemon can read it.

#### Scenario: Second instance refused
- **WHEN** a second `yagurad` starts against the same data directory
- **THEN** it exits non-zero with `data_dir_locked` and the PID of the holder

#### Scenario: Lock file left by a crashed daemon
- **WHEN** a lock file remains from a daemon that crashed, and its recorded PID now belongs to an unrelated process
- **THEN** the new daemon acquires the lock and starts normally

### Requirement: Windows service install and control
`yagurad service install` SHALL register the daemon as a Windows service `yagurad` that starts automatically, runs as LocalSystem and restarts on failure; run from a newer bundle on a host where the service is installed, it SHALL upgrade it. `service configure --bind <address:port>` SHALL change the API bind for the next service start. `service uninstall` and `service status` SHALL remove and report it. All require an elevated prompt.

#### Scenario: Install as a service
- **WHEN** an admin runs `yagurad service install` in an elevated prompt
- **THEN** a service `yagurad` exists with start type automatic, and it is running after the command returns

#### Scenario: Not elevated
- **WHEN** the command runs without elevation
- **THEN** it exits non-zero with `elevation_required` and no service is registered

#### Scenario: Already installed
- **WHEN** `yagurad service install` runs from a bundle of the same version as the registered service
- **THEN** it exits non-zero with `service_exists` and the existing service is unchanged

### Requirement: Game servers run under a low-privilege account
In service mode the daemon SHALL keep a local account `yagura-srv` with no administrative rights and no interactive logon, and SHALL start every game server under it with the ADR 0015 directory permissions: on each instance directory, list, create and modify its contents but not delete or rename the directory itself; on the data directory, no access. Instances created before the service was installed SHALL get the same permissions at the next service start.

#### Scenario: Server process identity
- **WHEN** a Valheim instance is started in service mode
- **THEN** the server process runs as `yagura-srv`, and it cannot open `yagura.db`

#### Scenario: Instance created before the service
- **WHEN** an instance created by a `--dev` daemon is updated and started after `yagurad service install`
- **THEN** SteamCMD updates it as `yagura-steam`, its server runs as `yagura-srv`, and neither fails with access denied

#### Scenario: Logon fails
- **WHEN** the game-server account's logon fails (for example it was disabled)
- **THEN** the start fails with `launch_logon_failed` and the Windows error, and the instance stays `stopped`

### Requirement: Servers survive service stop and upgrade
Stopping, restarting or upgrading the daemon service SHALL NOT stop running game servers.

#### Scenario: Service restart
- **WHEN** the service is restarted while two instances run
- **THEN** both server processes keep their PIDs and the daemon re-attaches to both

#### Scenario: Service upgraded in place
- **WHEN** `yagurad service install` runs from a newer bundle while an instance runs
- **THEN** the service runs the newer version, the server process keeps its PID, and the new daemon re-attaches to it

#### Scenario: Server exits while the daemon is down
- **WHEN** a server exits while the service is stopped
- **THEN** after the service starts the instance shows the exit code from the relay's exit record
