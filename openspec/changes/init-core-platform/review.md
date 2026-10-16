# Review

## Metadata

- **Round:** 2
- **Prior round:** Round 1 REVISE: 4 Critical (stop signal, state machine, app single-flight, SYSTEM file ops / forged run records), 20 Moderate, 11 Suggestions; the author reports all fixed.
- **Reviewer:** fresh-context subagent (Claude Code, `specwright-reviewer` role)
- **Reviewed:**
  - The change: `openspec/changes/init-core-platform/proposal.md`, `design.md` (D1-D21), all 13 `specs/*/spec.md`.
  - Baseline: `openspec/architecture.md`, `openspec/strategy.md`, `docs/adr/0001`-`0013`, re-reading 0005, 0008, 0009, 0010 and 0013 as changed by the baseline review.
  - Protocol: `docs/protocol.md`, `docs/overview.md`, `proto/yagura/v1/*.proto`.
  - Validation: `openspec validate init-core-platform --strict` passes. No requirement description is over 450 characters.
  - Not available: `tasks.md` does not exist yet, so the spike task numbers the design cites (1.2, 1.3, 10.1, 11.3, 14.1, 19.3, 21.3) could not be checked.
  - Per the coordinator, where D17 and Resource Bounds refine `architecture.md` tables, the design is treated as authoritative.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

Round-1 findings are resolved except as noted in Rebuttals. New findings follow.

### Critical (blocking)

**R2-C1. A compromised server in one instance can plant a junction that a SYSTEM `app_update` of another instance writes through.**
- *Location:* ADR 0010 Decision (the reparse-point check before and after `app_update`, justified by "instances in `installing`/`updating` have no running server, so `yagura-srv` code is not running to race the check"); ADR 0013 ACLs (`yagura-srv` modify on all instance directories); `design.md` D13 ("`app_update` checks the tree before and after"); `specs/steam-content/spec.md` "Install, update and validate apps" (no trust-boundary requirement).
- *Problem:* Every game server runs as the same `yagura-srv` account, and that account can modify every instance directory. So while instance A is `updating`, instance B's running server is `yagura-srv` code and can write into A's tree. It can plant a junction (for example `A\steamapps` or a game subfolder pointing at `C:\Windows\System32`) after the pre-check passes. SteamCMD then runs as a child of the daemon (LocalSystem) and follows the junction natively, because it does not go through InstanceFs. The post-check detects the junction only after SYSTEM has already written attacker-chosen paths. This is the host-takeover path that ADR 0013 and D13 exist to close, and the "nobody can race" reasoning is false whenever more than one instance exists.
- *Fix:* See Required Change 1. During install, update and validate, take `yagura-srv`'s access off the target instance root and restore it after the post-check. Optionally run SteamCMD with a token that cannot traverse junctions.

### Moderate

**R2-M1. The spec contradicts D17 on which requests are allowed from `error`.**
- *Location:* `specs/instance-lifecycle/spec.md` "Error reasons have defined exits" ("Other requests fail with `invalid_state`") and "Deleting an instance protects game data" ("SHALL require it to be stopped"); `design.md` D17 last row ("any | Stop, Delete | refused only while an operation runs").
- *Problem:* Under the spec, an instance in `error: plugin_missing` can never be deleted, because Delete needs `stopped` and leaving `plugin_missing` needs the plugin back. The admin cannot remove an instance whose plugin they deleted on purpose. The design says the opposite, so implementations and tests will disagree.
- *Fix:* Required Change 2.

**R2-M2. Autostart restarts crash-looping instances on every daemon restart.**
- *Location:* `design.md` D14 (last requested state stays "running" until Stop) and D17 (`crash_loop` + Start → `starting` with the restart counter reset); D9 leaves `error` unchanged at startup; `specs/instance-lifecycle/spec.md` "Autostart after daemon or host restart".
- *Problem:* An instance that reached `error: crash_loop` still has "last requested: running". Each daemon restart, including WinSW restart-on-failure loops, autostarts it through a normal Start, which D17 allows and which resets the counter. The crash-loop guard therefore never holds across restarts.
- *Fix:* Required Change 3.

