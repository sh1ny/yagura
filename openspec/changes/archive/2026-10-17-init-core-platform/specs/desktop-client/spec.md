# Spec Delta

## Purpose

Gives the admin a desktop application for a Yagura daemon, rendering each game's settings from its plugin schema and showing operations and logs live. This version connects to one daemon over the development connection.

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

### Requirement: Connection to one daemon
The client SHALL connect to one daemon, call `System.GetInfo` first and use the highest API major both support, show the daemon as `incompatible` and make no further calls when they share none, and after the connection drops reconnect with backoff (1 s, doubling to 30 s), fetch a fresh instance snapshot and resume its streams.

#### Scenario: Daemon restarted
- **WHEN** the daemon restarts while the client shows a running instance
- **THEN** the client shows the daemon as reconnecting, reconnects once the daemon is back, and shows the instance's current state from a fresh `WatchInstances` snapshot without the client being restarted

### Requirement: Instance actions
The client SHALL let the admin create, install, start, stop and delete instances, and SHALL show each resulting operation's steps and progress until it ends.

#### Scenario: Start from the client
- **WHEN** the admin starts a stopped instance from the client
- **THEN** the client calls `Start`, shows the operation's steps as they arrive, and shows the instance `running` once the daemon reports it
