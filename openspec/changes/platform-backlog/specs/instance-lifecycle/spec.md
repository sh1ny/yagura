# Spec Delta

## Purpose

Lets an admin create game server instances from plugins, install and run them, and keeps their state correct and durable across operations, crashes and daemon restarts.

## ADDED Requirements

### Requirement: Import and export instances
The daemon SHALL export an instance as its directory's `instance.json` and SHALL import a directory containing a valid `instance.json` as a new instance, validating it like a create and listing the secrets that must be re-entered.

#### Scenario: Import a copied instance
- **WHEN** a client imports `D:/servers/dayz-main`, under a configured instance root and containing a valid `instance.json` for an installed plugin
- **THEN** a new instance is created in state `stopped` pointing at that directory with the game-server account's access set, and the response lists `rconPassword` as a secret to set

#### Scenario: Import with unknown plugin version
- **WHEN** the `instance.json` names plugin `dayz` version `3.0.0` and the installed plugin's settings schema rejects its settings
- **THEN** the import fails with `FAILED_PRECONDITION`, the error lists each invalid field, and no instance is created

## MODIFIED Requirements

### Requirement: Graceful stop per plugin strategy
Stopping SHALL follow the plugin's stop strategy (`rcon` command, `signal` (Linux SIGTERM / Windows Ctrl+C to the server's console), or `kill`), wait up to the grace period, then kill the process if it is still alive, and report which step ended it.

#### Scenario: Valheim saves on a signal stop
- **WHEN** a client stops a running Valheim instance started by `yagurad run --console` whose strategy is `signal`
- **THEN** the server receives Ctrl+C, its world save file is written before the process exits, and the result reports `stopped_by: graceful`

#### Scenario: RCON unavailable during stop
- **WHEN** the stop strategy is `rcon` and the RCON session cannot authenticate
- **THEN** the daemon waits out the grace period, kills the process, and the result reports `stopped_by: kill` with reason `rcon_unavailable`

#### Scenario: Graceful RCON shutdown
- **WHEN** a client stops a running DayZ instance whose strategy is `rcon` with `#shutdown` and grace 60 s
- **THEN** the daemon sends `#shutdown` over RCON, the process exits within the grace period, and the operation result reports `stopped_by: graceful`

#### Scenario: Grace period exceeded
- **WHEN** the process is still alive when the grace period ends
- **THEN** the daemon kills the process, the instance becomes `stopped`, and the operation result reports `stopped_by: kill`

### Requirement: One operation per instance at a time
The daemon SHALL run at most one lifecycle operation per instance at a time and SHALL queue further requests in arrival order, reporting their queue position. At most 4 heavy operations (install, update, validate, apply_mods, update_mods) run at once across the host; further ones wait in the queue.

#### Scenario: Concurrent requests on one instance
- **WHEN** a client requests `Update` on an instance while its `Install` operation is running
- **THEN** the update returns an operation id with status `queued` and position 1, and it starts only after the install operation ends

#### Scenario: Stop requested while starting
- **WHEN** a client stops an instance whose `Start` operation is running a pre-start step
- **THEN** the start is cancelled at its next step boundary, the stop runs next, and the instance ends `stopped`

#### Scenario: Stop during the health wait
- **WHEN** a client stops an instance whose server process is running but whose health check has not passed yet
- **THEN** the health wait is interrupted at once and the instance is `stopped` within the plugin's grace period

#### Scenario: Queued operation becomes invalid
- **WHEN** a queued `Start` reaches the head of the queue but the instance is now `not_installed` because the install ahead of it was cancelled
- **THEN** the operation ends `failed` with reason `invalid_state` and the instance stays `not_installed`

#### Scenario: Queue full
- **WHEN** an instance already has 10 queued operations and another is requested
- **THEN** the call fails with `RESOURCE_EXHAUSTED` reason `queue_full` and no operation is created

### Requirement: Updates stop and restart a running server
An update or validate of a running instance SHALL stop it with its stop strategy, snapshot its data paths, update the app and any mods with updates, re-apply bindings, and start it again; an update of a stopped instance leaves it stopped.

#### Scenario: Update while running
- **WHEN** a client updates a running instance
- **THEN** the operation steps are `stop`, `snapshot`, `download`, `update_mods`, `apply_config`, `start`, and the instance ends `running`

#### Scenario: Update fails after stop
- **WHEN** the download step fails for a running instance
- **THEN** the instance is `error` with the failure reason, it is not started again, and the snapshot is kept

### Requirement: Durable state with a portable instance file
The daemon SHALL persist instances, settings, mods and operations in its database before acknowledging a change, and SHALL write `instance.json` (plugin id and version, settings, mods, ports, `format_version: 1`, secret settings as placeholders) into the instance directory after every committed change.

#### Scenario: Change persisted and mirrored
- **WHEN** a client changes `hostname` on an instance and the call returns success
- **THEN** a daemon restart still shows the new hostname, and `instance.json` contains it

#### Scenario: instance.json write fails
- **WHEN** the database commit succeeds but writing `instance.json` fails (for example the disk is full)
- **THEN** the call succeeds, a `instance_file_stale` warning event is emitted, and the file is rewritten at the next change or daemon start

#### Scenario: Secrets excluded from instance.json
- **WHEN** an instance's plugin declares a `secret` setting `rconPassword`
- **THEN** `instance.json` contains `"rconPassword": {"secret": true}` and no other value for it

