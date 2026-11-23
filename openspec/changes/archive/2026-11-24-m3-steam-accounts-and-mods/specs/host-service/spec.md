# Spec Delta

## MODIFIED Requirements

### Requirement: Data directory layout
The daemon SHALL keep its state in one data directory (default `%ProgramData%\Yagura`, `/var/lib/yagura` on Linux) holding the database, SteamCMD installations, the content store, plugins, snapshots and daemon logs. Instance directories default under its `instances/` folder and may sit under other instance roots, added and removed only with `yagurad roots add|remove` over the local admin channel, which makes a root writable only by SYSTEM and Administrators; the gRPC API cannot change them.

#### Scenario: Default layout created
- **WHEN** the daemon starts for the first time with no configuration
- **THEN** `%ProgramData%\Yagura` contains `yagura.db`, `steamcmd/`, `content/`, `plugins/`, `instances/`, `snapshots/` and `logs/`

#### Scenario: Content store protected
- **WHEN** the service-mode daemon creates `content/`
- **THEN** SYSTEM and Administrators have full access, the game-server account has read and execute only, and the SteamCMD account has no entry

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
On start the daemon SHALL, in order: lock the data directory; in service mode protect it (Administrators owner, protected SYSTEM/Administrators DACL, one no-follow walk outside instance directories); open and migrate the database; open the secret store and, in service mode, its identity, exiting non-zero naming a failed step; then load plugins, recover instances, in service mode set up accounts, directory rights and firewall, start log tailing (failures: notices, health flags) and open the API.

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

## ADDED Requirements

### Requirement: Unreadable secrets are reset in service mode
In service mode, secrets protected for another Windows account or another machine cannot be read; the daemon SHALL delete them at startup, re-create the secrets it owns, keep every instance and name the affected instances in notice `secrets_reset`. When DPAPI fails for any other reason, it SHALL delete nothing and fail with `secret_store_unavailable`.

#### Scenario: Secrets protected for another account
- **WHEN** a `--dev` daemon stored secrets for instance `A` and one of its own, and the service then opens the secret store
- **THEN** those secrets are deleted, the reset names instance `A`, every instance is kept, and only secrets the service stores afterwards remain

#### Scenario: Secrets protected on another machine
- **WHEN** the service opens a secret store whose secrets were protected by LocalSystem on another machine
- **THEN** those secrets are deleted, the reset names instance `A` by its name, and every instance is kept

#### Scenario: DPAPI fault deletes nothing
- **WHEN** the service opens its own secret store and DPAPI fails for a reason other than a wrong key
- **THEN** opening fails with `secret_store_unavailable`, no secret or instance is deleted, and the same secrets open once DPAPI works again
