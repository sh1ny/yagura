# Review

## Metadata

- **Round:** 2
- **Prior round:** Round 1: REVISE, 5 Critical / 10 Moderate / 10 Suggestions; all marked fixed by the author
- **Reviewer:** fresh-context subagent (Claude Code)
- **Reviewed:**
  - Planning docs: openspec/strategy.md, openspec/architecture.md, docs/overview.md, docs/protocol.md.
  - Proto definitions: proto/yagura/v1/{common,firewall,instances,logs,mods,operations,pairing,plugins,rcon,steam,system}.proto.
  - ADRs: docs/adr/0001 to 0013, with 0011 renamed to 0011-secrets-are-dpapi-blobs.md and 0013 new.
  - Spot checks of the init-core-platform specs (instance-lifecycle, plugin-manifest, host-service, mod-management) and design.md, to verify the round-1 fixes that cite them.
  - Review rules: openspec/schemas/specwright/schema.yaml and templates/review.md.
  - External checks: Microsoft "Process Creation Flags" (`CREATE_NEW_PROCESS_GROUP` / `CREATE_NEW_CONSOLE` / `CREATE_BREAKAWAY_FROM_JOB` semantics), grpc-dart `server_keepalive.dart` (defaults).

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

The revision is substantial and resolves most of round 1. The process model is now buildable in principle. Pairing, the content store, recovery, revisions and secrets are specified. The protocol is concrete enough to implement. The new findings below come mostly from the revisions themselves: the new privilege boundary (ADR 0013) and the relay process model (ADR 0009).

### Critical (blocking)

**C1. The LocalSystem daemon trusts paths and files that the low-privilege `yagura-srv` account controls, so ADR 0013's isolation can be bypassed.** (docs/adr/0013, 0009, 0005, 0004, 0003; architecture.md "Failure and recovery", "Save snapshots"; docs/adr/0010)

ADR 0013 gives `yagura-srv` modify rights on the instance directory. The threat it addresses is a game server or mod being exploited. Several LocalSystem actors then operate inside that same directory:

- the config binder (atomic replace of bound files and hook-returned edits);
- the key copy into `keys/`;
- mod staging, including `copy_fallback`;
- snapshot and restore of `data_paths`;
- `DeleteInstance` with `delete_files`;
- SteamCMD `app_update` into the instance;
- hook host functions that read instance files.

A compromised server can replace `keys/`, `yagura/`, `{{profiles}}` or a file with a junction or symlink to `C:\Windows\System32` or to the daemon data directory. The next start, update, snapshot or delete then makes LocalSystem write, copy or delete through it. That is arbitrary file write or delete as SYSTEM, which is local privilege escalation and the outcome ADR 0013 exists to prevent.

Separately, `relay.json` and `exit.json` sit in `<instance>/.yagura/run/`, which `yagura-srv` can write. The supervisor takes relay and server PIDs from `relay.json` and kills them on stop or force-stop. Executable path and start time can be read for any process, so a forged record makes the daemon terminate an arbitrary process as SYSTEM, for example `lsass.exe`, which forces a reboot.

Fix:
- **Reparse-point rule (ADR 0013):** every daemon file operation under an instance directory must refuse to traverse reparse points. Open with `FILE_FLAG_OPEN_REPARSE_POINT` and check each path component. The only allowed exceptions are the junctions the mod pipeline itself created, which are recorded in instance-mod rows and re-verified to point at the expected content-store version. Recursive delete and snapshot copy never descend into a reparse point; they delete or skip the link itself.
- **SteamCMD into instances (ADR 0010):** SteamCMD installs app content into a daemon-owned staging location, or into an instance tree that `yagura-srv` cannot write while SteamCMD runs. Either way, the daemon refuses an instance tree that contains unexpected reparse points.
- **Run records (ADR 0009):** they come from the launcher, which runs as LocalSystem. The launcher returns the relay PID and creation time on its stdout to the daemon. The daemon accepts a server PID from `relay.json` only if that process's parent is the recorded relay and its token user is `yagura-srv`. Before any terminate, the daemon re-checks that the target's token user is `yagura-srv`.