**R2-M3. Rejecting a forged run record orphans the real server.**
- *Location:* `specs/instance-lifecycle/spec.md` "Only verified game server processes are terminated" / "Forged run file"; `design.md` D13.
- *Problem:* When `relay.json` names a foreign PID, the instance is reported `stopped`, but the genuine server, a child of the verified relay, keeps running untracked:
  - Stop cannot reach it.
  - Its ports stay bound.
  - Autostart or a later Start launches a second server that fails on the same ports or corrupts the same save directory.

  The daemon already holds an authoritative relay record from the launcher, so it does not need `relay.json` to find the server.
- *Fix:* Required Change 4.

**R2-M4. Lock and slot acquisition order is not defined for operations that need more than one SteamCMD installation.**
- *Location:* `design.md` D3 ("one of 4 heavy slots is taken ... after it holds any SteamCMD installation lock it needs") and D7; Update steps `download` then `update_mods` (`specs/instance-lifecycle/spec.md` "Update while running").
- *Problem:* Suppose an update holds the anonymous installation lock and a heavy slot for `download`, then needs an account installation's lock for `update_mods`. Meanwhile other operations hold that account lock and wait for a heavy slot. If all 4 slots are held by operations in the first position, nothing progresses, and no timeout covers lock or slot waits. This is a deadlock.
- *Fix:* Required Change 5.

