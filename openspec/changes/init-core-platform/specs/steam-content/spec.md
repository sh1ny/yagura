# Spec Delta

## Purpose

Downloads and updates game server content and workshop items from Steam, handling anonymous, account and Steam Guard logins without exposing credentials.

## ADDED Requirements

### Requirement: SteamCMD is installed and managed by the daemon
The daemon SHALL download and bootstrap SteamCMD on first need into its data directory, keeping one SteamCMD installation for anonymous use, and SHALL report SteamCMD bootstrap failures as operation errors.

#### Scenario: First install bootstraps SteamCMD
- **WHEN** the first install operation runs on a fresh host
- **THEN** SteamCMD is downloaded into `<data>/steamcmd/anonymous/`, self-updates, and the install continues without user action

#### Scenario: SteamCMD download fails
- **WHEN** the SteamCMD archive cannot be downloaded
- **THEN** the operation fails with `steamcmd_unavailable` and the HTTP status or network error, and no partial SteamCMD directory is left marked as ready

### Requirement: Login mode per plugin
Each plugin SHALL declare `steam.login` as `anonymous`, `account` or `account_optional`, and SHALL install `anonymous` plugins with SteamCMD's anonymous login.

#### Scenario: Anonymous install
- **WHEN** a Valheim instance (`login: anonymous`) is installed
- **THEN** SteamCMD runs with `+login anonymous` and the app is installed into the instance directory

### Requirement: SteamCMD runs non-interactively
The daemon SHALL invoke SteamCMD only with `+command` arguments ending in `+quit` and stdin closed, never through a script file, run at most one SteamCMD process per installation at a time, and classify output with a versioned pattern table; unrecognised failure output is returned verbatim (last 50 lines, password removed).

#### Scenario: Known failure classified
- **WHEN** SteamCMD prints a "No subscription" failure for app 223350
- **THEN** the operation fails with `steam_no_subscription` and a message that the account does not own the required app

#### Scenario: Unknown failure surfaced
- **WHEN** SteamCMD exits non-zero with output matching no known pattern
- **THEN** the operation fails with `steam_unknown_error` and carries the last 50 output lines, and the daemon does not retry

### Requirement: Install, update and validate apps
The daemon SHALL install and update an instance's app with `app_update <app_id>` (with the plugin's `branch` and optional beta password) into the instance directory, report download progress, and support a `validate` option. Before downloading it SHALL check free disk space.

#### Scenario: Update reports progress
- **WHEN** an update downloads 1.2 GB
- **THEN** progress events report bytes and percent at least every 2 s until completion

#### Scenario: Two instances of one app installed at once
- **WHEN** two Valheim instances are installed concurrently
- **THEN** the installs run one after the other, the second reports step `waiting_for_steamcmd` meanwhile, and each instance directory contains the full app

#### Scenario: Not enough disk space
- **WHEN** the volume has less free space than twice the app's last known size
- **THEN** the operation fails with `insufficient_disk` naming the volume, free bytes and required bytes, before SteamCMD downloads anything

### Requirement: SteamCMD runs are bounded and cleaned up
A SteamCMD step SHALL fail after 15 minutes without download progress or 12 hours in total. SteamCMD processes SHALL end when the daemon ends, and at startup the daemon SHALL terminate any SteamCMD process running from its SteamCMD directories before accepting operations.

#### Scenario: Stalled download
- **WHEN** SteamCMD reports no download progress for 15 minutes
- **THEN** it is terminated and the operation fails with `steam_stalled` and the last progress values

#### Scenario: Stray SteamCMD after a crash
- **WHEN** the daemon starts and a SteamCMD process from its directories is still running
- **THEN** that process is terminated before the API listener opens, and the termination is logged