### Moderate

**M1. Ctrl+C delivery as specified will not reach the server, and the spec contradicts the ADR.** (docs/adr/0009 steps 1-3; openspec/changes/init-core-platform/specs/instance-lifecycle/spec.md, stop requirement)
- **Spec contradiction.** The instance-lifecycle spec says `signal` sends "Windows CTRL_BREAK to the process group". ADR 0009 and the overview say Ctrl+C through the relay's console. Unity and Unreal servers handle these differently, and only Ctrl+C is the documented save-and-exit path for Valheim.
- **Flag combination.** `CREATE_NEW_PROCESS_GROUP` is documented as ignored when combined with `CREATE_NEW_CONSOLE`. Where it does apply, it disables Ctrl+C for the whole group. Listing it is at best inert and at worst the reason Ctrl+C never arrives.
- **Inherited ignore flag.** "The relay ignores console control events": if the relay does this with `SetConsoleCtrlHandler(NULL, TRUE)`, the ignore flag is inherited by the game server it spawns. Valheim then never sees Ctrl+C, and the M1 graceful-stop criterion fails.
- **Dead relay.** `yagurad signal --console-of <relay pid>` cannot attach if the relay is gone. The failure table explicitly keeps the server running after the relay dies.

Fix:
- Drop `CREATE_NEW_PROCESS_GROUP` from step 1.
- State that the relay installs a handler function that returns TRUE, never `SetConsoleCtrlHandler(NULL, TRUE)`, and that it spawns the server without `CREATE_NEW_PROCESS_GROUP`.
- `signal` attaches to the console of the server PID (falling back to the relay PID) and sends `CTRL_C_EVENT` to process group 0.
- Change the spec's `signal` definition to "Windows: Ctrl+C to the server's console".

**M2. `CreateProcessAsUserW` from a service, as described, will fail or run the game with the wrong profile.** (docs/adr/0013, docs/adr/0009 step 1)

- **Console start failure.** A console process (the relay, with `CREATE_NEW_CONSOLE`) started under a different user's token inherits the service's window station and desktop (`Service-0x0-3e7$\Default`). `yagura-srv` has no access to them, so console initialisation typically fails with `STATUS_DLL_INIT_FAILED` (0xC0000142).
- **Wrong profile.** `LogonUserW` does not load the user profile. Without `LoadUserProfileW` and `CreateEnvironmentBlock`, `HKCU`, `%APPDATA%` and `%USERPROFILE%` point at the default/SYSTEM context. That breaks Unity PlayerPrefs and any game state that falls back to the profile.

Fix: in ADR 0013, specify that the launcher:
- creates, or reuses, a dedicated window station and desktop for `yagura-srv` (e.g. `YaguraSrv\Default`), with ACLs granting the account's logon SID, and passes it in `STARTUPINFO.lpDesktop`;
- calls `LoadUserProfileW` and builds the environment with `CreateEnvironmentBlock`.

Add "relay console starts under `yagura-srv` from the service" to the M2 spike.

**M3. The revision fix for round-1 M7 produces constant false conflicts.** (docs/adr/0008; proto/yagura/v1/instances.proto `Instance.revision`; docs/protocol.md "Calls and streams")

`revision` is "incremented on every change", and the `Instance` message includes runtime fields: state, health, pid, `queued_operations`, `restart_required`, `state_changed_at`. A running instance changes these continuously (health checks, crash restarts, queue changes). A client editing settings for a minute then gets `revision_conflict` without anyone else having edited anything.

Fix: make `revision` a configuration revision. It increments only on changes to settings, ports, secrets, mods, restart policy, Steam account, or a snapshot restore. Runtime fields do not bump it. State this in ADR 0008, the proto comment and protocol.md.

