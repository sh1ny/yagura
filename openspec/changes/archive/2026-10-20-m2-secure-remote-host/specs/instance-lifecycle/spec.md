# Spec Delta

## ADDED Requirements

### Requirement: Concurrent edits are detected by revision
Each instance SHALL carry a revision that increments only on configuration changes (settings, ports, secrets, restart policy, autostart, snapshot restore). Configuration calls (settings, secrets, snapshot restore, delete) SHALL include the revision the caller last read. A stale revision fails with `FAILED_PRECONDITION` reason `revision_conflict` and changes nothing.

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

#### Scenario: Restore from a stale view
- **WHEN** a client restores a snapshot with expected revision 7 after another client's save made the revision 8
- **THEN** the call fails with `revision_conflict`, no operation is created, and the data paths are unchanged

#### Scenario: Revision missing
- **WHEN** a configuration call omits the expected revision
- **THEN** the call fails with `INVALID_ARGUMENT` reason `revision_required` and changes nothing

### Requirement: Daemon file operations do not follow links planted in instance directories
Every daemon file operation inside an instance directory (config writes, hook reads, snapshots, restore, delete, log tailing) SHALL refuse any symbolic link or junction it meets, including the instance directory itself, failing with `sandbox_violation` naming the path.

#### Scenario: Junction planted in a config folder
- **WHEN** the game-server account replaces `yagura/` in an instance with a junction to `C:\Windows\System32` and the instance is started
- **THEN** the start fails with `sandbox_violation` naming `yagura/`, and no file outside the instance is written

#### Scenario: Instance directory replaced by a junction
- **WHEN** an instance directory has been replaced by a junction to another folder (for example on a root created before M2)
- **THEN** the next daemon file operation on that instance fails with `sandbox_violation` naming the instance directory, and nothing under the junction's target changes

#### Scenario: Plain instance files
- **WHEN** an instance directory contains only ordinary files and directories and the instance is started, snapshotted and stopped
- **THEN** every step completes without `sandbox_violation`

#### Scenario: Delete never descends into a link
- **WHEN** an instance with a planted junction to another directory is deleted with files
- **THEN** the junction itself is removed and nothing under its target is deleted

### Requirement: Only verified game server processes are terminated
The daemon SHALL terminate a process only if it is the relay it launched or that relay's child running as the game-server account (the current user in dev mode), whatever the instance's run files claim.

#### Scenario: Forged run file
- **WHEN** an instance's `relay.json` is rewritten to name the PID of a system process and a client stops the instance
- **THEN** the daemon refuses to terminate that process, stops the genuine server found as the verified relay's child, reports notice `run_record_rejected`, and the system process keeps running

#### Scenario: Forged run file and no verified server
- **WHEN** `relay.json` names a foreign PID and the verified relay has no child running as the game-server account
- **THEN** the daemon terminates nothing, the stop fails with `run_record_rejected` naming the relay PID, and the instance is `error`

#### Scenario: Genuine server
- **WHEN** the recorded server is the relay's child running as `yagura-srv`
- **THEN** stop and kill act on it normally

## MODIFIED Requirements

### Requirement: Graceful stop per plugin strategy
Stopping SHALL follow the plugin's stop strategy (`signal` (Linux SIGTERM / Windows Ctrl+C to the server's console), or `kill`), wait up to the grace period, then kill the process if it is still alive, and report which step ended it. This holds for servers started from the console and for servers the service started as the game-server account.

#### Scenario: Valheim saves on a signal stop
- **WHEN** a client stops a running Valheim instance started by `yagurad run --console` whose strategy is `signal`
- **THEN** the server receives Ctrl+C, its world save file is written before the process exits, and the result reports `stopped_by: graceful`

#### Scenario: Valheim saves on a signal stop from the service
- **WHEN** a client stops a running Valheim instance started by the installed service (server running as `yagura-srv`) whose strategy is `signal`
- **THEN** the server receives Ctrl+C, its world save file is written before the process exits, and the result reports `stopped_by: graceful`

#### Scenario: Grace period exceeded
- **WHEN** the process is still alive when the grace period ends
- **THEN** the daemon kills the process, the instance becomes `stopped`, and the operation result reports `stopped_by: kill`

### Requirement: Instance creation validates settings against the plugin schema
The daemon SHALL create an instance only when the plugin exists, the settings validate (defaults filled in), the ports collide with no other instance's ports or the daemon's API port, and the directory is allowed (under a configured instance root, overlapping no other instance or daemon directory). Creates are serialised. A new instance starts `not_installed`, with the game-server and SteamCMD accounts' access set on its directory in service mode.

#### Scenario: Valid instance created
- **WHEN** a client creates an instance of plugin `valheim` with name `Friends` and settings that satisfy the schema
- **THEN** the response carries a new instance id, state `not_installed`, every unspecified setting set to its default, and the directory `instances/<id>/` exists

#### Scenario: Game-server account access set
- **WHEN** an instance is created in service mode
- **THEN** `yagura-srv` and `yagura-steam` can list, create and modify files in the instance directory but cannot delete or rename the directory itself, and neither has access to the data directory

#### Scenario: Setting violates the schema
- **WHEN** a client creates an instance with `maxPlayers: 500` where the schema's maximum is 127
- **THEN** the call fails with `INVALID_ARGUMENT`, the error lists the field path `maxPlayers` and the constraint, and no instance row or directory is created

