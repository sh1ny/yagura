# Spec Delta

## MODIFIED Requirements

### Requirement: One operation per instance at a time
The daemon SHALL run at most one lifecycle operation per instance at a time and SHALL queue further requests in arrival order, reporting their queue position. At most 4 heavy steps (the SteamCMD runs of install, update and validate, and the mod downloads of start, apply_mods and update_mods) run at once across the host; further ones wait with step `waiting_for_steamcmd` and their position.

#### Scenario: Concurrent requests on one instance
- **WHEN** a client requests `Update` on an instance while its `Install` operation is running
- **THEN** the update returns an operation id with status `queued` and position 1, and it starts only after the install operation ends

#### Scenario: Heavy limit counts mod downloads
- **WHEN** 4 instances are downloading mods in `ApplyMods` operations and a fifth instance's `Install` reaches its download
- **THEN** the install reports step `waiting_for_steamcmd` with its position until one of the four mod downloads ends, then downloads

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
An update or validate of a running instance SHALL stop it with its stop strategy, snapshot its data paths, update the app and any mods with updates, re-apply bindings, run the plugin's `onPostUpdate` hook and apply its file edits (step `apply_config`), and start it again; an update of a stopped instance leaves it stopped.

#### Scenario: Update while running
- **WHEN** a client updates a running instance
- **THEN** the operation steps are `stop`, `snapshot`, `download`, `update_mods`, `apply_config`, `start`, and the instance ends `running`

#### Scenario: Update fails after stop
- **WHEN** the download step fails for a running instance
- **THEN** the instance is `error` with the failure reason, it is not started again, and the snapshot is kept

#### Scenario: Mod update fails after stop
- **WHEN** the `update_mods` step fails for a running instance because one item is `unavailable`
- **THEN** the instance is `error` with `workshop_item_unavailable` naming the item, it is not started again, and the other mods' links are unchanged

### Requirement: Durable state with a portable instance file
The daemon SHALL persist instances, settings, mods and operations in its database before acknowledging a change, and SHALL write `instance.json` (plugin id and version, settings, mods, ports, `format_version: 1`, secret settings as placeholders and never their values) into the instance directory after every committed change.

#### Scenario: Change persisted and mirrored
- **WHEN** a client changes `hostname` on an instance and the call returns success
- **THEN** a daemon restart still shows the new hostname, and `instance.json` contains it

#### Scenario: Mod list mirrored
- **WHEN** a client sets the mods of an instance and the call returns success
- **THEN** a daemon restart shows the same ordered mods with their roles, and `instance.json` lists them with source, item id, role and staged name

#### Scenario: instance.json write fails
- **WHEN** the database commit succeeds but writing `instance.json` fails (for example the disk is full)
- **THEN** the call succeeds, a `instance_file_stale` warning event is emitted, and the file is rewritten at the next change or daemon start

#### Scenario: Secrets excluded from instance.json
- **WHEN** an instance has a value set for its `secret` setting `rconPassword`
- **THEN** `instance.json` contains `"rconPassword": {"secret": true}` and the value appears nowhere in the file
