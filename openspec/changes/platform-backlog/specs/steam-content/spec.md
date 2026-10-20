# Spec Delta

## Purpose

Downloads and updates game server content and workshop items from Steam, handling anonymous, account and Steam Guard logins without exposing credentials.

## ADDED Requirements

### Requirement: Adding a Steam account with Steam Guard
Adding an account SHALL log in once with username and password. If Steam asks for an email or authenticator code, the operation SHALL wait for input with a prompt of kind `email` or `authenticator`, wait up to 5 minutes for the code, and retry the login once with it; for kind `mobile_approval` it waits up to 2 minutes for approval.

#### Scenario: Email code relayed
- **WHEN** an admin adds account `srvadmin` and Steam requests an email code
- **THEN** the operation reports a prompt of kind `email`, the client submits `F3K9P`, the daemon retries with the code, and the account is listed as `ready`

#### Scenario: Wrong code
- **WHEN** the submitted code is rejected by Steam
- **THEN** the operation fails with `steam_guard_invalid`, the account is not saved, and the password is discarded

#### Scenario: No code submitted in time
- **WHEN** no code arrives within 5 minutes
- **THEN** the operation fails with `steam_guard_timeout` and no account is saved

### Requirement: Credential retention is the admin's choice
After a successful login the daemon SHALL rely on SteamCMD's cached login for that account. It SHALL keep the password, encrypted, only if the admin chose `remember_password`; otherwise it discards it, and a later expired login makes operations fail with `steam_reauth_required`.

#### Scenario: Password not remembered and cache valid
- **WHEN** an update runs for an account added without `remember_password` and the cached login is still valid
- **THEN** SteamCMD logs in with the username only and the update proceeds

#### Scenario: Cached login expired
- **WHEN** the cached login has expired and no password is stored
- **THEN** the operation fails with `steam_reauth_required`, and the client offers to re-enter the password for that account

### Requirement: Game Server Login Tokens
The daemon SHALL store a per-instance GSLT as a secret when the plugin declares `steam.gslt` and inject it into the launch arguments through the template; a GSLT is never treated as a Steam account login.

#### Scenario: Token injected at launch
- **WHEN** an instance has a GSLT set and the plugin's launch template references `{{secrets.gslt}}`
- **THEN** the launched process receives the token in its arguments, and the token does not appear in the operation history, the daemon's logs, or the relay's run files

#### Scenario: Required token missing
- **WHEN** the plugin declares `steam.gslt: required` and the instance has none
- **THEN** start fails with `FAILED_PRECONDITION` reason `gslt_required`

### Requirement: Workshop downloads
The daemon SHALL download workshop items with `workshop_download_item <workshop_app_id> <item_id>` using the account linked to the instance (or anonymous when the item allows it) and SHALL read item metadata (title, size, `time_updated`) before downloading.

#### Scenario: Workshop item downloaded
- **WHEN** mod 1559212036 is requested for a DayZ instance with a linked account
- **THEN** it is downloaded into the content store under `221100/1559212036` and its title and `time_updated` are recorded

#### Scenario: Item removed from the workshop
- **WHEN** metadata lookup reports the item does not exist or is private
- **THEN** the operation fails with `workshop_item_unavailable` naming the item, and other requested items are still processed

### Requirement: Steam passwords never reach disk or logs
The daemon SHALL pass the Steam password only as a SteamCMD argument, SHALL remove it from captured SteamCMD output, operation events and daemon logs, and SHALL store it only encrypted and only when the admin chose `remember_password`.

#### Scenario: Password absent from output
- **WHEN** an account is added and SteamCMD echoes its command line
- **THEN** no operation event, daemon log line or file in the data directory contains the password

#### Scenario: Remember password
- **WHEN** an account is added with `remember_password`
- **THEN** the password is stored only in the encrypted secrets table

## MODIFIED Requirements

### Requirement: Login mode per plugin
Each plugin SHALL declare `steam.login` as `anonymous`, `account` or `account_optional`. Instances of `account` plugins SHALL reference a Steam account added to the daemon before install.

#### Scenario: Anonymous install
- **WHEN** a Valheim instance (`login: anonymous`) is installed
- **THEN** SteamCMD runs with `+login anonymous` and the app is installed into the instance directory

#### Scenario: Account login not available
- **WHEN** a DayZ instance (`login: account`) is installed without a linked Steam account
- **THEN** the install fails with `FAILED_PRECONDITION` reason `steam_account_required` before SteamCMD runs

### Requirement: SteamCMD is installed and managed by the daemon
The daemon SHALL download and bootstrap SteamCMD on first need into its data directory, keeping one SteamCMD installation per Steam account plus one for anonymous use, and SHALL report SteamCMD bootstrap failures as operation errors.

#### Scenario: First install bootstraps SteamCMD
- **WHEN** the first install operation runs on a fresh host
- **THEN** SteamCMD is downloaded into `<data>/steamcmd/anonymous/`, self-updates, and the install continues without user action

#### Scenario: SteamCMD download fails
- **WHEN** the SteamCMD archive cannot be downloaded
- **THEN** the operation fails with `steamcmd_unavailable` and the HTTP status or network error, and no partial SteamCMD directory is left marked as ready
