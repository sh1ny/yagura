# Spec Delta

## ADDED Requirements

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
