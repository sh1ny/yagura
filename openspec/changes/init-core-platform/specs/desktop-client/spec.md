# Spec Delta

## Purpose

Gives the admin one desktop application to manage several Yagura daemons, rendering each game's settings from its plugin schema and showing operations, prompts, logs and consoles live.

## ADDED Requirements

### Requirement: Forms rendered from plugin schemas
The client SHALL render instance settings from the plugin's settings schema: an input per type, nested groups for objects, grouping and an advanced section, client-side validation with the schema's constraints, and the daemon's field errors shown on the fields.

#### Scenario: Daemon rejects a value
- **WHEN** the daemon returns a field violation for `ports.game`
- **THEN** the error is shown under the port field and the other edits stay in the form

#### Scenario: Unknown field type
- **WHEN** a schema contains a type the client does not know
- **THEN** the field is shown read-only with its raw JSON value and a notice, and the rest of the form works

### Requirement: Logs and console views
The client SHALL show each instance's log sources with backlog and live follow, search within the loaded lines, and pause.

#### Scenario: Follow and pause
- **WHEN** the admin pauses a live log view
- **THEN** new lines are counted but not appended until resume, and on resume the view shows them in order

#### Scenario: Dropped lines marker
- **WHEN** the daemon sends a `dropped` marker
- **THEN** the view shows an inline notice with the number of skipped lines
