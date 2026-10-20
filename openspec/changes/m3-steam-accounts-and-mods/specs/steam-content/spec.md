# Spec Delta

## ADDED Requirements

### Requirement: Adding a Steam account with Steam Guard
Adding an account SHALL log in once with username and password in the account's own SteamCMD installation. If Steam asks for an email or authenticator code, the operation SHALL wait for input with a prompt of kind `email` or `authenticator` for up to 15 minutes and retry the login once with the submitted code; for kind `mobile_approval` it SHALL wait up to 2 minutes for the approval.

#### Scenario: Email code relayed
- **WHEN** an admin adds account `srvadmin` and Steam requests an email code
- **THEN** the operation reports a prompt of kind `email`, the client submits `F3K9P`, the daemon retries with the code, and the account is listed as `ready`

#### Scenario: Wrong code
- **WHEN** the submitted code is rejected by Steam
- **THEN** the operation fails with `steam_guard_invalid`, the account is not saved, and the password is discarded

#### Scenario: No code submitted in time
- **WHEN** no code arrives within 15 minutes
- **THEN** the operation fails with `steam_guard_timeout` and no account is saved

#### Scenario: Mobile approval not given
- **WHEN** Steam asks for a mobile approval and none arrives within 2 minutes
- **THEN** the SteamCMD run is terminated, the operation fails with `steam_guard_timeout`, and no account is saved

#### Scenario: Wrong password
- **WHEN** Steam rejects the username or password
- **THEN** the operation fails with `steam_login_invalid` without raising a prompt, and no account is saved

#### Scenario: SteamCMD does not respond
- **WHEN** the login run neither ends, asks for a code or an approval, nor writes to its SteamCMD log for 60 seconds
- **THEN** the SteamCMD run is terminated, the operation fails with `steam_login_unresponsive`, and no account is saved

#### Scenario: Daemon restarted while adding
- **WHEN** the daemon restarts while an `AddAccount` operation waits for a Steam Guard code
- **THEN** after startup the operation is `interrupted`, the account is not listed, and its stored password and SteamCMD installation are removed

#### Scenario: Account already added
- **WHEN** a client adds account `srvadmin` and an account with that username already exists
- **THEN** the call fails with `ALREADY_EXISTS` reason `account_exists`, and no operation is created

### Requirement: Credential retention is the admin's choice
After a successful login the daemon SHALL rely on SteamCMD's cached login for that account. It SHALL keep the password, encrypted, only if the admin chose `remember_password`; otherwise it discards it, and a later expired login makes operations fail with `steam_reauth_required` and marks the account `reauth_required`.

#### Scenario: Password not remembered and cache valid
- **WHEN** an update runs for an account added without `remember_password` and the cached login is still valid
- **THEN** SteamCMD logs in with the username only and the update proceeds

#### Scenario: Cached login expired
- **WHEN** the cached login has expired and no password is stored
- **THEN** the operation fails with `steam_reauth_required`, the account is listed as `reauth_required`, and the client offers to re-enter the password for that account

#### Scenario: Remembered password needs Steam Guard during an update
- **WHEN** the cached login has expired, the password is remembered, and Steam asks for a code during an instance update
- **THEN** the update operation raises a prompt of kind `email` or `authenticator` naming the account, and continues with the download once the code is accepted

#### Scenario: Account removed while in use
- **WHEN** a client removes an account linked to an instance
- **THEN** the call fails with `FAILED_PRECONDITION` reason `account_in_use` naming the instance, and the account is kept

### Requirement: Game Server Login Tokens
A plugin SHALL name the `secret` setting that holds the instance's Game Server Login Token in `steam.gslt`, and reference it in its launch template as `{{secrets.<setting>}}`. A GSLT is never used as a Steam account login.

#### Scenario: Token injected at launch
- **WHEN** an instance has its GSLT set and the plugin's launch template references `{{secrets.gslt}}`
- **THEN** the launched process receives the token in its arguments, and the token does not appear in the operation history, the daemon's logs, or the relay's run files

#### Scenario: Required token missing
- **WHEN** the plugin declares `steam.gslt` as required and the instance has no token set
- **THEN** start fails with `FAILED_PRECONDITION` reason `gslt_required`, and no process is launched

### Requirement: Workshop downloads
The daemon SHALL read workshop item metadata (title, size, `time_updated`, visibility) before downloading, and SHALL download items with `workshop_download_item <workshop_app_id> <item_id>` using the account linked to the instance, or anonymously when no account is linked.

#### Scenario: Workshop item downloaded
- **WHEN** mod 1559212036 is requested for a DayZ instance with a linked account
- **THEN** it is downloaded and published into the content store under `steam_workshop/221100/1559212036/<time_updated>/`, and its title and `time_updated` are recorded

#### Scenario: Item removed from the workshop
- **WHEN** metadata lookup reports the item does not exist or is private
- **THEN** that item's mod is marked `unavailable` with `workshop_item_unavailable`, the operation fails naming the item, and the other requested items are still downloaded