#### Scenario: Directory outside the instance roots
- **WHEN** a client creates an instance with directory `D:\`
- **THEN** the call fails with `INVALID_ARGUMENT` reason `directory_not_allowed`, no directory is created, and no ACL is changed

#### Scenario: Port equal to the daemon API port
- **WHEN** a client creates an instance with a port equal to the daemon's API port
- **THEN** the call fails with `FAILED_PRECONDITION` reason `port_conflict` naming the daemon API

#### Scenario: Port collision with another instance
- **WHEN** a client creates an instance whose game port 2456/udp is already assigned to another instance
- **THEN** the call fails with `FAILED_PRECONDITION` naming the conflicting instance and port, and no instance is created

### Requirement: Save data is declared and snapshotted
Instances SHALL keep save data in the plugin's `data_paths`, inside the instance directory. The daemon SHALL snapshot them before every update (unless the request skips it, which the operation result records and the audit log records) and before a delete with files, keep the last 3 per instance and pre-delete snapshots of deleted instances for 30 days, and refuse the operation when the snapshots volume lacks the space.

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

#### Scenario: Daemon killed during a restore
- **WHEN** the daemon is killed while a restore is replacing an instance's data paths
- **THEN** after restart the instance is in `error` with reason `restore_interrupted`, a Start is refused with `invalid_state`, and the `pre_restore` snapshot is listed

#### Scenario: Snapshot skipped on request
- **WHEN** an update is requested with `skip_snapshot`
- **THEN** no snapshot is taken, the operation result shows `snapshot: skipped`, and the audit log records the request with the requesting device

#### Scenario: Pre-delete snapshot of a deleted instance
- **WHEN** an instance was deleted with files 2 days ago
- **THEN** its `pre_delete` snapshot is listed by `ListOrphanSnapshots` with the instance name, and it is removed 30 days after the delete

### Requirement: Deleting an instance protects game data
Deleting an instance SHALL require it to be `stopped`, `not_installed` or `error`, SHALL run as an operation on the instance's queue, refused with `invalid_state` while another operation is queued or running, and SHALL remove its database rows and its owned firewall rules; its directory is removed only when the request sets `delete_files: true` and repeats the instance name as confirmation. Its operation records SHALL outlive it until normal history pruning.

#### Scenario: Delete with files snapshots first
- **WHEN** a client deletes a stopped instance with `delete_files: true` and the correct confirmation
- **THEN** the delete operation succeeds, its result names the `pre_delete` snapshot of the data paths, written to the snapshots directory before the instance directory was removed, and `WatchOperation` on the delete still returns that result after the instance is gone

#### Scenario: Delete an instance whose plugin is missing
- **WHEN** an instance in `error` with `plugin_missing` is deleted without `delete_files`
- **THEN** the delete operation succeeds, the instance disappears from listings, and its directory is left on disk

#### Scenario: Delete keeping files
- **WHEN** a client deletes a stopped instance without `delete_files`
- **THEN** the delete operation succeeds, the instance disappears from listings, its owned firewall rules are removed, and its directory with world saves is left on disk

#### Scenario: Delete with wrong confirmation
- **WHEN** a client deletes with `delete_files: true` and a confirmation that does not match the instance name
- **THEN** the call fails with `INVALID_ARGUMENT`, no operation is created, and nothing is deleted

### Requirement: Durable state with a portable instance file
The daemon SHALL persist instances, settings and operations in its database before acknowledging a change, and SHALL write `instance.json` (plugin id and version, settings, ports, `format_version: 1`, secret settings as placeholders and never their values) into the instance directory after every committed change.

#### Scenario: Change persisted and mirrored
- **WHEN** a client changes `hostname` on an instance and the call returns success
- **THEN** a daemon restart still shows the new hostname, and `instance.json` contains it

#### Scenario: instance.json write fails
- **WHEN** the database commit succeeds but writing `instance.json` fails (for example the disk is full)
- **THEN** the call succeeds, a `instance_file_stale` warning event is emitted, and the file is rewritten at the next change or daemon start

#### Scenario: Secrets excluded from instance.json
- **WHEN** an instance has a value set for its `secret` setting `rconPassword`
- **THEN** `instance.json` contains `"rconPassword": {"secret": true}` and the value appears nowhere in the file

### Requirement: Error reasons have defined exits
An instance in `error` SHALL carry a reason that allows only these exits: `crash_loop` leaves by Start or Acknowledge; `update_interrupted` and update failures by Update, Validate or Acknowledge; `restore_interrupted` by a restore or Acknowledge; `settings_invalid` by saving valid settings; `plugin_missing` by a reload that restores the plugin; `run_record_rejected` by Stop or Acknowledge. Stop (when no operation runs) and Delete (when none is queued or running) are allowed from any reason; other requests fail with `invalid_state`.

#### Scenario: Acknowledge a crash loop
- **WHEN** a client acknowledges an instance in `error` with `crash_loop`
- **THEN** the instance becomes `stopped` and its restart counter is reset

#### Scenario: Start refused with invalid settings
- **WHEN** a client starts an instance in `error` with `settings_invalid`
- **THEN** the call fails with `FAILED_PRECONDITION` reason `invalid_state` naming `settings_invalid`, and the state is unchanged

#### Scenario: Update clears an interrupted update
- **WHEN** a client updates an instance in `error` with `update_interrupted` and the update succeeds
- **THEN** the instance ends `stopped` and the error reason is cleared

#### Scenario: Acknowledge a rejected run record
- **WHEN** a client acknowledges an instance in `error` with `run_record_rejected`
- **THEN** the instance becomes `stopped`, its run record is cleared, and a warning naming the relay PID is kept on the instance

#### Scenario: Start refused after a rejected run record
- **WHEN** a client starts an instance in `error` with `run_record_rejected`
- **THEN** the call fails with `FAILED_PRECONDITION` reason `invalid_state` naming `run_record_rejected`
