# daemon-protocol Specification

## Purpose

Defines the contract between the desktop client and the daemon: services, versioning, error reporting, long-running operation streams and how plugin-shaped data is carried.

## Requirements

### Requirement: API version negotiation
The daemon SHALL report its `daemon_version` and every API version it serves (`major.minor`) in `System.GetInfo`. A client SHALL use the highest major both support, refuse a daemon sharing no major, and hide features newer than the daemon's minor version.

#### Scenario: Compatible versions
- **WHEN** a client with API 1.3 connects to a daemon reporting API 1.5
- **THEN** the client shows the daemon as connected and enables features up to 1.3

#### Scenario: Incompatible major
- **WHEN** a client with API 1.x connects to a daemon serving only API 2.0
- **THEN** the client shows the daemon as `incompatible` with both versions and makes no further calls to it

#### Scenario: Overlap during a migration
- **WHEN** a client with API 1.x connects to a daemon serving 1.9 and 2.0
- **THEN** the client manages it over API 1.9

### Requirement: Structured errors
Every failed call SHALL return a gRPC status code and an error detail with a stable machine-readable `reason`, a human message, and field violations when input was invalid. Reasons are documented with the proto and never reused for another meaning.

#### Scenario: Field violation detail
- **WHEN** a settings update fails validation on two fields
- **THEN** the status is `INVALID_ARGUMENT` and the detail lists both field paths with their constraint descriptions

#### Scenario: Unexpected internal failure
- **WHEN** an unhandled exception occurs in the daemon while serving a call
- **THEN** the status is `INTERNAL` with reason `internal_error` and an incident id, and the daemon log contains the same incident id with the stack trace

### Requirement: Long operations are asynchronous with resumable progress
Calls that start lifecycle work SHALL return an operation id immediately. `WatchOperation` SHALL stream ordered, numbered events and accept `after_sequence` so a reconnecting client gets only what it missed. If some missed events are no longer retained, the stream SHALL start with an `events_dropped` marker giving the skipped range, then the current operation snapshot.

#### Scenario: Reconnect without losing events
- **WHEN** a client watching an install loses its connection after event 17 and reconnects with `after_sequence: 17`
- **THEN** it receives events from 18 onward, including any emitted while it was disconnected

#### Scenario: Missed events no longer retained
- **WHEN** a client resumes with `after_sequence: 10` and events 11-2400 are no longer retained
- **THEN** the stream starts with `events_dropped` from 11 to 2400, then the current operation, then live events

#### Scenario: Resume across coalesced progress
- **WHEN** a client resumes with `after_sequence: 17` and the progress events 18-40 of one step were coalesced into event 40 while it was disconnected
- **THEN** it receives every retained event after 17 that is not progress, and event 40 as the latest progress of that step, with no `events_dropped` marker

#### Scenario: Operation pruned from history
- **WHEN** a client watches an operation id that was pruned
- **THEN** the call fails with `NOT_FOUND` reason `operation_expired`

### Requirement: Instance state and event stream
`WatchInstances` SHALL stream a snapshot of all instances followed by changes (state, health, operations); deltas carry settings only when settings changed, so a client never needs to poll.

#### Scenario: Snapshot then deltas
- **WHEN** a client subscribes and then another client starts instance `A`
- **THEN** the subscriber first receives the full instance list, then a delta with `A` in `starting` and later `running`

#### Scenario: State-only delta
- **WHEN** an instance's health changes but its settings do not
- **THEN** the delta carries the new health with `settings_omitted: true` and no settings document

#### Scenario: Slow subscriber
- **WHEN** a subscriber stops reading and 1,000 events or 8 MiB queue for it, whichever comes first
- **THEN** the daemon drops its backlog, sends a `resync_required` event when the subscriber reads again, and follows it with a fresh snapshot

### Requirement: Plugin-shaped data as versioned JSON
Settings schemas, settings values and hook output shown to clients SHALL travel as JSON text fields accompanied by `schema_version`. The daemon SHALL validate incoming JSON fields against the plugin's current schema and reject values for a different `schema_version`.

#### Scenario: Stale form submission
- **WHEN** a client submits settings with `schema_version` 3 after the plugin reloaded to version 4
- **THEN** the call fails with `FAILED_PRECONDITION` reason `schema_version_mismatch` and the current version, and nothing is saved

#### Scenario: Malformed JSON
- **WHEN** a client submits `settings_json` that is not valid JSON
- **THEN** the call fails with `INVALID_ARGUMENT` reason `invalid_json` and the parse position

### Requirement: Message size limits
The daemon SHALL accept request messages up to 4 MiB and send response messages up to 16 MiB; larger payloads (backlogs, file listings) are paged.

#### Scenario: Oversized request
- **WHEN** a client sends a 10 MiB settings payload
- **THEN** the call fails with `RESOURCE_EXHAUSTED` and nothing is saved

#### Scenario: Paged backlog
- **WHEN** a client requests 5,000 backlog lines that exceed one message
- **THEN** they arrive across several stream messages in order with no line split between messages

### Requirement: Methods a daemon version does not implement
A call to a method that the daemon version does not implement, including every method of a service it does not build yet, SHALL fail with `UNIMPLEMENTED` reason `not_implemented` and change nothing. `docs/protocol.md` SHALL list the methods each daemon version implements.

#### Scenario: Method not built yet
- **WHEN** a client calls `Instances.ExportInstance` on a daemon that does not implement it
- **THEN** the call fails with `UNIMPLEMENTED` reason `not_implemented`, and nothing changes

#### Scenario: Service not built yet
- **WHEN** a client calls `Mods.ListMods` on a daemon that does not build mods
- **THEN** the call fails with `UNIMPLEMENTED` and an error detail with reason `not_implemented`