**R2-M5. Graceful stop under the service identity is not covered by any spike or scenario.**
- *Location:* `design.md` Context (spike 1.3: Ctrl+C delivery in console mode; spike 11.3: relay console starts as `yagura-srv` on `YaguraSrv\Default`); D2 (`signal` attaches to the server console); `specs/instance-lifecycle/spec.md` "Valheim saves on a signal stop".
- *Problem:* In production, `yagurad signal` runs as LocalSystem and must `AttachConsole` to a console owned by `yagura-srv` on a separate window station. Spike 1.3 proves delivery only as the current user. Spike 11.3 proves only that the console starts. If the attach fails across identities, every Valheim/SCUM stop under the service becomes a kill: the round-1 C1 data loss comes back unnoticed. D2 also no longer says that the helper ignores the `CTRL_C_EVENT` it sends to its own console (ADR 0009's earlier text did), so the helper can be killed before it reports success.
- *Fix:* Required Change 6.

**R2-M6. Residual naming drift from round-1 M3.**
- *Location:*
  - `specs/desktop-client/spec.md` "Steam Guard prompt" ("an operation emits `steam_guard_required`"). The proto models this as a `Prompt` with `WAITING_FOR_INPUT`, and `docs/protocol.md` has no `steam_guard_required`.
  - `specs/instance-lifecycle/spec.md` "One operation per instance at a time" ("At most 4 install or update operations"). D3 defines the heavy set as install, update, validate, apply_mods and update_mods.
- *Problem:* Tests written from the specs will assert an event name the proto cannot carry, and a heavy-slot limit that does not count validate or mod operations.
- *Fix:* Required Change 7.

**R2-M7. `UpdateSettings.autostart` is a plain proto3 bool on a full-replace call, so any client that omits it turns autostart off.**
- *Location:* `proto/yagura/v1/instances.proto` `UpdateSettingsRequest.autostart = 7` (and `restart_policy`, `steam_account_id` as plain strings); D14 (default on).
- *Problem:* Proto3 cannot distinguish "false" from "not set". A client that edits only settings sends `autostart=false` and silently disables autostart, and that change also bumps the revision. The same applies to scripts and grpcurl. An empty `steam_account_id` likewise either unlinks the account or is ignored; nothing says which.
- *Fix:* Required Change 8.

**R2-M8. The instance roots that create and import depend on have no API or spec.**
- *Location:* `design.md` D21 (`yagurad roots add`); `specs/daemon-security/spec.md` "Local admin channel is restricted to administrators" (lists only `pair`, `devices`, `status`); `specs/instance-lifecycle/spec.md` "Import a copied instance" and `specs/host-service/spec.md` "Instance on another drive" (both assume a configured root).
- *Problem:* Placing instances on another drive or importing one is untestable as specified. The command that makes it possible is not in the restricted-command list or in any requirement, so it is also unclear whether a remote client could add `C:\` as a root.
- *Fix:* Required Change 9.

### Suggestions

**R2-S1. The desktop-client connection states omit `expired`.**
- *Location:* "Multiple paired daemons" lists `connected`, `connecting`, `offline`, `incompatible`, `revoked`; the renewal requirement uses `expired`.
- *Fix:* Add `expired` to the list. Required Change 10.

**R2-S2. The firewall spec names an RPC that does not exist.**
- *Location:* `specs/firewall-rules/spec.md` refers to `ListFirewallRules`; the proto method is `Firewall.ListRules`.
- *Fix:* Use `Firewall.ListRules`. Required Change 10.

**R2-S3. Port collision checks ignore ports a running instance launched with.**
- *Location:* port collision (instance-lifecycle create, plugin-manifest "Derived port collides").
- *Problem:* While A runs on 2456 with a saved change to 2466, a new instance B can take 2456 (D16 keeps A listening on its launched ports) and then fails to bind.
- *Fix:* Check against both saved and launched ports.

**R2-S4. A failed stray-SteamCMD sweep is only a degraded step.**
- *Location:* D9.
- *Problem:* If a stray SteamCMD survives the sweep, new runs on that installation break D7's one-process rule.
- *Fix:* Mark that installation unavailable until a sweep succeeds.

**R2-S5. Two mods can ship the same key file name with different content.**
- *Location:* D19.
- *Fix:* Say which key wins, or raise `key_conflict` between mods too.

**R2-S6. ADR 0010's reasoning is now wrong.**
- *Location:* ADR 0010 sentence "instances in `installing`/`updating` have no running server, so `yagura-srv` code is not running to race the check".
- *Fix:* Correct it through the baseline process after Required Change 1. This is not part of this change.

**R2-S7. `docs/overview.md` is stale.**
- *Location:* `docs/overview.md`: `SubmitSteamGuard`, the event `steam_guard_required(kind)`, the "Mods (list, add, remove, reorder)" service list.
- *Fix:* Align it with the proto. It is not a contract document, but it is the first page readers see.

**R2-S8. The revision lists disagree.**
- *Location:* the spec's list includes `autostart` (and D14 makes it configuration); ADR 0008, `docs/protocol.md` and the `instances.proto` comment omit it.
- *Fix:* Add `autostart` to `docs/protocol.md` and the proto comment now, and to ADR 0008 at the next baseline touch. Required Change 10.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **R2-C1.**
   - In `design.md` D13, replace "`app_update` checks the tree before and after (ADR 0010)." with: "During install, update and validate, the daemon removes `yagura-srv`'s access entry from the target instance root (the instance has no running server), runs the reparse-point check, runs `app_update`, re-runs the check, and only then restores the ADR 0013 ACL; a failure at any point leaves the ACL removed and the operation fails with `sandbox_violation` or its own reason. This holds against other instances' servers, which run as the same account."
   - Add a Mechanism Ledger row "ACL withdrawal during SteamCMD runs | yes | other instances' servers share `yagura-srv` and could plant junctions SteamCMD (SYSTEM) follows | per-instance accounts".
   - In `specs/steam-content/spec.md` "Install, update and validate apps", append: "While SteamCMD writes into an instance directory, the game-server account SHALL have no access to it." Add a scenario:
     - **WHEN** instance A is updating and instance B's server process (running as `yagura-srv`) tries to create a junction inside A's directory
     - **THEN** the attempt fails with access denied, and after the update A's directory has the game-server account's access restored.
2. **R2-M1.** In `specs/instance-lifecycle/spec.md` "Error reasons have defined exits", replace "Other requests fail with `invalid_state`." with "Stop and Delete are allowed from any reason when no operation runs; other requests fail with `invalid_state`." In "Deleting an instance protects game data", replace "SHALL require it to be stopped" with "SHALL require it to be `stopped`, `not_installed` or `error` with no running operation". Add a scenario:
   - **WHEN** an instance in `error` with `plugin_missing` is deleted without `delete_files`
   - **THEN** it disappears from listings and its directory is left on disk.
3. **R2-M2.** In `design.md` D14, append "Instances in `error` are not autostarted; entering `error: crash_loop` clears the last requested state." In `specs/instance-lifecycle/spec.md` "Autostart after daemon or host restart", add a scenario:
   - **WHEN** an instance is in `error` with `crash_loop` and the daemon restarts
   - **THEN** it stays in `error` and is not started.
4. **R2-M3.** In `design.md` D13, append "If `relay.json` fails verification, the daemon identifies the server as the verified relay's child running as `yagura-srv` (by parent PID and token user); if none is found, it terminates the verified relay, whose exit ends its console's processes, and reports `error` with reason `run_record_rejected`." In `specs/instance-lifecycle/spec.md` scenario "Forged run file", replace the THEN with:
   - **THEN** the daemon refuses to terminate that process, stops the genuine server through the verified relay, reports notice `run_record_rejected`, and the system process keeps running.
5. **R2-M4.** In `design.md` D3, replace "after it holds any SteamCMD installation lock it needs" with "per step: a step acquires the SteamCMD installation lock it needs, then a heavy slot, and releases both when the step ends; no step holds a lock or slot while waiting for another installation's lock". Add a Flow & State Gaps bullet: "Update needing two installations (app anonymous, workshop account): locks and slots are taken per step, so no circular wait."
6. **R2-M5.**
   - In `design.md` Context, extend spike 11.3 to read "WinSW leaving relays running, the relay console starting as `yagura-srv` on its own window station, and `yagurad signal` running as LocalSystem delivering Ctrl+C to that console (Valheim saves)".
   - In D2, append to the `signal` sentence: "the helper ignores the event itself (`SetConsoleCtrlHandler(NULL, TRUE)` in the helper only) and exits 0 after `GenerateConsoleCtrlEvent` returns."
   - In `specs/instance-lifecycle/spec.md` scenario "Valheim saves on a signal stop", change the WHEN to "a client stops a running Valheim instance started by the installed service (server running as `yagura-srv`) whose strategy is `signal`".
7. **R2-M6.**
   - In `specs/desktop-client/spec.md` scenario "Steam Guard prompt", replace "an operation emits `steam_guard_required` with kind `authenticator`" with "an operation enters `waiting_for_input` with a prompt of kind `authenticator`".
   - In `specs/instance-lifecycle/spec.md` "One operation per instance at a time", replace "At most 4 install or update operations run at once across the host" with "At most 4 heavy operations (install, update, validate, apply_mods, update_mods) run at once across the host".
8. **R2-M7.**
   - In `proto/yagura/v1/instances.proto` `UpdateSettingsRequest`, declare `optional bool autostart = 7;`, `optional string restart_policy = 4;` and `optional string steam_account_id = 5;`, with the comment "unset = unchanged; empty steam_account_id = unlink".
   - Add to `specs/instance-lifecycle/spec.md` "Concurrent edits are detected by revision" a scenario:
     - **WHEN** a client saves settings without setting `autostart`
     - **THEN** the instance's `autostart` value is unchanged.
9. **R2-M8.**
   - In `specs/daemon-security/spec.md` "Local admin channel is restricted to administrators", change "(`pair`, `devices`, `status`)" to "(`pair`, `devices`, `status`, `roots`)".
   - Add to `specs/host-service/spec.md` "Data directory layout" the sentence "Instance roots are added and removed only with `yagurad roots add|remove` over the local admin channel; the gRPC API cannot change them." Add a scenario:
     - **WHEN** an administrator runs `yagurad roots add D:\servers`
     - **THEN** creating an instance under `D:\servers` is allowed and no remote call can add or remove a root.
10. **R2-S1, R2-S2, R2-S8.**
    - In `specs/desktop-client/spec.md` "Multiple paired daemons", add `expired` to the state list.
    - In `specs/firewall-rules/spec.md`, replace `ListFirewallRules` with `Firewall.ListRules`.
    - In `docs/protocol.md` (the "Calls and streams" revision sentence) and the `instances.proto` `revision` comment, add `autostart` to the configuration list.

Re-check (2026-10-16, fresh-context subagent): Required Changes 1-10 verified in design.md (D2, D3, D13, D14, Context 11.3, Flow & State Gaps, Mechanism Ledger), the steam-content, instance-lifecycle, desktop-client, daemon-security, host-service and firewall-rules specs, instances.proto and docs/protocol.md; `openspec validate --strict` passes. R2-S6 (ADR 0010 race reasoning) will be handled by a superseding ADR in the tasks' first ADR group.

CHANGES_APPLIED: yes

## Rebuttals

Round 1 author responses (all reported fixed), with reviewer disposition:

- **C1 fixed**: instance-lifecycle stop requirement now says Ctrl+C to the server's console; design D2 (relay clears the inherited ignore flag with `SetConsoleCtrlHandler(NULL, FALSE)`, installs a TRUE handler, no `CREATE_NEW_PROCESS_GROUP`; `signal --console-of <server pid>` with `GenerateConsoleCtrlEvent(CTRL_C_EVENT, 0)`); T1 label fixed; scenario "Valheim saves on a signal stop" added; ADR 0009 aligned.
  - *Accepted by reviewer.* Verification under the service identity is tracked as R2-M5.
- **C2 fixed**: design T2 refers to the architecture state machine; D17 error-reason exit table; new requirement "Error reasons have defined exits" (Acknowledge, Start refused for settings_invalid, Update clears update_interrupted); "Queued operation becomes invalid" now uses `not_installed`.
  - *Accepted by reviewer.* The new spec/D17 conflict on Stop/Delete is tracked as R2-M1.
- **C3 fixed**: D7: single-flight only for content-store items `(source, app, item, version)`; app runs keyed `(app, branch, instance directory)` on the installation lock; steam-content scenario "Two instances of one app installed at once".
  - *Accepted by reviewer.*
- **C4 fixed**: D13 (InstanceFs: handle-relative opens, no reparse following, `GetFinalPathNameByHandle` checks, recorded junctions re-verified, delete/snapshot never descend; relay PID from the launcher, server PID verified by parent and token user, token check before every terminate); instance-lifecycle requirements "Daemon file operations do not follow links planted in instance directories" and "Only verified game server processes are terminated"; ADRs 0009/0010/0013 aligned.
  - *Not accepted, in part.* The daemon's own file operations and process verification are accepted. The `app_update` path still lets SYSTEM write through junctions planted by another instance's server (R2-C1), and a rejected run record orphans the real server (R2-M3).
- **M1 fixed**: D3 (progress coalesced per step, `events_dropped` + snapshot); daemon-protocol scenario; proto `EventsDropped`.
  - *Accepted by reviewer.*
- **M2 fixed**: revision = configuration only (spec, ADR 0008, proto, protocol.md); scenario "Runtime state does not change the revision"; requirement wording limited to configuration calls.
  - *Accepted by reviewer.* The `autostart` list drift is tracked as R2-S8.
- **M3 fixed**: `external_edit` everywhere; `steam_stalled`, `prompt_resolved`, `queue_full`, `too_many_subscribers`, `pairing_throttled` and others in protocol.md; Prompt kinds `email`/`authenticator`/`mobile_approval` in specs and proto; `mods_update_available` on `Instance`; heavy set defined once in D3.
  - *Not accepted, in part.* `steam_guard_required` remains in the desktop-client spec, and instance-lifecycle still says "install or update" (R2-M6).
- **M4 fixed**: config-bindings scenario "Secret values masked in the event". *Accepted by reviewer.*
- **M5 fixed**: D16 (rules follow launched ports while running, saved ports otherwise, installed instances only); firewall scenarios for stopped and running port changes. *Accepted by reviewer.*
- **M6 fixed**: D9 fatal vs degraded startup steps; host-service requirement rewritten with scenario "Firewall unavailable at startup". *Accepted by reviewer.*
- **M7 fixed**: OS exclusive lock (`LockFileEx`/`flock`); scenario rewritten. *Accepted by reviewer.*
- **M8 fixed**: running instances keep running with `settings_invalid` flag; `migrateSettings` added to hook points with contract, revision increment and failure scenario. *Accepted by reviewer.*
- **M9 fixed**: D19 key ownership; scenarios "Shared key kept", "Admin's own key with the same name". *Accepted by reviewer.*
- **M10 fixed**: staged/desired versions (ADR 0005, spec, mods.proto); scenario "Update requested for a running instance". *Accepted by reviewer.*
- **M11 fixed**: D3 heavy slot after the SteamCMD lock, `waiting_for_steamcmd`, stall timer from SteamCMD start; D7 waiter detach; scenarios in steam-content and mod-management.
  - *Accepted by reviewer.* Lock and slot ordering across steps is tracked as R2-M4.
- **M12 fixed**: D12 (snapshots volume, restore pinning, orphan listing 30 days, `ListOrphanSnapshots`); three scenarios. *Accepted by reviewer.*
- **M13 fixed**: D20 aggregated auth failures in a separate table; audit requirement and "Scanner flood" scenario. *Accepted by reviewer.*
- **M14 fixed**: D20 device certificate rows; `DeviceCertificate` in pairing.proto; protocol.md wording; scenario "Revoking a renewed device". *Accepted by reviewer.*
- **M15 fixed**: desktop-client requirement "Device certificate renewal by the client".
  - *Accepted by reviewer.* The missing `expired` state is tracked as R2-S1.
- **M16 fixed**: D4 slot release, leak count in `GetHealth`, `hook_runtime_degraded` at 2; plugin-hooks scenario. *Accepted by reviewer.*
- **M17 fixed**: D15 slim deltas and 8 MiB per-subscriber bound; daemon-protocol scenario "State-only delta". *Accepted by reviewer.*
- **M18 fixed**: D14 autostart (default on); requirement "Autostart after daemon or host restart"; proto `autostart`.
  - *Accepted by reviewer.* The crash-loop interaction is tracked as R2-M2 and the proto presence issue as R2-M7.
- **M19 fixed**: D18 cancellation/stop table; scenarios for update-after-stop cancel, stop during health wait, stop cancels queued starts. *Accepted by reviewer.*
- **M20 fixed**: D21 instance roots and overlap checks, ACLs on create/import; scenario "Directory outside the instance roots".
  - *Accepted by reviewer.* Managing roots has no spec yet; tracked as R2-M8.
- **S1-S11 fixed**: S1 (per-address throttle, D20), S2 (masking in backlog and crash notices, replaced values 24 h, length rule), S3 (relay.json holds no command line, D2; GSLT scenario), S4 (D12 + scenario), S5 (scenario "RCON unavailable during stop"), S6 (memory and timeout THENs measurable; stdout wording observable; desktop pairing THEN asserts only the CSR is sent), S7 (failure scenarios for instance.json, data directory, daemon port rule, RCON exposure, hook points via migration failure, Linux service), S8 (proposal wording), S9 (daemon API port, serialised creates), S10 (`update_mods` step), S11 (worker wait excluded from the deadline).
  - *Accepted by reviewer.*
