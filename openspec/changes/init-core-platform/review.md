# Review

## Metadata

- **Round:** 4
- **Prior round:** Round 3 had two reviews. The subagent review returned APPROVE_WITH_CHANGES (R3-M1..M5, R3-S1..S9). The OMP review (`review-round3-omp.md`) returned REVISE (C1, C2, M1..M10, S1..S4). The user treated round 3 as REVISE, and the author's Rebuttals table (commit 60261d2) marks every finding fixed. This round re-checks each listed fix against the artifacts at HEAD 66914e4 and then reviews the change afresh.
- **Reviewer:** fresh-context subagent (Claude Code, `specwright-reviewer` role). The request named no specific `SKILL.md` paths, only "Dart/Flutter ones" under `.claude/skills/`. I loaded and applied `dart-setup-ffi-assets`, `dart-use-ffigen`, `dart-build-cli-app` and `flutter-apply-architecture-best-practices` from `F:\Dev\Dart\yagura\.claude\skills\`. None failed to load.
- **Reviewed:**
  - The change: `openspec/changes/init-core-platform/proposal.md`, `design.md`, `tasks.md`, and all 9 `specs/*/spec.md`.
  - Prior round: `git show 60261d2:openspec/changes/init-core-platform/review.md` (including its Rebuttals) and `openspec/changes/init-core-platform/review-round3-omp.md`.
  - Context:
    - `openspec/roadmap.md` (M1 section and exit criteria).
    - `openspec/architecture.md` (state machine, state ownership, failure and recovery, resource bounds).
    - `docs/protocol.md`.
    - `proto/yagura/v1/{system,plugins,instances,operations,logs,common}.proto`, plus the service lists of the others.
    - ADRs 0008 and 0013, by grep for delete, restore and revision.
  - Backlog, for the split only (not reviewed): the requirement lists of `openspec/changes/platform-backlog/specs/*/spec.md`, and the text of its MODIFIED/REMOVED "Stop and health declarations", "Secret settings stay unset without a secret store", "Deleting an instance protects game data" and "Development mode is localhost only".
  - Checks:
    - `openspec validate init-core-platform --strict` passes.
    - By script, all 148 scenarios in the 9 specs have a test-map row with a matching requirement and scenario name.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Re-check of the round-3 fixes

Each fix listed in the Rebuttals table is present in the artifacts:

- **Secrets (R3-M2 / OMP C2).**
  - New requirement "Secret settings stay unset without a secret store".
  - D24 and `docs/protocol.md` M1 row (`SetSecret`/`DeleteSecret` fail `secret_store_unavailable`).
  - Task 4.3.
  - Valheim runs with `-public 0` and no password (9.1, spike 1.3, Risks).
  - Backlog REMOVED, with a migration note.
- **Hook file edits (OMP C1).** D23, task 2.3 and the "Edit in an unsupported format" scenario.
- **M3 vocabulary removed from hooks and manifest (R3-M3, R3-M4 / OMP M1).**
  - `onPreStart` is used in "Thrown error".
  - "Edit through a link refused" is added.
  - `unsupported_in_this_version` covers `rcon` stop, `query` health and the `bindings`/`mods`/`rcon` sections.
  - `steam_account_required` is defined.
- **Valheim log source and health evaluator (R3-M1 / OMP M2).** Task 9.1 declares source `server`; the evaluator is built in 5.3 and 7.3.
- **Protocol boundary (R3-S7 / OMP M3).**
  - D24 table.
  - `not_implemented`.
  - `revision` 0.
  - `GetHealth.not_built` (proto field 10).
  - The 8.3 checks.
- **Desktop connection and actions (R3-S2 / OMP M5).** Requirements "Connection to one daemon" and "Instance actions"; task 9.3.
- **Signal helper and breakaway (R3-S3 / OMP M6).** D2 "Signal helper and jobs"; spike 1.3 runs from a console parent and on CI.
- **SteamCMD sweep (R3-S6 / OMP M7).** Scenario "Stray SteamCMD cannot be terminated".
- **Hook worker slots (OMP M8).** Scenario "Timed-out worker keeps its slot".
- **Log bounds (OMP M9).** 64 KiB line cut, 4 MiB follow lag, 10,000-line pause buffer.
- **Launch commit boundary (OMP M10).** D2 "Launch records" with `pending` run rows.
- **Other items.**
  - AOT bundle smoke (9.4).
  - Dev-mode defaults.
  - M1 scope lines on D6, D12 and D21.
  - D22.
  - State & Ownership rows for the restart counter and the last requested state.
  - "Cancelled update not autostarted".
  - The 6 s hook bound.
  - The MSVC fallback rule.
  - The `valheim` tag.

One fix is incomplete. R3-M5 / OMP M4 moved the runtime manifest rows and the negotiation rows to the right boundary, but the same class of problem remains in other groups (R4-M1 below).

### Critical (blocking)

None.

### Moderate

**R4-M1. Test-map rows are still assigned to a package or group that cannot observe their THEN, so several group "green" gates cannot be met as ordered.**
- *Location:* the `tasks.md` test map and the Verify lines of tasks 2.2, 2.4, 3.3 and 4.3.
- *Problem:* Each group's Verify says "this group's rows are green; flip them". Several rows depend on components that a later group builds, or sit in a package that has no such component:
  - **Rows in the `packages/yagura_js` package.** This package has only the FFI runtime (task 2.2).
    - "Infinite loop interrupted" asserts that "the start operation fails ... and the daemon keeps answering other calls". This is also the M1 exit criterion "while the daemon keeps answering `System.GetInfo`", but there is no start operation or daemon in that package.
    - "Manifest deadline above the cap" is manifest validation at load (`yagura_plugin`, group 3).
    - "Oversized result" and "Allocation beyond the cap" assert that "the operation fails". The result-size cap is in the daemon's hook runner (2.4).
  - **Group 2 hook rows whose THEN is an operation outcome.** Group 2 comes before the operation runner (group 4), Start (group 5) and Install (group 6):
    - `pre_start_hook_adds_arguments` ("the server is launched with ...").
    - `invalid_result_shape` ("the server is not started").
    - `thrown_error` ("operation ends `failed` ... recorded in the operation history").
    - `context_contents` (the context of an instance's `onPreStart`).
    - `edit_in_an_unsupported_format` and `edit_through_a_link_refused` ("the operation fails").
    - `hook_not_exported` ("install completes").
    - `degraded_hook_runtime` ("`GetHealth` reports 2 leaked hook workers"; `GetHealth` is served in group 8).
    - `syntax_error_at_load` (plugin `rejected` at load; the daemon plugin registry is task 4.3).
  - **Group 4 rows that need group 5 or 6.**
    - `process_exits_during_the_health_window`, `health_check_never_passes` and `stop_during_the_health_wait` need the start-time health evaluator, which task 5.3 builds.
    - `delete_with_files_snapshots_first` and `update_cancelled_after_the_server_was_stopped` need snapshots and the update operation (task 6.3).
    - `daemon_killed_during_an_update` asserts that no SteamCMD from before the restart survives, which is the stray sweep in task 6.2.
  - **Group 3 rows in `packages/yagura_plugin`.**
    - `missing_executable_for_this_os` asserts that "creating an instance of it fails with `FAILED_PRECONDITION` reason `unsupported_platform`".
    - `derived_port_collides` asserts that "the settings change fails ... naming both instances".
    - Both are instance-manager behaviour (task 4.3).
- *Consequence:* The author has two options, and neither is good:
  - Write these tests against a hand-built harness that does less than the THEN. The row goes green without proving it. For "Infinite loop interrupted" this hollows out an agent-verified exit criterion.
  - Leave the group unfinished until later groups exist, which breaks the group order the tasks depend on.
- *Fix:* Required Change 1.

**R4-M2. Deleting with files is long, non-atomic work done inside a unary call, with no defined order of steps for a crash.**
- *Location:*
  - `specs/instance-lifecycle/spec.md` "Deleting an instance protects game data".
  - `proto/yagura/v1/instances.proto` (`rpc DeleteInstance(...) returns (Empty)`).
  - `docs/protocol.md` ("Long work never blocks a unary call"; "Client deadlines: unary 30 s").
  - Design Failure & Visibility, which has no delete row.
  - Task 4.3.
- *Problem:* `delete_files: true` runs these steps in one unary call:
  1. Copies `data_paths` into a `pre_delete` snapshot.
  2. Removes the database rows.
  3. Recursively removes the instance directory (a Valheim install is about 1-2 GB in thousands of files).

  That breaks the protocol rule above and can exceed the client's 30 s unary deadline. Nothing defines:
  - what the daemon does when the client cancels the call;
  - the order of the steps if the daemon dies mid-delete;
  - what happens to operations queued for the instance. The spec refuses delete only while an operation *runs*, so a queued Start then reaches the head of the queue for a deleted instance.

  Concrete outcomes:
  - Rows are removed first and the directory removal is cut: a half-deleted, unowned directory is left under `instances/`, and nothing reports or finishes it.
  - The directory goes first and the rows remain: a `stopped` instance points at a half-deleted directory, and its next Start launches a broken install.
- *Why now:* The return type is part of the wire contract D24 promises not to change. While no daemon implements v1 the change is free; after M1 it is a breaking change.
- *Fix:* Required Change 2.

**R4-M3. `log_match` on a `fixed` file source can miss the current run's line when the previous run's file was about the same size.**
- *Location:*
  - `specs/plugin-manifest/spec.md` scenario "Log-match health check" ("whose file still holds that line from the previous run").
  - Design D6 ("truncation detection").
  - Tasks 7.2 and 7.3 ("matching only lines written after the current start").
  - Task 9.1: Valheim uses `-logFile logs/server.log` with rotation `fixed`.
- *Problem:* The only mechanism for telling a new run's file apart from the previous run's is truncation detection. With polling, that can only mean "the size went below the stored offset". A Unity server rewrites its `-logFile` from the start on each launch, so file identity and, through Windows file-name tunnelling, creation time are not reliable signals either.
  - Suppose the previous run was short: started, then stopped or crashed soon after "Game server connected". The new run's file grows back past the old offset at about the moment it writes that line again.
  - If a poll first sees a size at or above the stored offset, the tailer reads only from the old offset onward. It misses the new "Game server connected" line.
  - After `start_timeout` (300 s) the instance is `running` with `health: unknown`.
- *Consequence:* This is the Valheim readiness path of the user-verified exit criterion, and a start/stop/start sequence (or a crash restart) reaches it. The scenario's own premise, an old file holding the line, is the setup that triggers it. Nothing in the design says how the evaluator avoids it.
- *Fix:* Required Change 3.

### Suggestions

**R4-S1. An interrupted restore leaves a half-replaced world behind a `stopped` instance.**
- *Location:* the "Restore a snapshot" scenario, D12, task 6.3, and Failure & Visibility (whose only snapshot row is "copy fails mid-way").
- *Problem:* If the daemon dies while replacing `data_paths`, D9 marks the operation `interrupted`, but the instance stays `stopped`. Its next Start (or autostart) runs on mixed old and new save files. The `pre_restore` snapshot makes this recoverable, but nothing tells the admin to use it.
- *Fix:* Restore into a staging directory next to each data path and swap with renames. Alternatively, mark the instance `error` with a `restore_interrupted` reason whose exits are a new restore or Acknowledge.

**R4-S2. The second daemon may not be able to read the holder's PID on Windows.**
- *Location:* host-service "Second instance refused" ("exits ... with `data_dir_locked` and the PID of the holder"); D9 (`LockFileEx` on `yagurad.lock`, "the PID inside is informational").
- *Problem:* `LockFileEx` locks are mandatory on Windows, so other processes cannot read the locked byte range. Dart's `RandomAccessFile.lock()` with the default range locks the whole file. The second daemon's read of the PID then fails, and the scenario cannot pass as written.
- *Fix:* Lock a byte range past the PID bytes (for example, one byte at a large offset), or write the PID to a separate file.

**R4-S3. A stop cut short by a daemon crash can be undone by the restart policy.**
- *Location:* D9 (`stopping` → re-attach); the crash detection requirement ("exits without a stop request").
- *Problem:* Suppose the daemon dies after sending Ctrl+C but while Valheim is still saving. After restart the server is re-attached as `running` with no stop request on record. When it then exits, that counts as a crash, and `on_crash` starts it again.
- *Fix:* Persist "stop requested" on the run record. A re-attached run that carries it resumes `stopping`: it waits out the rest of the grace period, then kills.

**R4-S4. Coalesced progress leaves sequence gaps, and nothing says how a resume treats them.**
- *Location:* D3 ("`Progress` events are coalesced per step"); daemon-protocol "Reconnect without losing events" ("receives events from 18 onward").
- *Problem:* Coalescing drops intermediate Progress sequence numbers inside the retained window. A test or client that checks for consecutive sequences will see a gap, and nothing says whether the gap is an `events_dropped` case.
- *Fix:* State that gaps from coalesced Progress are never reported as `events_dropped`, and that a resume gets every retained non-progress event plus the latest Progress per step.

**R4-S5. The disk check for a first install has no input.**
- *Location:* steam-content "Not enough disk space" ("twice the app's last known size").
- *Problem:* On a fresh host, such as the M1 Valheim install, there is no last known size, so the check is undefined.
- *Fix:* Define what happens: for example, use an optional manifest `steam.size_hint_bytes`, or skip the check with a warning when no size is known.

**R4-S6. A settings document echoed back with secret placeholders could be refused.**
- *Location:* plugin-manifest "Secret settings stay unset without a secret store"; `UpdateSettingsRequest.settings`; desktop task 9.3 (form "all v1 field types").
- *Problem:* Reading the settings returns `{"secret": true, "set": false}` for a secret field. If the form sends that object back and it counts as "a value for a `secret` setting", then every save for a plugin with a secret field fails `secret_store_unavailable`.
- *Fix:* State that a placeholder object, or an omitted secret key, is accepted and leaves the field unset. Only a non-placeholder value is refused.

**R4-S7. Calls to unserved services get no `ErrorDetail`.**
- *Location:* D24 ("services M1 does not serve are unknown to the server"); daemon-protocol "Structured errors" ("Every failed call SHALL return ... an error detail").
- *Problem:* `package:grpc` answers an unknown service with `UNIMPLEMENTED` before any interceptor sees the method, so it attaches no `ErrorDetail`. A call to `Mods.ListMods` breaks the requirement as written.
- *Fix:* Scope the requirement to served services, or serve stub services that answer `not_implemented`.

**R4-S8. Small inconsistencies the write-back (task 9.6) should catch.**
- `Snapshot.reason` in `instances.proto` lists `pre_update | pre_delete | manual`. It lacks `pre_restore`, which the spec requires, and M1 has no method that creates a `manual` snapshot.
- The architecture state diagram allows `DeleteInstance` only from `stopped`. The spec also allows it from `not_installed` and `error`.
- "PID reused by another process" expects the instance `stopped`. With `autostart` on by default, "Host rebooted" then starts it. The scenario should say autostart is off, or expect the autostart.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **R4-M1: test map groups and boundaries.** In `tasks.md`, make these test-map edits; leave every other row unchanged.
   - **Rows moved out of `packages/yagura_js`:**
     - "Infinite loop interrupted" → `apps/yagurad/test/hooks/hook_deadline_test.dart`, group 8.
     - "Manifest deadline above the cap" → `packages/yagura_plugin/test/hook_declarations_test.dart`, group 3.
     - "Allocation beyond the cap" and "Oversized result" → `apps/yagurad/test/hooks/hook_memory_cap_test.dart`, group 5.
     - In task 3.2, add `hooks.timeout_seconds` (max 60) to the schema.
   - **Group 2 rows moved to later groups:**
     - Group 5: `thrown_error`, `context_contents`, `invalid_result_shape`, `pre_start_hook_adds_arguments`, `edit_in_an_unsupported_format`, `edit_through_a_link_refused`.
     - Group 6: `hook_not_exported`.
     - Group 8: `degraded_hook_runtime`.
     - Group 4: `syntax_error_at_load`.
   - **Group 4 rows moved to later groups:**
     - Group 5: `process_exits_during_the_health_window`, `health_check_never_passes`, `stop_during_the_health_wait`.
     - Group 6: `delete_with_files_snapshots_first`, `update_cancelled_after_the_server_was_stopped`, `daemon_killed_during_an_update`.
   - **Group 3 rows moved to the daemon:**
     - `missing_executable_for_this_os` and `derived_port_collides` → `apps/yagurad/test/instances/...`, group 4.
   - **Task text:**
     - Task 2.4 keeps "every row of this group". Group 2's remaining rows (read limits, worker slots, listing, the file-edit writer, write and path-escape refusal) can be observed by the hook runner and writer alone.
     - Tasks 5.3, 6.3 and 8.2 already flip "this group's rows", so the moved rows are covered there.
2. **R4-M2: delete as an operation.**
   - Change `rpc DeleteInstance(DeleteInstanceRequest) returns (Operation)` in `proto/yagura/v1/instances.proto`, and add `DeleteInstance` to the "Unary returning an `Operation`" row in `docs/protocol.md`.
   - In `specs/instance-lifecycle/spec.md` "Deleting an instance protects game data", add: "Delete runs as an operation on the instance's queue and is refused with `invalid_state` while another operation is queued or running. With `delete_files`, the daemon takes the `pre_delete` snapshot, writes a `.yagura/deleting` marker into the instance directory, removes the database rows, then removes the directory. At startup, a directory under an instance root that has the marker and no instance row is removed again."
   - Add a scenario:
     - **WHEN** the daemon is killed while removing an instance directory after its rows were deleted
     - **THEN** after restart the instance is not listed, the remaining directory is removed, and its `pre_delete` snapshot is listed by `ListOrphanSnapshots`
   - Map the scenario in the test map (group 6).
   - Add a "Delete" row to design Failure & Visibility.
   - Update task 4.3 ("delete as an operation with the marker order") and the "Delete ..." scenarios so their THENs are read from the operation's result.
3. **R4-M3: current-run detection for `fixed` sources.**
   - In design D6 (or a sentence in task 7.3), add: "Before each Start, for every `fixed` file source the evaluator records the file's size and a hash of its first 4 KiB. A later poll that finds a smaller size or a different first-4-KiB hash treats the file as rewritten and reads it from offset 0. `log_match` considers only lines read after this point."
   - In `specs/plugin-manifest/spec.md`, add a scenario under "Stop and health declarations":
     - **WHEN** the previous run's log file is 40 KiB and still holds the match line, and the new run rewrites the file from the start past 40 KiB before the next poll
     - **THEN** the instance becomes `running` on the new run's line
   - Map it in the test map (`apps/yagurad/test/instances/log_match_health_check_test.dart`, group 7).

### Re-check (round 4, after commits 8880730 and ba3c924)

The reviewer re-checked `git diff 9773c10..ba3c924` against the artifacts. All three Required Changes are applied:

1. **R4-M1: applied.**
   - The test map moves every row listed in Required Change 1 to the stated file and group.
   - Group 2 keeps only rows the hook runner and writer can observe: read and listing limits, worker slots, the file-edit writer, and write and path-escape refusal.
   - Task 2.2 now verifies package unit tests only. Task 3.2 adds `hooks.timeout_seconds` (max 60). Task 5.3 calls `onPreStart` and `onPostStop` through the hook runner, and 6.3 calls `onPostInstall`.
   - Each group's Covers line lists the rows moved into it.
   - A script confirms 156 scenarios and 156 matching rows, and `openspec validate init-core-platform --strict` passes.
2. **R4-M2: applied.**
   - `DeleteInstance` returns `Operation`, in both the proto and the `docs/protocol.md` call table.
   - The requirement refuses delete with `invalid_state` while another operation is queued or running.
   - New requirement "Deleting files survives a daemon crash" defines the marker order, with scenario "Daemon killed while removing files" (group 6).
   - The delete THENs are read from the operation's result, and a wrong confirmation creates no operation.
   - D25 adds the cancellation cut-off and the case of a marked directory whose row survived.
   - D9 recovery, State & Ownership, Failure & Visibility and tasks 4.3 and 6.3 are updated.
3. **R4-M3: applied.**
   - D6 "Current run" records the size and first-4-KiB hash before each Start.
   - Scenario "Log file rewritten past its old size" is mapped to group 7, and task 7.2 builds the mark.
   - There is a State & Ownership row for it.
   - The same scenario is carried into the backlog's MODIFIED "Stop and health declarations".

All eight Suggestions are also applied. Two use a different fix from the one proposed, and both hold:

- **R4-S1 (error-reason option).**
  - An interrupted restore leads to `error: restore_interrupted`, consistently across the spec, D9, D12, D17 (exits: restore or Acknowledge), Failure & Visibility, `docs/protocol.md` and the new scenario "Daemon killed during a restore" (group 6).
  - Start is refused, and D14 never autostarts an instance in `error`, so the admin finds out and a half-replaced world is never started.
  - The `pre_restore` snapshot is taken before any data path is replaced, so the data stays recoverable.
- **R4-S7 (stub services).**
  - Registering `Pairing`, `Steam`, `Mods`, `Rcon` and `Firewall` as stubs lets every call pass through the interceptor and carry an `ErrorDetail`.
  - The requirement text, D24 (with its reason), the `docs/protocol.md` M1 row, task 8.2 and scenario "Service not built yet" (group 8) agree.
  - It keeps D24's rejected alternative intact, because the proto stays whole. The generated stubs already come from task 1.4.

The other six Suggestions are applied as proposed:

- **R4-S2:** the PID is written at offset 0 and one byte at 2^32 is locked (spec, D9, task 4.2).
- **R4-S3:** `stop_requested_at` is written before the stop strategy is sent, and re-attach resumes `stopping` (new requirement and scenario, D2, D9, task 5.3).
- **R4-S4:** coalescing gaps are not drops (D3, scenario, also carried into the backlog).
- **R4-S5:** `steam.size_hint_bytes` and `disk_check_skipped` are added, with a scenario and tasks 3.2, 6.2 and 9.1.
- **R4-S6:** secret placeholders are accepted (spec, scenario, task 4.3).
- **R4-S8:** `Snapshot.reason` gains `pre_restore`, "PID reused" sets `autostart` off, and task 9.6 writes these back.

The edits introduced two small gaps. Neither blocks the Required Changes; the author can fix them with a wording edit:

- **R4-S9. The delete operation's own row is not protected.**
  - *Problem:* D25 and the delete requirement say delete "removes the database rows" but do not say that the delete operation's own row, and the instance's operation history, are kept until normal pruning. If delete removes them with the instance:
    - `WatchOperation` on the delete would return `operation_expired`;
    - the THENs "the delete operation succeeds, and its result names the `pre_delete` snapshot" would have nothing to read.
  - *Fix:* State that operation rows outlive the instance and are pruned by the normal history bound.
- **R4-S10. Two texts still use the old "while an operation runs" wording.**
  - *Location:* D17's "any | Stop, Delete | refused only while an operation runs" row, and the "Error reasons have defined exits" text.
  - *Problem:* Both still say "while an operation runs", but the delete requirement now refuses delete while an operation is queued *or* running.
  - *Fix:* Align the wording for Delete.

CHANGES_APPLIED: yes

## Rebuttals


All three Required Changes and all eight Suggestions were applied as fixes; none is rebutted.

| Finding | Response |
|---|---|
| R4-M1 (test rows that cannot observe their outcome) | Fixed as listed in Required Change 1: the `yagura_js` rows moved to the daemon (groups 5, 8) and to `yagura_plugin` (group 3); group 2 keeps only the runner and writer rows; the health, cancellation, update and delete rows moved to groups 5 and 6; the two `yagura_plugin` rows moved to daemon tests in group 4. Task 2.2 now verifies package unit tests, 3.2 adds `hooks.timeout_seconds` (max 60), and each group's Covers line lists the moved requirements. 156 scenarios, 156 rows. |
| R4-M2 (delete blocks a unary call) | Fixed. `DeleteInstance` returns `Operation` (proto, `docs/protocol.md`); the requirement runs delete on the queue and refuses it with `invalid_state` while another operation is queued or running; new requirement "Deleting files survives a daemon crash" with the marker order and scenario "Daemon killed while removing files" (group 6); the delete THENs read the operation result; new D25 (cancellation only before the rows go; marked directory with a row left alone); D9 recovery, State & Ownership and Failure & Visibility rows; tasks 4.3 and 6.3. |
| R4-M3 (Valheim readiness missed on rewrite) | Fixed. D6 "Current run": size and first-4-KiB hash per `fixed` source before each Start; scenario "Log file rewritten past its old size" (group 7, also carried into the backlog MODIFIED block); State & Ownership row; task 7.2. |
| R4-S1 (interrupted restore) | Fixed. `pre_restore` is taken before any data path is replaced; a restore cut by a crash leaves `error: restore_interrupted` (exits: restore or Acknowledge) in the spec, D9, D12, D17 and Failure & Visibility; scenario "Daemon killed during a restore"; reason added to `docs/protocol.md`; task 6.3. |
| R4-S2 (PID unreadable under `LockFileEx`) | Fixed. The holder writes its PID at offset 0 and locks one byte at offset 2^32 (host-service requirement, D9, task 4.2). |
| R4-S3 (stop undone by restart policy) | Fixed. New requirement "A stop survives a daemon restart" with scenario "Daemon killed during a stop" (group 5); D2 "Stop records" (`stop_requested_at` before the strategy is sent), D9 recovery, State & Ownership and Failure & Visibility rows; tasks 5.2 and 5.3. |
| R4-S4 (coalesced progress gaps) | Fixed. D3 states coalescing gaps are not drops; scenario "Resume across coalesced progress" (group 8, carried into the backlog); task 8.2. |
| R4-S5 (disk check on first install) | Fixed. Twice the last known size, else twice the optional manifest `steam.size_hint_bytes`, else skipped with warning `disk_check_skipped`; scenario "First install without a known size"; tasks 3.2, 6.2 and 9.1 (Valheim hint from spike 1.3); warning listed in `docs/protocol.md`. |
| R4-S6 (secret placeholder echoed back) | Fixed. An omitted key or the read placeholder is accepted and leaves the field unset; scenario "Settings saved with the secret placeholder" (group 4); task 4.3. |
| R4-S7 (no `ErrorDetail` for unserved services) | Fixed by serving stubs: `Pairing`, `Steam`, `Mods`, `Rcon` and `Firewall` are registered and every method fails `not_implemented` with a detail (D24, requirement text, `docs/protocol.md`, task 8.2); scenario "Service not built yet" (group 8). |
| R4-S8 (small inconsistencies) | Fixed. `Snapshot.reason` lists `pre_update`, `pre_delete` and `pre_restore` (no `manual`); "PID reused by another process" now has `autostart` off; task 9.6 writes back delete from `stopped`, `not_installed` and `error`, delete as an operation, stop records and `restore_interrupted` into the architecture state diagram. |
