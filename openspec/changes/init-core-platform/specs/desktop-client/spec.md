# Spec Delta

## Purpose

Gives the admin one desktop application to manage several Garrison daemons, rendering each game's settings from its plugin schema and showing operations, prompts, logs and consoles live.

## ADDED Requirements

### Requirement: Multiple paired daemons
The client SHALL keep a list of paired daemons with name, address and connection state (`connected`, `connecting`, `offline`, `incompatible`, `revoked`, `expired`), connect to all of them, and reconnect with backoff up to 60 s.

#### Scenario: Two daemons online
- **WHEN** the client starts with two paired daemons that are reachable
- **THEN** both are listed as `connected` with their instances grouped under each

#### Scenario: Daemon offline
- **WHEN** one daemon is unreachable
- **THEN** it is listed `offline` with the last error and last-seen time, the other daemon remains usable, and reconnection is retried

#### Scenario: Device revoked
- **WHEN** a daemon rejects the client with `device_revoked`
- **THEN** the daemon is listed `revoked`, the client stops reconnecting to it, and offers to pair again

### Requirement: Pairing from the client
The client SHALL pair a daemon from a pairing string, generating its device key in the OS keychain, and SHALL store the daemon's CA and its client certificate there.

#### Scenario: Pair a new daemon
- **WHEN** the admin pastes a valid pairing string and enters a device name
- **THEN** the daemon is added as `connected`, and the only key material sent to the daemon is the CSR (the private key stays in the keychain)

#### Scenario: Malformed pairing string
- **WHEN** the admin pastes text that is not a pairing string
- **THEN** the client shows `invalid_pairing_string` and makes no network call

### Requirement: Forms rendered from plugin schemas
The client SHALL render instance settings from the plugin's settings schema: an input per type, nested groups for objects, editable tables for lists, grouping and an advanced section, client-side validation with the schema's constraints, and the daemon's field errors shown on the fields.

#### Scenario: Repeatable list as a table
- **WHEN** an ARK:SA instance's settings are opened
- **THEN** `itemStackOverrides` is shown as a table with add, remove and reorder actions and one column per object field

#### Scenario: Daemon rejects a value
- **WHEN** the daemon returns a field violation for `ports.game`
- **THEN** the error is shown under the port field and the other edits stay in the form

#### Scenario: Someone else saved first
- **WHEN** saving fails with `revision_conflict`
- **THEN** the client reloads the instance, shows which fields differ from the user's unsaved edits, and keeps the edits for the user to re-apply

#### Scenario: Unknown field type
- **WHEN** a schema contains a type the client does not know
- **THEN** the field is shown read-only with its raw JSON value and a notice, and the rest of the form works

### Requirement: Operations and interactive prompts
The client SHALL show running and queued operations with progress, and SHALL prompt the admin when an operation asks for input (Steam Guard code or mobile approval), sending the answer back to the daemon.

#### Scenario: Steam Guard prompt
- **WHEN** an operation enters `waiting_for_input` with a prompt of kind `authenticator`
- **THEN** the client shows a code entry dialog naming the Steam account, and submits the code to that operation

#### Scenario: Prompt answered elsewhere
- **WHEN** another client answers the same prompt first
- **THEN** this client's dialog closes and shows that the prompt was answered by the other device

### Requirement: Logs and console views
The client SHALL show each instance's log sources with backlog and live follow, search within the loaded lines, pause, and a console for RCON-capable instances with command history.

#### Scenario: Follow and pause
- **WHEN** the admin pauses a live log view
- **THEN** new lines are counted but not appended until resume, and on resume the view shows them in order

#### Scenario: Dropped lines marker
- **WHEN** the daemon sends a `dropped` marker
- **THEN** the view shows an inline notice with the number of skipped lines

### Requirement: Device certificate renewal by the client
The client SHALL renew its certificate with each daemon when fewer than 30 days of validity remain, on connect and daily while connected; if renewal is refused or the certificate has expired, it SHALL show the daemon as `expired` and offer to pair again.

#### Scenario: Renewal on connect
- **WHEN** the client connects to a daemon with 20 days left on its certificate
- **THEN** it renews, stores the new certificate in the keychain, and keeps the connection

#### Scenario: Certificate already expired
- **WHEN** the client's certificate for a daemon has expired
- **THEN** the daemon is listed `expired` and the client offers re-pairing instead of retrying
