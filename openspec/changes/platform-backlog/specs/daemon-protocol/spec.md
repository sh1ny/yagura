# Spec Delta

## Purpose

Defines the contract between the desktop client and the daemon: services, versioning, error reporting, long-running operation streams and how plugin-shaped data is carried.

## MODIFIED Requirements

### Requirement: Long operations are asynchronous with resumable progress
Calls that start lifecycle work SHALL return an operation id immediately. `WatchOperation` SHALL stream ordered, numbered events and accept `after_sequence` so a reconnecting client gets only what it missed. If some missed events are no longer retained, the stream SHALL start with an `events_dropped` marker giving the skipped range, then the current operation snapshot.

#### Scenario: Reconnect without losing events
- **WHEN** a client watching an install loses its connection after event 17 and reconnects with `after_sequence: 17`
- **THEN** it receives events from 18 onward, including any emitted while it was disconnected

#### Scenario: Missed events no longer retained
- **WHEN** a client resumes with `after_sequence: 10` and events 11-2400 are no longer retained
- **THEN** the stream starts with `events_dropped` from 11 to 2400, then the current operation including any pending prompt, then live events

#### Scenario: Resume across coalesced progress
- **WHEN** a client resumes with `after_sequence: 17` and the progress events 18-40 of one step were coalesced into event 40 while it was disconnected
- **THEN** it receives every retained event after 17 that is not progress, and event 40 as the latest progress of that step, with no `events_dropped` marker

#### Scenario: Operation pruned from history
- **WHEN** a client watches an operation id that was pruned
- **THEN** the call fails with `NOT_FOUND` reason `operation_expired`

### Requirement: Instance state and event stream
`WatchInstances` SHALL stream a snapshot of all instances followed by changes (state, health, operations, mod update counts); deltas carry settings only when settings changed, so a client never needs to poll.

#### Scenario: Snapshot then deltas
- **WHEN** a client subscribes and then another client starts instance `A`
- **THEN** the subscriber first receives the full instance list, then a delta with `A` in `starting` and later `running`

#### Scenario: State-only delta
- **WHEN** an instance's health changes but its settings do not
- **THEN** the delta carries the new health with `settings_omitted: true` and no settings document

#### Scenario: Slow subscriber
- **WHEN** a subscriber stops reading and 1,000 events or 8 MiB queue for it, whichever comes first
- **THEN** the daemon drops its backlog, sends a `resync_required` event when the subscriber reads again, and follows it with a fresh snapshot
