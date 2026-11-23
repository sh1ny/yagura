# Spec Delta

## ADDED Requirements

### Requirement: Pending prompts reach every client
`Operations.WatchPrompts` SHALL stream a snapshot of every pending prompt (with its operations and their instance or account), then each prompt raised or resolved. `RespondToPrompt` SHALL accept the first valid answer to a pending prompt and refuse every later one.

#### Scenario: Snapshot then raised and resolved
- **WHEN** a client subscribes while one prompt is pending, and another operation then raises a prompt that a second client answers
- **THEN** the subscriber receives the pending prompt, then the raised prompt, then its resolution naming the answering device

#### Scenario: Late answer refused
- **WHEN** a client answers a prompt that another client already answered
- **THEN** the call fails with `FAILED_PRECONDITION` reason `prompt_resolved`, and the first answer stands

#### Scenario: Malformed answer
- **WHEN** a client answers an email prompt with a 40-character value
- **THEN** the call fails with `INVALID_ARGUMENT` reason `prompt_answer_invalid`, and the prompt stays pending

#### Scenario: Too many prompt watchers
- **WHEN** 32 clients already watch prompts and another subscribes
- **THEN** the call fails with `RESOURCE_EXHAUSTED` reason `too_many_subscribers`

## MODIFIED Requirements

### Requirement: Long operations are asynchronous with resumable progress
Calls that start lifecycle work SHALL return an operation id immediately. `WatchOperation` SHALL stream ordered, numbered events and accept `after_sequence` so a reconnecting client gets only what it missed. If some missed events are no longer retained, the stream SHALL start with an `events_dropped` marker giving the skipped range, then the current operation snapshot, including any pending prompt.

#### Scenario: Reconnect without losing events
- **WHEN** a client watching an install loses its connection after event 17 and reconnects with `after_sequence: 17`
- **THEN** it receives events from 18 onward, including any emitted while it was disconnected

#### Scenario: Missed events no longer retained
- **WHEN** a client resumes with `after_sequence: 10` and events 11-2400 are no longer retained
- **THEN** the stream starts with `events_dropped` from 11 to 2400, then the current operation including any pending prompt, then live events

#### Scenario: Pending prompt after reconnect
- **WHEN** a client reconnects to an operation waiting for a Steam Guard code whose prompt event it missed
- **THEN** the operation it receives carries the pending prompt with its id, kind, account and expiry, and the client can answer it

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

#### Scenario: Mod update count delta
- **WHEN** a scheduled update check flags 2 of instance `A`'s mods `update_available`
- **THEN** subscribers receive a delta for `A` with `mod_updates_available: 2` and `settings_omitted: true`

#### Scenario: State-only delta
- **WHEN** an instance's health changes but its settings do not
- **THEN** the delta carries the new health with `settings_omitted: true` and no settings document

#### Scenario: Slow subscriber
- **WHEN** a subscriber stops reading and 1,000 events or 8 MiB queue for it, whichever comes first
- **THEN** the daemon drops its backlog, sends a `resync_required` event when the subscriber reads again, and follows it with a fresh snapshot

### Requirement: Methods a daemon version does not implement
A call to a method that the daemon version does not implement, including every method of a service it does not build yet, SHALL fail with `UNIMPLEMENTED` reason `not_implemented` and change nothing. `docs/protocol.md` SHALL list the methods each daemon version implements.

#### Scenario: Method not built yet
- **WHEN** a client calls `Instances.ExportInstance` on a daemon that does not implement it
- **THEN** the call fails with `UNIMPLEMENTED` reason `not_implemented`, and nothing changes

#### Scenario: Service not built yet
- **WHEN** a client calls `Rcon.Execute` on a daemon that does not build RCON
- **THEN** the call fails with `UNIMPLEMENTED` and an error detail with reason `not_implemented`
