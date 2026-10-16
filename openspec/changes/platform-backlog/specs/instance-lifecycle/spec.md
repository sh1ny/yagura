# Spec Delta

## Purpose

Lets an admin create game server instances from plugins, install and run them, and keeps their state correct and durable across operations, crashes and daemon restarts.

## ADDED Requirements

### Requirement: Concurrent edits are detected by revision
Each instance SHALL carry a revision that increments only on configuration changes (settings, ports, secrets, mods, restart policy, autostart, Steam account, snapshot restore). Configuration calls SHALL include the revision the caller last read; a stale revision fails with `FAILED_PRECONDITION` reason `revision_conflict` and changes nothing.

#### Scenario: Two clients edit the same instance
- **WHEN** clients A and B both read revision 7, A saves settings (revision becomes 8), then B saves with expected revision 7
- **THEN** B's call fails with `revision_conflict` and the current revision 8, and A's settings are unchanged

#### Scenario: Runtime state does not change the revision
- **WHEN** an instance crashes, restarts and changes health while a client has revision 7 loaded
- **THEN** the revision is still 7 and the client's next settings save succeeds

#### Scenario: Autostart unchanged when omitted
- **WHEN** a client saves settings without setting `autostart`
- **THEN** the instance's `autostart` value is unchanged

#### Scenario: Current revision accepted
- **WHEN** a client saves with the current revision
- **THEN** the change is applied and the response carries the incremented revision

### Requirement: Import and export instances
The daemon SHALL export an instance as its directory's `instance.json` and SHALL import a directory containing a valid `instance.json` as a new instance, validating it like a create and listing the secrets that must be re-entered.

#### Scenario: Import a copied instance
- **WHEN** a client imports `D:/servers/dayz-main`, under a configured instance root and containing a valid `instance.json` for an installed plugin
- **THEN** a new instance is created in state `stopped` pointing at that directory with the game-server account's access set, and the response lists `rconPassword` as a secret to set

#### Scenario: Import with unknown plugin version
- **WHEN** the `instance.json` names plugin `dayz` version `3.0.0` and the installed plugin's settings schema rejects its settings
- **THEN** the import fails with `FAILED_PRECONDITION`, the error lists each invalid field, and no instance is created

### Requirement: Daemon file operations do not follow links planted in instance directories
Every daemon file operation inside an instance directory (config writes, hook reads, key copies, staging, snapshots, restore, delete, log tailing, update checks) SHALL refuse any symbolic link or junction other than the mod links the daemon created and recorded, which must still point at their recorded content-store target.

#### Scenario: Junction planted in a config folder
- **WHEN** the game-server account replaces `yagura/` in an instance with a junction to `C:\Windows\System32` and the instance is started
- **THEN** the start fails with `sandbox_violation` naming `yagura/`, and no file outside the instance is written

#### Scenario: Recorded mod link
- **WHEN** an instance's `@CF` junction points at its recorded content-store version
- **THEN** staging and reads through it proceed normally

#### Scenario: Delete never descends into a link
- **WHEN** an instance with a planted junction to another directory is deleted with files
- **THEN** the junction itself is removed and nothing under its target is deleted

### Requirement: Only verified game server processes are terminated
The daemon SHALL terminate a process only if it is the relay it launched or that relay's child running as the game-server account (the current user in console mode), regardless of what the instance's run files claim.

#### Scenario: Forged run file
- **WHEN** an instance's `relay.json` is rewritten to name the PID of a system process and a client stops the instance
- **THEN** the daemon refuses to terminate that process, stops the genuine server through the verified relay, reports notice `run_record_rejected`, and the system process keeps running

#### Scenario: Genuine server
- **WHEN** the recorded server is the relay's child running as `yagura-srv`
- **THEN** stop and kill act on it normally

## MODIFIED Requirements

