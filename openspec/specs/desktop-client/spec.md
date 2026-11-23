# desktop-client Specification

## Purpose

Gives the admin a desktop application for a Yagura daemon, rendering each game's settings from its plugin schema and showing operations and logs live. This version connects to one daemon over the development connection.

## Requirements

### Requirement: Forms rendered from plugin schemas
The client SHALL render instance settings from the plugin's settings schema: an input per type, nested groups for objects, grouping and an advanced section, client-side validation with the schema's constraints, and the daemon's field errors shown on the fields. Saving SHALL send the revision the form was loaded from. Secret values entered in the form SHALL be sent only with `SetSecret`.

#### Scenario: Daemon rejects a value
- **WHEN** the daemon returns a field violation for `ports.game`
- **THEN** the error is shown under the port field and the other edits stay in the form

#### Scenario: Unknown field type
- **WHEN** a schema contains a type the client does not know
- **THEN** the field is shown read-only with its raw JSON value and a notice, and the rest of the form works

#### Scenario: Create an instance with a secret
- **WHEN** the user creates an instance and enters an RCON password in the form
- **THEN** the client calls `CreateInstance` without the value, then `SetSecret` with it, and shows the instance with the secret `set`

#### Scenario: Someone else saved first
- **WHEN** saving fails with `revision_conflict`
- **THEN** the client reloads the instance, shows which fields differ from the user's unsaved edits, and keeps the edits for the user to re-apply

### Requirement: Logs and console views
The client SHALL show each instance's log sources with backlog and live follow, search within the loaded lines, and pause. While paused, a view SHALL hold up to 10,000 new lines; beyond that it drops the oldest held lines and shows their count on resume.

#### Scenario: Follow and pause
- **WHEN** the admin pauses a live log view
- **THEN** new lines are counted but not appended until resume, and on resume the view shows them in order

#### Scenario: Dropped lines marker
- **WHEN** the daemon sends a `dropped` marker
- **THEN** the view shows an inline notice with the number of skipped lines

#### Scenario: Pause longer than the buffer
- **WHEN** 15,000 lines arrive while a log view is paused
- **THEN** on resume the view shows a notice for 5,000 dropped lines followed by the newest 10,000 lines in order

### Requirement: Instance actions
The client SHALL let the admin create, install, start, stop and delete instances, and SHALL show each resulting operation's steps and progress until it ends.

#### Scenario: Start from the client
- **WHEN** the admin starts a stopped instance from the client
- **THEN** the client calls `Start`, shows the operation's steps as they arrive, and shows the instance `running` once the daemon reports it

### Requirement: Multiple paired daemons
The client SHALL list paired daemons (plus an optional loopback development daemon) with name, address and state (`connected`, `connecting`, `offline`, `incompatible`, `revoked`, `expired`). It SHALL connect to each with the `System.GetInfo` negotiation, mark one with no shared API major `incompatible`, and reconnect with backoff (1 s, doubling to 30 s), fetching a fresh instance snapshot and resuming streams.

#### Scenario: Two daemons online
- **WHEN** the client starts with two paired daemons that are reachable
- **THEN** both are listed as `connected` with their instances grouped under each

#### Scenario: Daemon restarted
- **WHEN** a daemon restarts while the client shows one of its running instances
- **THEN** the client shows that daemon as `connecting`, reconnects once it is back, and shows the instance's current state from a fresh `WatchInstances` snapshot without the client being restarted

#### Scenario: Daemon offline
- **WHEN** one daemon is unreachable
- **THEN** it is listed `offline` with the last error and last-seen time, the other daemon remains usable, and reconnection is retried

#### Scenario: Device revoked
- **WHEN** a daemon rejects the client with `device_revoked`
- **THEN** the daemon is listed `revoked`, the client stops reconnecting to it, and offers to pair again

#### Scenario: No shared API version
- **WHEN** a daemon's `System.GetInfo` lists no API major the client supports
- **THEN** the daemon is listed `incompatible` and the client makes no further calls to it

### Requirement: Pairing from the client
The client SHALL pair a daemon from a pairing string, generating a device key per daemon that it keeps only in the OS keychain, together with the daemon's CA and its client certificate.

#### Scenario: Pair a new daemon
- **WHEN** the admin pastes a valid pairing string and enters a device name
- **THEN** the daemon is added as `connected`, and the only key material sent to the daemon is the CSR (the private key stays in the keychain)