### Requirement: Steam passwords never reach disk or logs
The daemon SHALL pass a Steam password only as a SteamCMD argument, SHALL remove it from captured SteamCMD output, operation events and daemon logs, and SHALL store it only encrypted and only when the admin chose `remember_password`.

#### Scenario: Password absent from output
- **WHEN** an account is added and SteamCMD echoes its command line
- **THEN** no operation event, daemon log line or file in the data directory contains the password

#### Scenario: Remember password
- **WHEN** an account is added with `remember_password`
- **THEN** the password is stored only in the encrypted secrets table

#### Scenario: Secret store refuses the password
- **WHEN** an account is added with `remember_password` and the secret store refuses the write
- **THEN** the operation fails with `secret_store_unavailable`, and no account is saved

## MODIFIED Requirements

### Requirement: Login mode per plugin
Each plugin SHALL declare `steam.login` as `anonymous`, `account` or `account_optional`. Instances of `account` plugins SHALL reference a Steam account added to the daemon before install; `account_optional` instances SHALL use their linked account when they have one and anonymous login otherwise.

#### Scenario: Anonymous install
- **WHEN** a Valheim instance (`login: anonymous`) is installed
- **THEN** SteamCMD runs with `+login anonymous` and the app is installed into the instance directory

#### Scenario: Account install
- **WHEN** a DayZ instance (`login: account`) linked to the `ready` account `srvadmin` is installed
- **THEN** SteamCMD runs in `srvadmin`'s installation with `+login srvadmin` and the app is installed into the instance directory

#### Scenario: Account login not available
- **WHEN** a DayZ instance (`login: account`) is installed without a linked Steam account
- **THEN** the install fails with `FAILED_PRECONDITION` reason `steam_account_required` before SteamCMD runs

#### Scenario: Optional account not linked
- **WHEN** an instance of an `account_optional` plugin with no linked account is installed
- **THEN** SteamCMD runs in the anonymous installation with `+login anonymous`

### Requirement: SteamCMD is installed and managed by the daemon
The daemon SHALL download and bootstrap SteamCMD on first need into its data directory, keeping one SteamCMD installation per Steam account plus one for anonymous use, and SHALL report SteamCMD bootstrap failures as operation errors.

#### Scenario: First install bootstraps SteamCMD
- **WHEN** the first install operation runs on a fresh host
- **THEN** SteamCMD is downloaded into `<data>/steamcmd/anonymous/`, self-updates, and the install continues without user action

#### Scenario: Account installation bootstrapped
- **WHEN** an admin adds the first Steam account `srvadmin`
- **THEN** a separate SteamCMD installation is bootstrapped for it under `<data>/steamcmd/`, and the anonymous installation is not touched

#### Scenario: SteamCMD download fails
- **WHEN** the SteamCMD archive cannot be downloaded
- **THEN** the operation fails with `steamcmd_unavailable` and the HTTP status or network error, and no partial SteamCMD directory is left marked as ready

### Requirement: SteamCMD runs are bounded and cleaned up
A SteamCMD step SHALL fail after 15 minutes without download progress or 12 hours in total, reading progress from its log (console output arrives only at exit). SteamCMD processes SHALL end with the daemon; at startup the daemon SHALL terminate any SteamCMD running from its directories before accepting operations. One it cannot terminate makes that installation unavailable: operations needing it fail with `steamcmd_unavailable`, starting no SteamCMD, until a sweep retried every 60 s succeeds.

#### Scenario: Stalled download
- **WHEN** SteamCMD reports no download progress for 15 minutes
- **THEN** it is terminated and the operation fails with `steam_stalled` and the last progress values

#### Scenario: Long download that keeps progressing
- **WHEN** a download runs for longer than 15 minutes, its console output held back until exit, while its log reports progress every few seconds
- **THEN** it is not terminated, the operation's progress follows the log, and the operation succeeds when SteamCMD exits successfully

#### Scenario: Stray SteamCMD after a crash
- **WHEN** the daemon starts and a SteamCMD process from its directories is still running
- **THEN** that process is terminated before the API listener opens, and the termination is logged

#### Scenario: Stray SteamCMD cannot be terminated
- **WHEN** the startup sweep cannot terminate a SteamCMD process running from the anonymous installation
- **THEN** the API listener still opens with a notice, installs fail with `steamcmd_unavailable` without starting another SteamCMD, and installs run again once a retried sweep succeeds

### Requirement: Install, update and validate apps
The daemon SHALL install and update an instance's app with `app_update <app_id>` (plugin `branch`, optional beta password) into the instance directory, with progress and a `validate` option, after requiring free space of twice the app's last size here, else twice `steam.size_hint_bytes` (neither: skip it, warn `disk_check_skipped`). In service mode SteamCMD SHALL run as a low-privilege account on its own desktop, unable to write system folders or the data directory outside SteamCMD installs.

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
