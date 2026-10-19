# Spec Delta

## Purpose

Runs the daemon as a long-lived host service that starts at boot, with a predictable data layout and a safe startup sequence.

## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: Data directory layout
The daemon SHALL keep its state in one data directory (default `%ProgramData%\Yagura`, `/var/lib/yagura` on Linux) containing the database, SteamCMD installations, the content store, plugins, snapshots and daemon logs; instance directories default under it and may be placed elsewhere per instance.

#### Scenario: Default layout created
- **WHEN** the daemon starts for the first time with no configuration
- **THEN** `%ProgramData%\Yagura` contains `yagura.db`, `steamcmd/`, `content/`, `plugins/`, `instances/`, `snapshots/` and `logs/`

#### Scenario: Data directory not writable
- **WHEN** the daemon cannot create its data directory
- **THEN** it exits non-zero with `data_dir_unwritable` and the path

