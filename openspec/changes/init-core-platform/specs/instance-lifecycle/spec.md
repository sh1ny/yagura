# Spec Delta

## Purpose

Lets an admin create game server instances from plugins, install and run them, and keeps their state correct and durable across operations, crashes and daemon restarts.

## ADDED Requirements

### Requirement: Instance creation validates settings against the plugin schema
The daemon SHALL create an instance only when the plugin exists, the settings validate (defaults filled in), the ports collide with no other instance's ports or the daemon's API port, and the directory is allowed (under a configured instance root, overlapping no other instance or daemon directory). Creates are serialised. A new instance starts `not_installed`.

#### Scenario: Valid instance created
- **WHEN** a client creates an instance of plugin `valheim` with name `Friends` and settings that satisfy the schema
- **THEN** the response carries a new instance id, state `not_installed`, every unspecified setting set to its default, and the directory `instances/<id>/` exists

#### Scenario: Setting violates the schema
- **WHEN** a client creates an instance with `maxPlayers: 500` where the schema's maximum is 127
- **THEN** the call fails with `INVALID_ARGUMENT`, the error lists the field path `maxPlayers` and the constraint, and no instance row or directory is created

#### Scenario: Directory outside the instance roots
- **WHEN** a client creates an instance with directory `D:\`
- **THEN** the call fails with `INVALID_ARGUMENT` reason `directory_not_allowed`, and no directory is created

#### Scenario: Port equal to the daemon API port
- **WHEN** a client creates an instance with a port equal to the daemon's API port
- **THEN** the call fails with `FAILED_PRECONDITION` reason `port_conflict` naming the daemon API

#### Scenario: Port collision with another instance
- **WHEN** a client creates an instance whose game port 2456/udp is already assigned to another instance
- **THEN** the call fails with `FAILED_PRECONDITION` naming the conflicting instance and port, and no instance is created

### Requirement: Instance state machine
Each instance SHALL be in exactly one state: `not_installed`, `installing`, `stopped`, `starting`, `running`, `stopping`, `updating` or `error`. Only the transitions defined by the daemon's lifecycle operations are allowed; an operation requested in a state that does not allow it is rejected without side effects.

#### Scenario: Start from stopped
- **WHEN** a client starts an instance in state `stopped`
- **THEN** the instance moves to `starting`, then to `running` once its health check passes, and each transition is emitted on the instance's state stream

#### Scenario: Start while not installed
- **WHEN** a client starts an instance in state `not_installed`
- **THEN** the call fails with `FAILED_PRECONDITION` and reason `not_installed`, and the state stays `not_installed`

#### Scenario: Process exits during the health window
- **WHEN** the started server process exits before its health check passes (for example a bootstrapper executable that spawns another process and exits)
- **THEN** the instance becomes `stopped`, the operation fails with `launch_failed` and the exit code, and no restart is attempted

#### Scenario: Health check never passes
- **WHEN** a started instance's health check has not passed within the plugin's `start_timeout` (default 300 s) while the process is still alive
- **THEN** the instance moves to `running` with a `health: unknown` flag and a warning event, and the process is not killed

### Requirement: One operation per instance at a time
The daemon SHALL run at most one lifecycle operation per instance at a time and SHALL queue further requests in arrival order, reporting their queue position. At most 4 heavy operations (install, update, validate) run at once across the host; further ones wait in the queue.

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

### Requirement: Operations report progress and can be cancelled
Every lifecycle operation SHALL have an id, a status (`queued`, `running`, `succeeded`, `failed`, `cancelled`), step progress and a terminal message, kept in history. Cancelling stops the current step at a safe point and leaves the instance in a defined state.

#### Scenario: Install progress streamed
- **WHEN** a client watches an install operation for a 5 GB app
- **THEN** it receives step events (`steam_login`, `download`, `post_install`) with percent and bytes for the download step, and a final event with status `succeeded`

#### Scenario: Install cancelled mid-download
- **WHEN** a client cancels an install while SteamCMD is downloading
- **THEN** SteamCMD is terminated within 10 s, the operation ends `cancelled`, and the instance returns to `not_installed`

#### Scenario: Update cancelled after the server was stopped
- **WHEN** a client cancels an update of a running instance after its `stop` step completed
- **THEN** the operation ends `cancelled`, the instance is `stopped` (not restarted), and the `pre_update` snapshot is kept

#### Scenario: Stop cancels queued starts
- **WHEN** a Start and a Restart are queued for an instance and a client requests Stop
- **THEN** the queued Start and Restart end `cancelled`, the Stop runs next, and queued Install or Update operations stay queued

### Requirement: Interrupted operations are reported after a daemon restart
When the daemon starts, it SHALL mark every operation left `queued` or `running` as `interrupted`, move instances out of transient states (`installing` to `not_installed`; `updating` to `error` with reason `update_interrupted`; `starting`, `running` or `stopping` to the result of re-attach), and emit a notice per affected instance.

#### Scenario: Daemon killed during an update
- **WHEN** the daemon process is killed while an update operation is downloading
- **THEN** after restart the operation shows `interrupted`, the instance is `error` with `update_interrupted`, and no SteamCMD process from before the restart is still running

#### Scenario: Daemon killed during install
- **WHEN** the daemon is killed during an install
- **THEN** after restart the instance is `not_installed` with notice `install_interrupted` and a new install can be started

### Requirement: Updates stop and restart a running server
An update or validate of a running instance SHALL stop it with its stop strategy, snapshot its data paths, update the app, re-apply the configuration, and start it again; an update of a stopped instance leaves it stopped.

#### Scenario: Update while running
- **WHEN** a client updates a running instance
- **THEN** the operation steps are `stop`, `snapshot`, `download`, `apply_config`, `start`, and the instance ends `running`

#### Scenario: Update fails after stop
- **WHEN** the download step fails for a running instance
- **THEN** the instance is `error` with the failure reason, it is not started again, and the snapshot is kept

### Requirement: Crash detection and restart policy
The daemon SHALL detect when a `running` instance's process exits without a stop request, record the exit code and the last 50 log lines, and apply the instance's restart policy (`never`, or `on_crash` with at most 3 restarts within 10 minutes, default `on_crash`).

#### Scenario: Crash is restarted
- **WHEN** a running instance with policy `on_crash` exits with code 1 for the first time
- **THEN** a `crashed` event with exit code and last log lines is emitted and the daemon starts the instance again within 10 s

#### Scenario: Crash loop stops restarting
- **WHEN** the same instance crashes a fourth time within 10 minutes
- **THEN** it is not restarted, its state becomes `error` with reason `crash_loop`, and a `crash_loop` event is emitted

### Requirement: Running servers survive daemon restarts
Game server processes SHALL keep running when the daemon stops, crashes or is upgraded. On startup the daemon SHALL re-attach to each instance recorded as running only if a process with the recorded PID, executable path and start time exists.

#### Scenario: Re-attach after daemon restart
- **WHEN** the daemon restarts while instance `A`'s server process is still running with the recorded PID, executable and start time
- **THEN** instance `A` is reported `running` without being restarted, and its log stream resumes from the recorded file offsets

#### Scenario: PID reused by another process
- **WHEN** the daemon starts and the recorded PID of instance `A` now belongs to a process with a different executable or start time
- **THEN** instance `A` is reported `stopped` with a `lost_while_daemon_down` event, and the unrelated process is not touched

### Requirement: Graceful stop per plugin strategy
Stopping SHALL follow the plugin's stop strategy (`signal` (Linux SIGTERM / Windows Ctrl+C to the server's console), or `kill`), wait up to the grace period, then kill the process if it is still alive, and report which step ended it.

#### Scenario: Valheim saves on a signal stop
- **WHEN** a client stops a running Valheim instance started by `yagurad run --console` whose strategy is `signal`
- **THEN** the server receives Ctrl+C, its world save file is written before the process exits, and the result reports `stopped_by: graceful`

#### Scenario: Grace period exceeded
- **WHEN** the process is still alive when the grace period ends
- **THEN** the daemon kills the process, the instance becomes `stopped`, and the operation result reports `stopped_by: kill`

### Requirement: Durable state with a portable instance file
The daemon SHALL persist instances, settings, mods and operations in its database before acknowledging a change, and SHALL write `instance.json` (plugin id and version, settings, mods, ports, `format_version: 1`, no secret values) into the instance directory after every committed change.

#### Scenario: Change persisted and mirrored
- **WHEN** a client changes `hostname` on an instance and the call returns success
- **THEN** a daemon restart still shows the new hostname, and `instance.json` contains it

#### Scenario: instance.json write fails
- **WHEN** the database commit succeeds but writing `instance.json` fails (for example the disk is full)
- **THEN** the call succeeds, a `instance_file_stale` warning event is emitted, and the file is rewritten at the next change or daemon start

#### Scenario: Secrets excluded from instance.json
- **WHEN** an instance has an RCON password and a GSLT set
- **THEN** `instance.json` contains `"rconPassword": {"secret": true}` placeholders and neither secret value appears anywhere in the file

### Requirement: Save data is declared and snapshotted
Instances SHALL keep save data in the plugin's `data_paths`, inside the instance directory. The daemon SHALL snapshot them before every update (unless the request skips it, which the operation result records) and before a delete with files, keep the last 3 per instance and pre-delete snapshots of deleted instances for 30 days, and refuse the operation when the snapshots volume lacks the space.

#### Scenario: Snapshot before update
- **WHEN** an update starts for a Valheim instance whose `data_paths` is `save/`
- **THEN** a snapshot `pre_update` containing `save/` is listed for the instance before the download begins

#### Scenario: Not enough space for a snapshot
- **WHEN** free space on the snapshots volume is less than twice the size of the data paths
- **THEN** the update fails with `insufficient_disk` before stopping the server, and nothing is changed

#### Scenario: Restore a snapshot
- **WHEN** a client restores a snapshot of a stopped instance
- **THEN** the data paths are replaced by the snapshot's contents and a new `pre_restore` snapshot of the replaced data is kept

#### Scenario: Restoring the oldest snapshot
- **WHEN** an instance has 3 snapshots and the oldest is restored
- **THEN** the restore completes from that snapshot, and pruning for the new `pre_restore` snapshot removes the oldest only after the restore ends

#### Scenario: Snapshot skipped on request
- **WHEN** an update is requested with `skip_snapshot`
- **THEN** no snapshot is taken, and the operation result shows `snapshot: skipped`

#### Scenario: Pre-delete snapshot of a deleted instance
- **WHEN** an instance was deleted with files 2 days ago
- **THEN** its `pre_delete` snapshot is listed by `ListOrphanSnapshots` with the instance name, and it is removed 30 days after the delete

### Requirement: Deleting an instance protects game data
Deleting an instance SHALL require it to be `stopped`, `not_installed` or `error` with no running operation and SHALL remove its database rows; its directory is removed only when the request sets `delete_files: true` and repeats the instance name as confirmation.

#### Scenario: Delete with files snapshots first
- **WHEN** a client deletes a stopped instance with `delete_files: true` and the correct confirmation
- **THEN** a `pre_delete` snapshot of its data paths is written to the snapshots directory, then the instance directory is removed

#### Scenario: Delete an instance whose plugin is missing
- **WHEN** an instance in `error` with `plugin_missing` is deleted without `delete_files`
- **THEN** it disappears from listings and its directory is left on disk

#### Scenario: Delete keeping files
- **WHEN** a client deletes a stopped instance without `delete_files`
- **THEN** the instance disappears from listings and its directory with world saves is left on disk

#### Scenario: Delete with wrong confirmation
- **WHEN** a client deletes with `delete_files: true` and a confirmation that does not match the instance name
- **THEN** the call fails with `INVALID_ARGUMENT` and nothing is deleted

### Requirement: Error reasons have defined exits
An instance in `error` SHALL carry a reason, and only the exits defined for that reason are allowed: `crash_loop` leaves by Start or Acknowledge; `update_interrupted` and update failures by Update, Validate or Acknowledge; `settings_invalid` by saving valid settings; `plugin_missing` by a reload that restores the plugin. Stop and Delete are allowed from any reason when no operation runs; other requests fail with `invalid_state`.

#### Scenario: Acknowledge a crash loop
- **WHEN** a client acknowledges an instance in `error` with `crash_loop`
- **THEN** the instance becomes `stopped` and its restart counter is reset

#### Scenario: Start refused with invalid settings
- **WHEN** a client starts an instance in `error` with `settings_invalid`
- **THEN** the call fails with `FAILED_PRECONDITION` reason `invalid_state` naming `settings_invalid`, and the state is unchanged

#### Scenario: Update clears an interrupted update
- **WHEN** a client updates an instance in `error` with `update_interrupted` and the update succeeds
- **THEN** the instance ends `stopped` and the error reason is cleared

### Requirement: Autostart after daemon or host restart
Each instance SHALL have an `autostart` setting (default on). After a daemon or host restart, an instance that was last requested to run and is not running after re-attach SHALL be started through a normal Start, one instance every 10 seconds, subject to its restart policy.

#### Scenario: Host rebooted
- **WHEN** the host reboots while two instances with `autostart` on are running
- **THEN** after the daemon starts both are started again, 10 s apart, and each shows an `autostarted` notice

#### Scenario: Instance stopped by the admin before the reboot
- **WHEN** an instance was stopped by a client before the reboot
- **THEN** it stays `stopped` after the daemon starts

#### Scenario: Crash-looped instance not autostarted
- **WHEN** an instance is in `error` with `crash_loop` and the daemon restarts
- **THEN** it stays in `error` and is not started

#### Scenario: Autostart fails
- **WHEN** an autostarted instance's start fails
- **THEN** the failure is handled like any failed Start and the instance is not retried beyond its restart policy