**M4. Content-store GC can delete a version a running instance still uses.** (docs/adr/0005; architecture.md "State ownership" content-store and instance-mod rows)

References are "derived from" each row's pinned version. `UpdateMods` on a running instance acquires the new version but defers re-linking until the instance is stopped. If the row's pin moves to the new version at that point, the old version has no reference while the running server's junctions still point at it. Long-running DayZ servers are common, so after 7 days GC deletes files under a live server. If instead the pin does not move, nothing records the pending update.

Fix: give the instance-mod row two fields, `staged_version` (what the junction points at now) and `desired_version`. GC treats both as references. Re-staging at stop/start sets `staged_version` to `desired_version`.

**M5. The client keepalive will be rejected by grpc-dart's server defaults.** (docs/protocol.md "Transport")

The client pings every 30 s. grpc-dart's `ServerKeepAliveOptions` defaults to `minIntervalBetweenPingsWithoutData` = 5 minutes and `maxBadPings` = 2, and data resets the counter. On a connection that only holds a quiet stream, the third 30 s ping trips the `tooManyBadPings` handling. The result is reconnect loops on idle `WatchInstances` and `Logs.Follow` streams, the kind most clients keep open.

Fix: state the server keepalive policy explicitly in protocol.md, e.g. `minIntervalBetweenPingsWithoutData: 20 s` to accept 30 s client pings. Add a test: an idle stream must survive 10 minutes.

**M6. The Linux process model in ADR 0009 contradicts the host-service spec and would kill servers on unit stop.** (docs/adr/0009 Decision; specs/host-service/spec.md "Stopping the unit keeps servers")

The ADR says `posix_spawn` with `setsid`. `setsid` does not leave the unit's cgroup, and systemd's default `KillMode=control-group` kills everything in it on stop or restart. The host-service spec instead says "transient scopes", and round 1's architecture said the same.

Fix: change ADR 0009 to start the relay in its own transient scope on Linux (`systemd-run --scope`, or the D-Bus `StartTransientUnit` call), and keep `setsid` only for terminal detachment.

### Suggestions

**S1. State-machine gaps** (architecture.md "Instance state machine"):
- `DeleteInstance` is allowed only from `stopped`. Allow it from `not_installed` and `error` too, for example when the plugin is missing.
- `error → starting` must be refused while the reason is `settings_invalid` or `plugin_missing`.
- Add `stopping → error` for when kill fails.
- State the preconditions for `RestoreSnapshot`, `ApplyMods` and `ApplyConfig`: stopped only, or which steps are deferred.
- Decide whether `on_crash` applies to a server that exited while the daemon was down (`lost_while_daemon_down`).

**S2. Snapshots:**
- `DeleteInstance` with `delete_files` is refused when there is no disk space for the pre-delete snapshot. That blocks the admin from freeing space; allow an explicit skip with `confirm_name`.
- DayZ's `data_paths` includes `{{profiles}}`, which holds multi-GB RPT/ADM logs. Add `exclude` globs.
- Write each snapshot to a temp directory, then rename it and insert its row, so a crash mid-snapshot never lists a partial snapshot as restorable.

**S3.** The server certificate is rotated only at startup. A daemon that runs for more than 2 years without a restart serves an expired certificate. Check daily, and rebind the listener with the new context, since `SecureServerSocket`'s context is fixed at bind.

**S4.** protocol.md "Device renewal" and pairing.proto say the daemon "accepts the old serial until it expires", but device identity is now the certificate's SHA-256. The device row needs a current and a previous fingerprint; say so.

**S5. Documentation drift:**
- Overview Steam Guard flow: it uses `AddSteamAccount`/`SubmitSteamGuard`; the proto has `Steam.AddAccount` and `Operations.RespondToPrompt`.
- Overview protocol surface: "Mods (add, remove, reorder)" vs `SetMods`, and "Steam (guard submit)".
- Proto: `PairingInfo.api_version` and the system.proto comment "Clients compare api_version major" are stale next to `api_versions`.
- ADR 0012 Context: still says "create symbolic links", but staging now uses junctions.

