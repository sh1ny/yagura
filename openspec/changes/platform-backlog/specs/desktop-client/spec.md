# Spec Delta

## Purpose

Gives the admin one desktop application to manage several Yagura daemons, rendering each game's settings from its plugin schema and showing operations, prompts, logs and consoles live.

## ADDED Requirements

### Requirement: Operations and interactive prompts
The client SHALL show running and queued operations with progress, and SHALL prompt the admin when an operation asks for input (Steam Guard code or mobile approval), sending the answer back to the daemon.

#### Scenario: Steam Guard prompt
- **WHEN** an operation enters `waiting_for_input` with a prompt of kind `authenticator`
- **THEN** the client shows a code entry dialog naming the Steam account, and submits the code to that operation

#### Scenario: Prompt answered elsewhere
- **WHEN** another client answers the same prompt first
- **THEN** this client's dialog closes and shows that the prompt was answered by the other device

## MODIFIED Requirements

### Requirement: Forms rendered from plugin schemas
The client SHALL render instance settings from the plugin's settings schema: an input per type, nested groups for objects, editable tables for lists, grouping and an advanced section, client-side validation with the schema's constraints, and the daemon's field errors shown on the fields.

#### Scenario: Repeatable list as a table
- **WHEN** an ARK:SA instance's settings are opened
- **THEN** `itemStackOverrides` is shown as a table with add, remove and reorder actions and one column per object field

#### Scenario: Daemon rejects a value
- **WHEN** the daemon returns a field violation for `ports.game`
- **THEN** the error is shown under the port field and the other edits stay in the form

#### Scenario: Unknown field type
- **WHEN** a schema contains a type the client does not know
- **THEN** the field is shown read-only with its raw JSON value and a notice, and the rest of the form works

### Requirement: Logs and console views
The client SHALL show each instance's log sources with backlog and live follow, search within the loaded lines, pause, and a console for RCON-capable instances with command history. While paused, a view SHALL hold up to 10,000 new lines; beyond that it drops the oldest held lines and shows their count on resume.

#### Scenario: Follow and pause
- **WHEN** the admin pauses a live log view
- **THEN** new lines are counted but not appended until resume, and on resume the view shows them in order

#### Scenario: Dropped lines marker
- **WHEN** the daemon sends a `dropped` marker
- **THEN** the view shows an inline notice with the number of skipped lines

#### Scenario: Pause longer than the buffer
- **WHEN** 15,000 lines arrive while a log view is paused
- **THEN** on resume the view shows a notice for 5,000 dropped lines followed by the newest 10,000 lines in order