### Requirement: Graceful stop per plugin strategy
Stopping SHALL follow the plugin's stop strategy (`rcon` command, `signal` (Linux SIGTERM / Windows Ctrl+C to the server's console), or `kill`), wait up to the grace period, then kill the process if it is still alive, and report which step ended it.

#### Scenario: Valheim saves on a signal stop
- **WHEN** a client stops a running Valheim instance started by the installed service (server running as `yagura-srv`) whose strategy is `signal`
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

### Requirement: Instance creation validates settings against the plugin schema
The daemon SHALL create an instance only when the plugin exists, the settings validate (defaults filled in), the ports collide with no other instance's ports or the daemon's API port, and the directory is allowed (under a configured instance root, overlapping no other instance or daemon directory). Creates are serialised. A new instance starts `not_installed` with the game-server account's access set on its directory.

#### Scenario: Valid instance created
- **WHEN** a client creates an instance of plugin `valheim` with name `Friends` and settings that satisfy the schema
- **THEN** the response carries a new instance id, state `not_installed`, every unspecified setting set to its default, and the directory `instances/<id>/` exists

#### Scenario: Setting violates the schema
- **WHEN** a client creates an instance with `maxPlayers: 500` where the schema's maximum is 127
- **THEN** the call fails with `INVALID_ARGUMENT`, the error lists the field path `maxPlayers` and the constraint, and no instance row or directory is created

#### Scenario: Directory outside the instance roots
- **WHEN** a client creates an instance with directory `D:\`
- **THEN** the call fails with `INVALID_ARGUMENT` reason `directory_not_allowed`, and no ACL is changed

#### Scenario: Port equal to the daemon API port
- **WHEN** a client creates an instance with a port equal to the daemon's API port
- **THEN** the call fails with `FAILED_PRECONDITION` reason `port_conflict` naming the daemon API

#### Scenario: Port collision with another instance
- **WHEN** a client creates an instance whose game port 2456/udp is already assigned to another instance
- **THEN** the call fails with `FAILED_PRECONDITION` naming the conflicting instance and port, and no instance is created

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

### Requirement: Save data is declared and snapshotted
Instances SHALL keep save data in the plugin's `data_paths`, inside the instance directory. The daemon SHALL snapshot them before every update (unless the request skips it, which is audited) and before a delete with files, keep the last 3 per instance and pre-delete snapshots of deleted instances for 30 days, and refuse the operation when the snapshots volume lacks the space.

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
- **THEN** no snapshot is taken, the operation result shows `snapshot: skipped`, and the audit log records the request

#### Scenario: Pre-delete snapshot of a deleted instance
- **WHEN** an instance was deleted with files 2 days ago
- **THEN** its `pre_delete` snapshot is listed by `ListOrphanSnapshots` with the instance name, and it is removed 30 days after the delete

### Requirement: Deleting an instance protects game data
Deleting an instance SHALL require it to be `stopped`, `not_installed` or `error` with no running operation and SHALL remove its database rows, firewall rules and content-store references; its directory is removed only when the request sets `delete_files: true` and repeats the instance name as confirmation.

#### Scenario: Delete with files snapshots first
- **WHEN** a client deletes a stopped instance with `delete_files: true` and the correct confirmation
- **THEN** a `pre_delete` snapshot of its data paths is written to the snapshots directory, then the instance directory is removed

#### Scenario: Delete an instance whose plugin is missing
- **WHEN** an instance in `error` with `plugin_missing` is deleted without `delete_files`
- **THEN** it disappears from listings and its directory is left on disk

#### Scenario: Delete keeping files
- **WHEN** a client deletes a stopped instance without `delete_files`
- **THEN** the instance disappears from listings, its firewall rules are removed, and its directory with world saves is left on disk

#### Scenario: Delete with wrong confirmation
- **WHEN** a client deletes with `delete_files: true` and a confirmation that does not match the instance name
- **THEN** the call fails with `INVALID_ARGUMENT` and nothing is deleted