**S6.** SteamCMD is assigned to a kill-on-close job after spawn. On first run and on self-update, SteamCMD relaunches itself, which can escape before the assignment. Spawn it suspended through the same native path as the launcher (`CREATE_SUSPENDED`, assign to the job, resume). The startup sweep remains as a backstop.

**S7.** A heavy-operation slot (4 per host) is taken before the per-installation SteamCMD lock. Four updates on one Steam account then occupy every slot while running one at a time, and anonymous installs starve. Acquire the SteamCMD lock first, or do not count operations waiting on it against the slot limit.

**S8.** `CreateInstance.directory` and `ImportInstance.directory` accept any path. The daemon then grants `yagura-srv` modify on it, and `delete_files` removes it recursively; a mistyped `D:\` is destructive. Restrict instance directories to configured roots, and require the directory to be empty or non-existent at create.

**S9. Firewall rules for the daemon's own ports:**
- The rule `Yagura/daemon/api/tcp` should follow the configured `--bind` port and be reconciled like the others.
- The fallback pairing listener on port+1 (protocol.md) needs its own rule if adopted.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **docs/adr/0013, Decision:** add the paragraph "Trust boundary: everything under an instance directory is writable by `yagura-srv` and untrusted to the daemon. Every daemon file operation there (binder, key copy, staging, snapshot, restore, delete, hook host reads, log tailing) opens paths without following reparse points (`FILE_FLAG_OPEN_REPARSE_POINT`, per-component check) and fails with `sandbox_violation` on any reparse point other than the mod junctions recorded in instance-mod rows, which are re-verified against their expected target. Recursive delete and snapshot copy never descend into a reparse point." Add "untrusted reparse point refused" to the M2 spike/exit criteria in docs/overview.md.
2. **docs/adr/0010, Decision:** add "Before and after each `app_update` into an instance, the daemon checks the instance tree for reparse points not created by Yagura and fails with `sandbox_violation`; instances in `installing`/`updating` have no running server, so `yagura-srv` code is not running to race the check." Alternatively, install into daemon-owned staging and move the result in; state whichever is chosen.
3. **docs/adr/0009, step 4 (Re-attach) and step 1:**
   - The launcher reports the relay PID and creation time to the daemon on its stdout before exiting; this, not `relay.json`, is the source of the relay record.
   - The server PID from `relay.json` is accepted only if its parent PID is the recorded relay and its token user is `yagura-srv`.
   - Before any terminate, the daemon re-checks that the target's token user is `yagura-srv`.
   - Update the architecture.md "Run records" row to say the authoritative copy is the launcher report plus the verified `relay.json`.
4. **docs/adr/0009, step 1:** remove `CREATE_NEW_PROCESS_GROUP |`.
5. **docs/adr/0009, step 2:** replace "The relay ignores console control events" with "The relay installs a console control handler that returns TRUE (never `SetConsoleCtrlHandler(NULL, TRUE)`, whose ignore flag the server would inherit) and starts the server without `CREATE_NEW_PROCESS_GROUP`."
6. **docs/adr/0009, step 3:** change to "`yagurad signal --console-of <server pid>` (falling back to the relay pid) attaches to that console and calls `GenerateConsoleCtrlEvent(CTRL_C_EVENT, 0)`." In specs/instance-lifecycle/spec.md, stop requirement, replace "Windows CTRL_BREAK to the process group" with "Windows Ctrl+C to the server's console".
7. **docs/adr/0013, Decision:** after the `CreateProcessAsUserW` sentence, add "The launcher loads the account profile (`LoadUserProfileW`), builds its environment with `CreateEnvironmentBlock`, and starts the relay on a dedicated window station and desktop `YaguraSrv\Default`, whose ACLs grant the account's logon SID, passed in `STARTUPINFO.lpDesktop`." In docs/overview.md M2 "Proves", add "relay console starts as `yagura-srv` from the service".
8. **docs/adr/0008, proto/yagura/v1/instances.proto (`revision` comment) and docs/protocol.md:** define `revision` as incremented only on configuration changes (settings, ports, secrets, mods, restart policy, Steam account, snapshot restore), never on state, health, pid or queue changes.
9. **docs/adr/0005 and the architecture.md State ownership row "Instance-mod rows":** the row carries `staged_version` (current junction target) and `desired_version`. GC treats both as references. Re-staging while stopped sets `staged_version := desired_version`. Add `staged_version` next to `pinned_version` in mods.proto (as `desired_version`'s counterpart), or rename `pinned_version` to `desired_version` and add `staged_version`.
10. **docs/protocol.md, Transport table:** add a row "Server keepalive policy | `minIntervalBetweenPingsWithoutData` 20 s, `maxBadPings` 2 (accepts the 30 s client ping)", and a sentence that an idle stream must survive 10 minutes (test).
11. **docs/adr/0009, Decision, first sentence:** replace "`posix_spawn` with `setsid` on Linux" with "on Linux, the relay starts in its own systemd transient scope (`StartTransientUnit`), so stopping `yagurad.service` does not kill it".

Re-check (round 2, new reviewer run): I verified that all 11 Required Changes are present as specified, in ADR 0005, 0008, 0009, 0010 and 0013, architecture.md (Run records and Instance-mod rows), overview.md M2, protocol.md (revision definition and server keepalive row), instances.proto, mods.proto and the instance-lifecycle spec's stop requirement. Suggestions S3, S4, S6, S7 and S8 move to the init-core-platform design.

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

## Rebuttals

<!-- Author: fixed (cite) or rebutted (reason) per finding. A Critical/Moderate rebuttal counts only once marked "accepted by reviewer". -->
Round 1 author responses (all fixed; round 2 requested), with the round-2 reviewer's disposition:

- **C1 fixed**: ADR 0009 rewritten: native `CreateProcessW` spawn through a short-lived `yagurad launch` and a `yagurad relay` per server (new process group and console, breakaway, parent chain broken), `yagurad signal` delivers Ctrl+C via `AttachConsole`/`GenerateConsoleCtrlEvent`, exit waiters + `exit.json`; games use file logs where they can, relay stdout capture is the fallback. Architecture components and Failure and recovery updated. Graceful Valheim stop is an M1 exit criterion; service stop/upgrade leaving servers running is an M2 exit criterion (roadmap). **Accepted by reviewer.** The relay structure resolves the round-1 issues. The remaining Ctrl+C and launch details are tracked as round-2 M1 and M2.
- **C2 fixed**: ADR 0007: listener requests (not requires) client certificates; fail-closed interceptor tested per method; `docs/protocol.md` Per-call authorization, with a fallback of a separate pairing listener if the TLS spike shows request mode accepts untrusted certificates. **Accepted by reviewer.**
- **C3 fixed**: ADR 0005 rewritten: versioned immutable store `content/<source>/<app>/<item>/<version>/`, atomic publish from `.staging`, single-flight per item version, references from pinned instance-mod rows, re-link only while stopped, read-only to hooks and servers. **Accepted by reviewer.** The GC/staged-version gap is tracked as round-2 M4.
- **C4 fixed**: new ADR 0013: `yagura-srv` low-privilege account, `LogonUserW` + `CreateProcessAsUserW` in the launcher, directory ACLs; strategy boundary added. **Not accepted:** the account separation is right, but a compromised server can still get SYSTEM-level file writes, deletes and process kills through reparse points and `relay.json` in its writable instance directory. See round-2 C1, Required Changes 1-3.
- **C5 fixed**: architecture "Failure and recovery" table; startup recovery (stray SteamCMD killed, operations `interrupted`, states re-derived, staging and firewall re-run); SteamCMD in a kill-on-close job (ADR 0010). **Accepted by reviewer.** S6 notes a job-assignment race that the startup sweep backstops.
- **M1 fixed**: ADR 0007 + protocol.md: `Pairing.Info` returns the CA cert checked against the pin; fixed SAN `yagurad-<daemon-id>` used as TLS authority; server cert 2 years, rotated under 30 days; `Pairing.RenewCertificate`. **Accepted by reviewer** (see S3, S4).
- **M2 fixed**: local admin channel (named pipe, SYSTEM + Administrators) in ADR 0012 and the component table; ADR 0008 "state component" replaced by one owning component per table; CLI never opens the database while the service runs. **Accepted by reviewer.**
- **M3 fixed**: one SteamCMD run per installation (ADR 0010, bounds); M3 spike records Guard behaviour with stdin closed before timeouts are fixed. **Accepted by reviewer** (see S7).
- **M4 fixed**: hooks never write files: they return edits applied by the binder (ADR 0003, 0004); external edits re-read, patched, `external_edit` event, never block; `game_writes: true`; Yagura-owned DayZ config copy; BattlEye active-file rename handled by `create: true` template in the DayZ plugin. **Accepted by reviewer.**
- **M5 fixed**: update = stop → update → bindings → start if it was running (state machine); `validate` opt-in and config copies outside depot paths; explicit reload only with manifest snapshots per operation; plugin version change re-validates settings with optional `migrateSettings`, else `error: settings_invalid` / `plugin_missing` (ADR 0002). **Accepted by reviewer.**
- **M6 fixed**: state machine in architecture.md with every transition including stop-during-start and crash loop; exit waiters for re-attached servers (ADR 0009). **Accepted by reviewer** (remaining gaps in S1).
- **M7 fixed**: instance `revision` and `expected_revision` on every mutating call (ADR 0008, proto, protocol.md). **Not accepted:** the revision also increments on runtime state changes, which produces false `revision_conflict` errors. See round-2 M3, Required Change 8.
- **M8 fixed**: `data_paths` in the manifest, must resolve inside the instance (Valheim `-savedir`); snapshots before update and before delete-with-files, last 3 kept (architecture Save snapshots, bounds). **Accepted by reviewer** (see S2).
- **M9 fixed**: DPAPI user scope of LocalSystem (ADR 0011 renamed), ACLs (ADR 0013), password only in argv never a script file, scrubbed from output; SteamCMD token documented as an accepted exception (strategy, ADR 0010). **Accepted by reviewer.**
- **M10 fixed**: port uniqueness incl. derived ports (instance-lifecycle and plugin-manifest specs); `service install` adds the daemon port rule (ADR 0012); DayZ example binds `RConPort`. **Accepted by reviewer** (see S9).
- **S1** fixed (15 min no-progress + 12 h cap). **S2** fixed (junctions, name fixed at add). **S3** fixed (audit mutating + auth only). **S4** fixed (4 hook workers, host input caps). **S5** fixed (device id = cert SHA-256). **S6** fixed (CurseForge edge removed; xml stays in the format list but no milestone exit criterion depends on exact XML round-trip until a binding needs it). **S7** fixed (ADR 0011 title, 0007 wording, 0012 rejection reason). **S8** fixed (scheduler out of scope for v1, strategy + architecture). **S9** fixed (long-running executable required; `starting → stopped` when the process exits in the health window). **S10** fixed (`api_versions`). **All accepted by reviewer.** Residual wording drift is in round-2 S4 and S5. Note: the M3 milestone row in overview.md still lists "config bindings (dayz-cfg, json, xml)" under Delivers, which is acceptable since the exit criterion no longer depends on exact XML round-tripping.
