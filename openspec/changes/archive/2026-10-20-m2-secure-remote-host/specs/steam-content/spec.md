# Spec Delta

## MODIFIED Requirements

### Requirement: Install, update and validate apps
The daemon SHALL install and update an instance's app with `app_update <app_id>` (with the plugin's `branch` and optional beta password) into the instance directory, report download progress, and support a `validate` option. Before downloading it SHALL check free disk space against twice the app's last known size on this host, or twice the manifest's `steam.size_hint_bytes` when there is none; with neither, the check is skipped and the operation shows warning `disk_check_skipped`. In service mode, SteamCMD SHALL run as a dedicated low-privilege account on its own desktop, and SHALL NOT be able to write to system folders or to the data directory outside SteamCMD installations.

#### Scenario: Update reports progress
- **WHEN** an update downloads 1.2 GB
- **THEN** progress events report bytes and percent at least every 2 s until completion

#### Scenario: SteamCMD runs without SYSTEM rights
- **WHEN** an install runs in service mode
- **THEN** the SteamCMD process runs as `yagura-steam`, not as LocalSystem

#### Scenario: SteamCMD separated from game servers
- **WHEN** instance A updates while instance B's server runs
- **THEN** SteamCMD runs on a window station and desktop other than the one B's server runs on

#### Scenario: Link planted into a system folder during an update
- **WHEN** instance A is updating and a junction inside A's directory points at `C:\Windows\System32` while SteamCMD writes through it
- **THEN** SteamCMD's writes through the junction fail with access denied, and no file in system folders or in the data directory outside SteamCMD installations changes

#### Scenario: Two instances of one app installed at once
- **WHEN** two Valheim instances are installed concurrently
- **THEN** the installs run one after the other, the second reports step `waiting_for_steamcmd` meanwhile, and each instance directory contains the full app

#### Scenario: Not enough disk space
- **WHEN** the volume has less free space than twice the app's last known size
- **THEN** the operation fails with `insufficient_disk` naming the volume, free bytes and required bytes, before SteamCMD downloads anything

#### Scenario: First install without a known size
- **WHEN** an app is installed for the first time on this host and its manifest has no `steam.size_hint_bytes`
- **THEN** the install runs without the disk check, and the operation shows warning `disk_check_skipped`