#### Scenario: Malformed pairing string
- **WHEN** the admin pastes text that is not a pairing string
- **THEN** the client shows `invalid_pairing_string` and makes no network call

#### Scenario: Pairing code rejected
- **WHEN** the daemon answers the enrollment with `pairing_code_invalid`
- **THEN** the client shows that the code expired or was used, adds no daemon, and removes the key it generated

### Requirement: Device certificate renewal by the client
The client SHALL renew its certificate with each daemon when fewer than 30 days of validity remain, on connect and daily while connected, at most once per 24 hours per daemon by the client's clock. If renewal is refused or the certificate has expired, it SHALL show the daemon as `expired` and offer to pair again.

#### Scenario: Renewal on connect
- **WHEN** the client connects to a daemon with 20 days left on its certificate
- **THEN** it renews, stores the new certificate in the keychain, and switches to a connection that presents the new certificate while the daemon stays `connected`

#### Scenario: Certificate already expired
- **WHEN** the client's certificate for a daemon has expired
- **THEN** the daemon is listed `expired` without contacting the daemon, and the client offers re-pairing instead of retrying

### Requirement: Operations and interactive prompts
The client SHALL prompt the admin when an operation asks for input (a Steam Guard code or a mobile approval), on every connected device, and SHALL send the answer back to the daemon for that operation.

#### Scenario: Steam Guard prompt
- **WHEN** an operation enters `waiting_for_input` with a prompt of kind `authenticator`
- **THEN** the client shows a code entry dialog naming the Steam account, and submits the code to that operation

#### Scenario: Mobile approval prompt
- **WHEN** an operation's prompt has kind `mobile_approval`
- **THEN** the client shows a notice naming the account and the time left, with no code field, and a cancel action for the operation

#### Scenario: Prompt from another device's operation
- **WHEN** another device starts adding a Steam account and the operation raises a prompt
- **THEN** this client also shows the prompt dialog for it, without having watched that operation

#### Scenario: Prompt answered elsewhere
- **WHEN** another client answers the same prompt first
- **THEN** this client's dialog closes and shows that the prompt was answered by the other device

#### Scenario: Code rejected
- **WHEN** the daemon fails the operation with `steam_guard_invalid` after the code is submitted
- **THEN** the dialog closes and the operation shows the failure with an action to try adding the account again

### Requirement: Steam accounts view
The client SHALL list each daemon's Steam accounts with status and the instances that use them, and SHALL let the admin add an account (username, password, remember password), re-enter the password of a `reauth_required` account, remove an account, and link an account to an instance.

#### Scenario: Account added from the desktop
- **WHEN** the admin adds `srvadmin` with a password and answers the Steam Guard prompt
- **THEN** the account appears as `ready`, the password field is empty once the call is sent, and the client stores the password nowhere

#### Scenario: Account needs re-login
- **WHEN** an account's status is `reauth_required`
- **THEN** the account row shows a re-login action that opens the password entry for that account

#### Scenario: Removal refused
- **WHEN** the admin removes an account and the daemon answers `account_in_use`
- **THEN** the account stays listed and the client names the instances that use it

### Requirement: Mods view
The client SHALL show an instance's mods in load order per role with name, status, versions, update flag and warnings, and SHALL let the admin add workshop items by id or link, remove, reorder and change roles, apply, check for updates and update.

#### Scenario: Mods added by id
- **WHEN** the admin pastes 12 workshop ids and saves
- **THEN** the client calls `SetMods` with the full ordered list, and the 12 mods are shown as `pending` with their names once the daemon has their metadata

#### Scenario: Key conflict shown
- **WHEN** a mod carries the `key_conflict` warning
- **THEN** its row shows the warning naming the key file

#### Scenario: Concurrent edit
- **WHEN** another device changed the mod list after this view loaded it
- **THEN** saving fails with `revision_conflict`, the client reloads the list, and the admin's unsaved changes are shown for re-applying

### Requirement: Config and plugin notices
The client SHALL show an instance's `external_edit` events (file and overwritten keys, with masked values as received) and its `settings_invalid` flag (with the invalid fields) on the instance.

#### Scenario: External edit shown
- **WHEN** a start emits `external_edit` for `serverDZ.cfg` listing `maxPlayers` with old value 60
- **THEN** the instance shows a notice naming the file, the key and the old and new values

#### Scenario: Settings invalid after a reload
- **WHEN** an instance has flag `settings_invalid` naming `maxPlayers`
- **THEN** the instance shows the flag, its start action is disabled, and opening settings highlights `maxPlayers`
