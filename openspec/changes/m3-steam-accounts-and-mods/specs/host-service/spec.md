# Spec Delta

## MODIFIED Requirements

### Requirement: Data directory layout
The daemon SHALL keep its state in one data directory (default `%ProgramData%\Yagura`, `/var/lib/yagura` on Linux) containing the database, SteamCMD installations, the content store, plugins, snapshots and daemon logs. Instance directories default under its `instances/` folder and may be placed under other instance roots, which are added and removed only with `yagurad roots add|remove` over the local admin channel, which makes a root writable only by SYSTEM and Administrators; the gRPC API cannot change them.

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
