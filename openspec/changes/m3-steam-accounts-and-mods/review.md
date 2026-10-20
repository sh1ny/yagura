# Review

## Metadata

- **Round:** 2
- **Prior round:** 1
- **Re-check:** amendment re-check. A spec amendment made during apply (task 3.3) voided the round-1 verdict. The amendment aligns the specs with design D9's single config pass: `specs/config-bindings/spec.md` "Bindings map settings to file keys", `specs/plugin-hooks/spec.md` scenario "Mods-staged hook edits a config", and `proposal.md` "Config bindings" (bindings apply on every start in one pass with the start's hook edits, bindings first; `ApplyConfig` stays unimplemented in M3). This round judged three questions only: whether the amendment makes specs, proposal and design consistent, whether it contradicts anything else, and whether dropping `ApplyConfig` from M3 is coherent with the roadmap.
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code)
- **Reviewed:** `git diff -- openspec/changes/m3-steam-accounts-and-mods`; `proposal.md`; `design.md` (D7 step 5, D9, T3 diagram, ADRs section); `tasks.md`; the delta specs `config-bindings`, `plugin-hooks`, `instance-lifecycle` and `plugin-manifest` (every delta was grepped for `binding`, `onPreStart` and `ApplyConfig`); main specs `plugin-hooks`, `instance-lifecycle` and `plugin-manifest`; `docs/protocol.md` (methods by version); `docs/plugins/hooks.md`; `openspec/roadmap.md` (M3, M4, Later); `openspec/architecture.md` (ADR table); ADR 0004; `openspec/changes/platform-backlog` (working-tree specs, proposal and tasks, grepped for `ApplyConfig`). Source checked: `apps/yagurad/lib/src/api/instances_api.dart:347-350`, `instances/lifecycle.dart:174,244,309-311,401-402`, `proto/yagura/v1/instances.proto:33`, `security/method_access.dart:45`. Skills loaded: none (none named).

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Round 2 (amendment re-check)

**What holds.**
- The amended config-bindings requirement, the plugin-hooks scenario and the proposal now agree with:
  - design D9 "Binder": `Start` makes one pass with bindings, `onModsStaged` edits and `onPreStart` edits, in that order;
  - D7 step 5: `onModsStaged` edits are re-applied with the bindings on every stage step;
  - the T3 diagram: one binder call after `onPreStart` returns;
  - `docs/plugins/hooks.md:86`: "the bindings first, then the edits in order".
- No delta spec or scenario still requires bindings before `onPreStart`, and none requires any `ApplyConfig` behaviour. The remaining `ApplyConfig` mentions all fit "stays unimplemented": the proto method (`instances.proto:33`), the stub that throws `not_implemented` (`instances_api.dart:347-350`), its access entry, and the M1 and M2 rows of `docs/protocol.md`.
- The config-bindings scenarios "Scalar binding applied", "Bound file missing" and "Missing file created from the plugin template" state their outcome relative to the launch, and the new wording keeps that.
- Dropping `ApplyConfig` from M3 fits the M3 outcome and exit criteria. They require config files written through round-tripping bindings and manual-edit detection, and the start-time pass meets both. No criterion names a re-apply while the server runs.

#### Critical (blocking)

None.

#### Moderate

**R2-M1. In-force ADR 0004 still states the ordering the amendment removed.**
ADR 0004 is accepted, and the design's "ADRs" section lists it as in force and constraining this change. It says "Bindings apply before `onPreStart`; the same parsers are exposed to hooks as host functions for cases bindings cannot express" (`docs/adr/0004-config-bindings-with-round-trip-parsers.md:11`), and the old spec wording came from that sentence. After the amendment, `onPreStart` runs before the bindings are applied, so it reads bound files as they were before this start's bindings. The user accepted that consequence, but the ADR records the opposite. The design's ADRs section says "To record during apply: none", so nothing brings the two into line. The consequences:
- The architecture baseline keeps a decision that the implementation contradicts.
- ADR 0004 is the reference for how hooks and bindings interact, so a plugin author who reads it will expect bound values to be visible in `onPreStart`.

The design needs to record the change in one of two ways. Either write a superseding ADR, the mechanism that `architecture.md`'s ADR table provides. Or, if the project treats the sentence as a wording correction, add an amendment note to ADR 0004 stating that bindings and hook edits apply in one pass after the hooks return, bindings first. In both cases, update the design's "ADRs: To record during apply".

**R2-M2. `ApplyConfig` now has no owner in any plan.**
In round 1, the backlog's config-bindings requirement carried "on every start and on `ApplyConfig`". That requirement moved from `platform-backlog` into this change (the working-tree `platform-backlog/specs/config-bindings/spec.md` deletes "Bindings map settings to file keys"), and the amendment now drops the `ApplyConfig` half from M3. `grep` finds `ApplyConfig` nowhere in `openspec/changes/platform-backlog`, and `openspec/roadmap.md` does not name it under M4 or "Later". The proposal's "`ApplyConfig` stays unimplemented in M3" implies that it arrives later, but nothing parks it. The consequences:
- The roadmap's backlog rule ("when a milestone starts, take its part of the backlog ... and delete that part") lets the method drop out of the plan without anyone deciding it.
- A defined `yagura.v1` method stays `not_implemented` with no milestone that will build it.

Park it. Either add the `ApplyConfig` requirement to `platform-backlog` under a named milestone (one pass that applies all bindings of a stopped or running instance, with its operation step), or record in the proposal that it is dropped from the roadmap and why.

#### Suggestions

- **R2-S1. The update path is still worded as a sequence that matches the old start ordering.**
  - The instance-lifecycle delta "Updates stop and restart a running server" lists "re-apply bindings, run the plugin's `onPostUpdate` hook and apply its file edits (step `apply_config`)". That reads as bindings before the hook runs. D9 instead makes one pass after `onPostUpdate` returns (bindings, `onModsStaged` edits, `onPostUpdate` edits), and `lifecycle.dart:309-311` already runs the hook first.
  - The plugin-hooks requirement calls each hook "after the daemon's own work for that step", which a reader may take to include applying the bindings.

  Neither statement is false under a loose reading, and the scenarios check only step names. But the start-path amendment was made for exactly this ambiguity. Consider "run the plugin's `onPostUpdate` hook, then apply the bindings and its file edits in one pass (step `apply_config`)".
- **R2-S2. Task 11.2 should name `ApplyConfig` in the M3 protocol row.** Task 11.2 lists what M3 implements, plus "still not `Rcon`". The M2 row of `docs/protocol.md:140` lists `Instances.ImportInstance`, `ExportInstance` and `ApplyConfig` as not implemented. The M3 row should keep `ApplyConfig` in that list, so the document matches the proposal.

### Round 1 (history)

The round-1 findings, the round-1 verdict (approve with changes) and its Required Changes are kept below as history. All nine round-1 Required Changes were applied and re-checked in round 1 (see Rebuttals, round 1).

#### Critical (blocking)

None.

#### Moderate

**M1. D12 and the mod-management specs mix up the instance root and the server's working directory, so the DayZ plugin as designed cannot find its config, BattlEye path or mods.**
The game is installed into `<instance>/server` and launched with that as its working directory (`lifecycle.dart:31,120,341,347`). `data_paths` resolve against the instance root (`templates.dart:303-312`), and bindings are "relative to the instance root" (config-bindings spec). D12 then has:
- bindings write `<instance>/yagura/serverDZ.cfg`, while `-config=yagura/serverDZ.cfg` and `-BEpath=yagura/battleye` resolve against `<instance>/server`;
- the spec scenario "DayZ mod linked" puts the junction at `<instance>/@Community-Framework`, while `-mod=@Community-Framework` resolves against `<instance>/server`;
- `data_paths: [mpmissions/, profiles/]` resolve to `<instance>/mpmissions`, while DayZ's `mpmissions` ships in the depot under `server/`, and `-profiles=profiles` writes `<instance>/server/profiles` while the log sources read `profiles/*.RPT`.
The consequence: the exit criterion 3 run fails on the real host (task 10.3), which is late and expensive to find. The design has to fix one frame of reference: where links are staged (instance root or `paths.server`), whether `mods.<role>` carries names or absolute paths, and the DayZ args, bindings, data paths and log sources written against it. The spec scenario path has to match.

**M2. D6 does not say who owns the SteamCMD run, the installation lock and the heavy slot once an owner is cancelled and its keys move to a waiter.**
`ctx.heavy` holds the runner's installation lock and a host slot for the length of `body()`, and the steam call gets the operation's own `CancelToken` (`operation_runner.dart:626-661`, `lifecycle.dart:116-131`). D6 says a cancelled owner "hands its keys to a remaining waiter, which keeps the run going", and the spec says the cancelled operation "ends `cancelled`". Two readings, and both break something:
- The owner's operation ends: its `heavy()` returns, so the lock and slot are released while SteamCMD still runs. The 4-slot limit and the one-run-per-installation lock in the runner then no longer count the run, and the run's events have no operation to go to.
- The owner's operation waits for the run: then it does not end `cancelled` promptly.
The waiter may also use another account and installation than the run. The flow-gap bullet about "installation locks per batch in a fixed order" implies an operation holds a lock while waiting on another's keys, and D6 does not say whether a waiter waits inside or outside a heavy slot. If 4 waiters hold slots while waiting on keys whose owners are queued for a slot, nothing ever proceeds. The design needs to state that the acquisition run is owned by the mod pipeline, not by an operation: the pipeline takes the installation lock and a heavy slot itself, uses its own cancel token, and is cancelled when its last waiter detaches. It also needs to state that waiting on another operation's keys holds no lock or slot.

**M3. D10's migration operation is queued behind operations that already run with the new manifest and the unmigrated settings.**
An operation reads `registry.find(...).manifest` when it starts executing, not when it is queued (`lifecycle.dart:166-169,274-277`). A `Start` queued before `ReloadPlugins` therefore runs ahead of the `migrate_settings` operation that D10 appends to the same queue. It renders the new manifest's templates over the old settings (in the spec example, `verboseLogs` is missing), and nothing has re-validated them. D10's stated goal ("never races an operation that holds the old manifest") covers only the running operation. Related gaps:
- A full queue (10, `operation_runner.dart:139-145`) makes the enqueue fail, and D10 says nothing about what happens to that instance.
- After a failed migration the stored version stays old. When the admin then saves valid settings (the `settings_invalid` exit, instance-lifecycle "Error reasons"), D10 does not say whether the new version is recorded, so the next reload could run `migrateSettings(from: old)` over settings already in the new shape.
- Today's `reconcilePlugins` already writes the new `pluginVersion` on a valid version change (`instance_manager.dart:1312-1320`). That write has to go, or the next pass no longer detects the change.
The design needs to state that an operation which starts while `record.pluginVersion != manifest.version` waits for, or fails behind, the migration (or that the migration goes to the head of the queue). It also needs to say what a full queue does, and that a valid settings save records the loaded plugin version.

**M4. D4's secret arguments go over a channel that exists only in service mode and stops at the launcher.**
D4 says the daemon adds the secrets "to the JSON line it already writes to the launcher's stdin". That line is written only with `--as-account` (`windows_process_host.dart:173-185`, `run_command.dart:195-205`). In console mode, which is how CI and the integration tests run, nothing is written. The relay itself gets no stdin pipe in either mode: it is spawned with `CREATE_NEW_CONSOLE` and no standard handles (`launcher_modes.dart:72-80,128-146`). The launcher exits once `relay.json` appears, and the relay writes `relay.json` before it spawns the server (`launcher_modes.dart:248,280-300`). D4 therefore needs new plumbing in both modes: a stdin line in console mode, an inheritable pipe into `CreateProcessAsUserW` and `spawnProcess` with `STARTF_USESTDHANDLES`, and the relay reading the secrets before `writeRelay`. The design understates this, and the steam-content "Token injected at launch" scenario would pass in service mode and fail, or go untested, in console mode. D4 should state the console-mode path and the relay's read point.

**M5. The password-on-disk guarantee depends on SteamCMD's own log files and on the expired-login behaviour, and spike A1 covers neither.**
The steam-content scenario "Password absent from output" asserts that no file in the data directory contains the password. ADR 0014 says it never touches disk. D3's scrubber covers only the output the daemon captures. SteamCMD writes its own logs under its installation (`<data>/steamcmd/<acct>/logs/`), and the design does not check whether they carry the echoed `+login user pass` line. The "Cached login expired" path is not in A1 either: with `+login <user>` alone, stdin on NUL and no password, SteamCMD may print a password prompt and wait or loop rather than fail. D2's `reauth_needed` pattern depends on that behaviour. Add both to A1 (task 1.1): scan the installation's files after a login, and record the expired-cache behaviour with stdin closed. Also state the fallback if SteamCMD's logs do carry the password, for example scrubbing or deleting them after each login run, or naming them an accepted exception next to `config.vdf`.

**M6. The staged name needs workshop metadata at `SetMods` time, and the design does not say when metadata is read or what happens when it cannot be.**
D7 fixes the staged name "on first add" from the link template `@{{mod.name_safe}}`, which needs the item's title. `SetMods` is a call (`mods.proto`), the Web API is paced at 1 request/s with a 15 s timeout (D5), and the desktop spec shows the 12 new mods as `pending` "with their names once the daemon has their metadata". Open points:
- whether `SetMods` blocks on the Web API;
- what name a mod gets when the API is down or the item is private (ADR 0005 allows `@<id>`);
- when a pending mod's name is fixed if it is fetched later.
This decides whether exit criterion 3's "one action" works with Steam's API unreachable, and whether launch arguments change after the first start. The design needs to state when the name is fixed and the fallback.

**M7. D7's staging deletes whatever sits at the staged name, including an admin's own mod folder.**
D7 step 3 says: "remove whatever entry exists at its staged name without following it". D7 de-duplicates names only between Yagura's own mods (`-2`, `-3`), not against existing entries in the instance. DayZ admins who move an existing server into Yagura commonly have hand-installed `@CF`-style folders, and staging would delete such a folder, along with any edited mod configs in it. This is the T6 data-loss case the design applies to keys (D8, "never placed over an admin's key"), but not to mod folders. Copy-mode folders also have no record that tells them apart from an admin's folder. The design needs one of two rules: de-duplicate against existing non-Yagura entries when the name is fixed, or refuse with a named reason (for example `stage_name_conflict`) when the entry is neither a recorded junction nor a recorded copy. It should also say how copies are recorded.

**M8. An account left in `adding` by a daemon restart has no recovery.**
`steam.proto` lists accounts with status `adding`, so the row exists while the operation runs. Startup recovery marks the operation `interrupted` (`operation_runner.dart:329-345`), but D1, the account state diagram and the Failure table ("no account saved") do not say who deletes the `adding` row. The same goes for its partly bootstrapped `<data>/steamcmd/<id>/` and for a `steam:<id>` secret stored just before the row would have turned `ready` (D3). The consequence is a ghost account counting toward the 32-account bound, refusing a new `AddAccount` for the same username, and a stored password with no account. Add a startup step that removes `adding` rows with their secret and installation (no-follow delete).

**M9. The daemon-protocol delta leaves a main-spec scenario false and gives the new stream no requirement.**
The main spec scenario "Service not built yet" (daemon-protocol, "Methods a daemon version does not implement") uses `Mods.ListMods`, which this change implements, so after the archive the spec asserts something the daemon no longer does. Separately, `Operations.WatchPrompts` (D13) is a new protocol method with a snapshot, `raised`/`resolved` events, 32 subscribers and `resync_required`, but no spec requirement or scenario covers it. Only the desktop "Prompt from another device's operation" scenario touches it, from the client side. The `RespondToPrompt` refusals (`prompt_resolved`, `prompt_answer_invalid`) also have no daemon-side scenario. Modify the requirement so its examples use a still-unbuilt service (for example `Rcon.Execute`), and add a daemon-protocol requirement for `WatchPrompts` and `RespondToPrompt` with a failure scenario (a late answer, a too-many-subscribers refusal).

#### Suggestions

- **S1. The heavy-limit scenario does not match what the slot covers.** The scenario says "the install waits in the queue until one of the four ends". The slot is held only around SteamCMD runs (`ctx.heavy`), so it frees before the operation ends (publish copy, staging), and the waiting install shows `waiting_for_steamcmd`, not a queue position. A `Start` that downloads mods also takes a slot, but `start` is not in the requirement's list. Reword the requirement to "heavy steps" and the THEN to "until one of them releases its SteamCMD slot".
- **S2. D9's apply passes are inconsistent.** D9 lists `onPreStart` edits inside the one apply pass, while the T3 sequence diagram applies them in a second binder call. Say which, and what rollback covers. Also say whether a standalone `ApplyMods` applies `onModsStaged` edits, and whether a later `Start` with unchanged mods calls `onModsStaged` again. Otherwise those edits can be lost.
- **S3. A Guard prompt can hold a host slot.** During an instance install or update with a remembered password, the prompt wait (up to 5 min) happens inside `ctx.heavy`, so it holds the account lock and one of the 4 host slots. That is bounded, but the D2 "Timing" bullet should say it.
- **S4. Two components claim to publish content.** `architecture.md` line 155 names the Steam service as the content-store publisher, while D6 and the State table name the mod pipeline. Update the baseline row together with the rows the proposal adds.
- **S5. New methods and host-wide operations need an access entry and a queue subject.** `security/method_access.dart` needs an entry for `Operations/WatchPrompts`, or the gate refuses it. `CheckModUpdates` with an empty `instance_id` is a host-wide operation, and D1's subject keys (`account:<id>`, instance id) give it no queue subject. Name one.
- **S6. `interrupted` is not a documented prompt outcome.** The Failure table uses `PromptResolved(outcome: interrupted)`, while `operations.proto:89-93` documents `answered | expired | cancelled`. After a restart there is no stream left to carry that event anyway. Drop it, or add the value to the proto comment.
- **S7. Very short secrets over-mask.** Whole-word masking of 1-3 character secrets (D11) masks every standalone occurrence, such as a numeric port value. Consider a minimum length, or refusing secrets under 4 characters, at `SetSecret`.
- **S8. A duplicate account has no defined outcome.** `AddAccount` for a username already added has no reason or scenario. Specify one (for example `ALREADY_EXISTS` `account_exists`).

#### Round 1 Required Changes (history, all applied)

1. **M1.** In design D12, and where needed D7, state the frame of reference for mod links, bindings, data paths, log sources and launch args (the instance root versus the server working directory `<instance>/server`). Rewrite the DayZ args (`-config`, `-BEpath`, `-profiles`, `-mod`/`-serverMod`), bindings, `data_paths` and log sources so they agree. Make the mod-management scenario "DayZ mod linked" name the matching link path.
2. **M2.** In D6, state that the mod pipeline (not an operation) owns each acquisition run, including its installation lock, heavy slot, cancel token and progress fan-out to waiters. State that the run is cancelled only when its last waiter detaches, and that an operation waiting on another operation's keys holds no lock or slot. Correct the Flow & State Gaps bullet on fixed-order lock acquisition to match.
3. **M3.** In D10, add three rules:
   - An operation that starts while the instance's recorded plugin version differs from the loaded manifest waits for, or fails behind, the pending migration (or the migration is placed at the queue head).
   - A full queue has a defined outcome.
   - A successful settings save on a `settings_invalid` instance records the loaded plugin version.
   Also note that the `pluginVersion` write in `reconcilePlugins` (`instance_manager.dart:1312-1320`) moves into the migration.
4. **M4.** In D4, describe the channel in both modes: the console-mode stdin line, the stdin pipe from launcher to relay through `CreateProcessAsUserW`/`spawnProcess`, and the relay reading the secrets before it writes `relay.json` and spawns the server. Correct the "it already writes" claim.
5. **M5.** Extend assumption A1 (and its spike task) to scan SteamCMD's own files under the account installation for the password after a login run, and to record the behaviour of an expired cached login with stdin closed. In D3, state the fallback if those files carry the password.
6. **M6.** In D7 (and D5), state when workshop metadata is read for a newly added mod, whether `SetMods` waits for it, when the staged name is fixed, and the fallback name (`@<id>`) when metadata is unavailable.
7. **M7.** In D7, replace "remove whatever entry exists at its staged name" with a rule that never deletes an entry Yagura did not create. Either de-duplicate against existing entries when the name is fixed, or fail with a named reason when the entry is not a recorded junction or recorded copy. Add a mod-management scenario for it, and say how copies are recorded.
8. **M8.** In D1, the account state diagram and the Failure table, add startup recovery for accounts left in `adding`: delete the row, its `steam:<id>` secret and its installation (no-follow). Add a steam-content scenario for a daemon restart during `AddAccount`.
9. **M9.** In the daemon-protocol delta, modify "Methods a daemon version does not implement" so its example service is one this version still does not build. Add a requirement for `Operations.WatchPrompts` (snapshot, raised/resolved events, subscriber bound, resync) and the `RespondToPrompt` refusals, with at least one failure scenario.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **R2-M1.** Bring ADR 0004's "Bindings apply before `onPreStart`" into line with the amended specs. Record a superseding ADR or an amendment note stating that bindings and hook edits apply in one pass after the hooks return, bindings first, so hooks read bound files as they were before this start's bindings. Update the design's "ADRs: To record during apply" to name it.
2. **R2-M2.** Give `ApplyConfig` an owner. Either park its requirement in `platform-backlog` (the config-bindings delta, with a task group under a named milestone), or state in the proposal that it is dropped from the roadmap and why.

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

## Rebuttals

<!-- Author: fixed (cite) or rebutted (reason) per finding. A Critical/Moderate rebuttal counts only once marked "accepted by reviewer". -->

### Round 2

- **R2-M1 fixed.** `docs/adr/0004-config-bindings-with-round-trip-parsers.md` gains "Amendment (2026-10-20, m3-steam-accounts-and-mods)": one binder pass per operation after its hooks return, bindings first, then hook edits in order (start: `onModsStaged`, `onPreStart`; update: `onModsStaged`, `onPostUpdate`), one rollback; hooks read bound files as they were before that operation's bindings. design "ADRs: To record during apply" names it.
- **R2-M2 fixed.** `ApplyConfig` is parked in M4: `openspec/roadmap.md` "Next: M4" now lists "`ApplyConfig` (a bindings-only pass on a stopped instance, left out of M3)", and `proposal.md` says it moves to M4 with the complex-config work. Not written into `platform-backlog`, which holds uncommitted edits of the user's.
- **R2-S1 fixed.** instance-lifecycle "Updates stop and restart a running server": "run the plugin's `onPostUpdate` hook, then apply the bindings and its file edits in one pass, bindings first (step `apply_config`)".
- **R2-S2 fixed.** Task 11.2 now reads "and still not `Rcon` or `Instances.ApplyConfig` (M4)".

#### Reviewer re-check (round 2)

I re-checked only the edits listed above (`git diff` of ADR 0004, `openspec/roadmap.md`, and the change's `design.md`, `proposal.md`, `specs/instance-lifecycle/spec.md` and `tasks.md`) and looked for contradictions they introduce.

- **R2-M1: applied.** ADR 0004 now has an "Amendment (2026-10-20, m3-steam-accounts-and-mods)" section, which states:
  - one binder pass per operation, made after the hooks return;
  - bindings first, then hook edits in order (start: `onModsStaged`, then `onPreStart`; update: `onModsStaged`, then `onPostUpdate`);
  - one rollback over the pass;
  - hooks read bound files as they were before that operation's bindings.

  This matches D9 "Binder", the amended config-bindings requirement, the plugin-hooks scenario "Mods-staged hook edits a config" and `docs/plugins/hooks.md:86`. The original Decision sentence ("Bindings apply before `onPreStart`") stays in the ADR, but the amendment opens with "Bindings no longer apply before `onPreStart`", so a reader cannot take the old sentence as current. D9's `ApplyMods` pass (bindings and `onModsStaged` edits) is not listed in the amendment's examples, but it follows the same "each operation makes one pass" rule, so the two do not conflict. The design's "ADRs: To record during apply" now names the amendment.
- **R2-M2: applied.** `ApplyConfig` now has an owner. The M4 paragraph of `openspec/roadmap.md` lists "`ApplyConfig` (a bindings-only pass on a stopped instance, left out of M3)", and the proposal says it "stays unimplemented in M3 and moves to M4 with the complex-config work". Neither the proto (`instances.proto:33`, no comment) nor `docs/protocol.md` defines its behaviour, so the "stopped instance" scope contradicts nothing. Non-blocking note: the same M4 paragraph says its change is "taken from `platform-backlog` groups 18-19", and those groups hold no `ApplyConfig` requirement. When the M4 change is created, it has to add the requirement from the roadmap line, not from the backlog. The author's reason for not editing `platform-backlog` (it holds the user's uncommitted edits) is acceptable.
- **R2-S1: applied.** The instance-lifecycle update requirement now says "run the plugin's `onPostUpdate` hook, then apply the bindings and its file edits in one pass, bindings first (step `apply_config`)". This matches D9, the ADR amendment and `lifecycle.dart:309-311`. The scenario step list (`stop`, `snapshot`, `download`, `update_mods`, `apply_config`, `start`) is unchanged and still holds. The requirement does not name the `onModsStaged` edits that D9 includes in the update pass, but it does not exclude them, and D7 step 5 covers them.
- **R2-S2: applied.** Task 11.2 now says "still not `Rcon` or `Instances.ApplyConfig` (M4)", which matches the proposal and the roadmap.

**Outstanding:** none. Both round-2 Required Changes are applied and re-checked, and the edits introduce no new contradiction. Changes applied: yes.

### Round 1 (history)

- **M1 fixed.** design D7 "Frame of reference" (manifest paths relative to the instance root, launch args relative to `<instance>/server`, links staged in `mods.stage_dir`, default `server`). D12 "Frame", "Bindings", "Mods", "Launch" and "Other" rewritten to `server/yagura/...`, `stage_dir: server`, `server/keys/`, `data_paths: [server/mpmissions/, server/profiles/]`, log sources `server/profiles/...`. D8 rule `to: server/keys/`. Spec mod-management "DayZ mod linked" now names `<instance>/server/@Community-Framework`, and the key scenarios use `server/keys/`.
- **M2 fixed.** design D6 "Runs belong to the pipeline", "Locks and slots", "Cancel": the pipeline owns each run with its installation lock, heavy slot, cancel token and progress fan-out; waiting operations hold no lock or slot; a run is cancelled only when no key has a waiter. The Flow & State Gaps bullet "Two instances need the same item version" is corrected, and the State, Resource Bounds and T3 diagram rows match.
- **M3 fixed.** design D10: the migration goes to the queue head, outside the 10 bound (full queue defined), a repeat reload retargets it; the `pluginVersion` write at `instance_manager.dart:1312-1320` moves into the migration; "Gate" (operations after a failed migration fail `invalid_state`, stop and delete exempt); "Recovery" (a valid save records the loaded version). The Failure table row is updated.
- **M4 fixed.** design D4: "Daemon to launcher" (the line written in both modes, the claim it already exists corrected, `launch_input_missing`), "Launcher to relay" (an anonymous pipe through `STARTF_USESTDHANDLES` in `CreateProcessAsUserW` and `spawnProcess`), "Relay" (the line is read before `writeRelay` and the spawn), "Tests" (console in CI, service in the elevated workflow).
- **M5 fixed.** design A1 now covers scanning the installation's files after a login and the expired-cache behaviour with stdin closed. D3 "SteamCMD's own files" gives the fallback (post-run and startup scrub, delete if a file cannot be scrubbed; `config.vdf` stays ADR 0014's exception). D2 adds the password-request pattern to `reauth_needed`.
- **M6 fixed.** design D7 "Names": `SetMods` never waits, a background fetch fixes the name once (title, or `@<item id>` on failure or a private or missing item), an apply waits for a fetch still running (bounded by 15 s), a restart refetches unnamed mods. D5 points at it. Spec mod-management "Title unavailable when added".
- **M7 fixed.** design D7 step 3 and step 4: only recorded entries are removed (a `link` row's link whatever its target, or a `copy` row's directory with the `.yagura-staged` marker); anything else fails `stage_name_conflict` and is left. Names are de-duplicated against existing entries when fixed. `stage_kind` column added. Spec mod-management requirement text and the scenario "Admin folder with the staged name".
- **M8 fixed.** design D1 "Rows while adding" and "Startup recovery"; T2 account diagram edge "startup recovery"; Failure table row "Account add". Spec steam-content "Daemon restarted while adding".
- **M9 fixed.** Spec daemon-protocol: ADDED "Pending prompts reach every client" (snapshot then raised/resolved, `prompt_resolved`, `prompt_answer_invalid`, 32 subscribers `too_many_subscribers`); MODIFIED "Methods a daemon version does not implement" now uses `Rcon.Execute`. design D13 cites the requirement.
- **S1 fixed.** Spec instance-lifecycle "One operation per instance at a time" now counts heavy steps, start's mod downloads included, with `waiting_for_steamcmd`; scenario "Heavy limit counts mod downloads".
- **S2 fixed.** design D9 "Binder": one pass per operation (Start, ApplyMods, Update), its order and rollback scope; D7 step 5 runs `onModsStaged` on every stage step; T3 diagram updated.
- **S3 fixed.** design D2 "Timing" says a prompt inside a run holds its lock and slot for at most 5 minutes, and that account operations take no heavy slot.
- **S4 accepted.** The architecture write-back (content-store publisher is the mod pipeline) is a task in the integration group.
- **S5 fixed.** design D13 adds the `method_access.dart` entry; D14 gives `CheckModUpdates` the queue subject `host` (or the instance's queue).
- **S6 fixed.** The Failure table no longer uses an `interrupted` prompt outcome; the dialog closes on the operation ending and on the next `WatchPrompts` snapshot.
- **S7 rebutted.** Refusing short secrets at `SetSecret` would change M2's shipped `SetSecret` behaviour for existing plugins. Whole-word matching already limits over-masking to standalone tokens equal to the secret, and over-masking a log line is the safe failure.
- **S8 fixed.** Spec steam-content "Account already added" (`ALREADY_EXISTS` `account_exists`); design D1 counts `adding` rows.
- **Route note.** The `select` output picked codex. This host's codex route cannot read files (repository memory), so the review ran on the `subagent` route and was recorded without `--selection`.

#### Reviewer re-check

- **M1: applied.** D7 "Frame of reference" and D12 "Frame", "Bindings", "Mods", "Launch" and "Other" now agree. `server/yagura/serverDZ.cfg` matches `-config=yagura/serverDZ.cfg` under `<instance>/server`, `-profiles=profiles` matches the log sources `server/profiles/*` and `data_paths` `server/profiles/`, and `server/mpmissions/` is in `data_paths`. The mod-management scenario "DayZ mod linked" names `<instance>/server/@Community-Framework`, and the key scenarios use `server/keys/`.
- **M2: applied, but the fix introduced a contradiction with D2.** D6 "Runs belong to the pipeline", "Locks and slots" and "Cancel", and the Flow & State Gaps bullet, are correct and consistent. D2 was not brought in line:
  - D2 "Code kinds" attaches a prompt to "the operation" and moves "the operation" to `waiting_for_input`, and `RespondToPrompt` is keyed by `operation_id`.
  - D2 "Timing" and "Instance operations" say a prompt can be raised inside a mod download run (remembered password, expired cached login).
  - D6 says that run belongs to the pipeline, with no operation and possibly several waiting operations.
  - D2 says "A cancel resolves the prompt with outcome `cancelled`", while D6 says a cancelled waiter only detaches and the run goes on for the other waiters.

  The result is that a Guard prompt inside a shared workshop run has no defined operation to show on or be answered through. One waiter's cancel would either kill a login the other waiters still need, or leave a prompt pending on an operation that has ended. **Remaining edit:** in D2 (or D6), state how a prompt raised inside a pipeline-owned run is surfaced. For example: it is raised on every waiting operation with one prompt id (each moves to `waiting_for_input`), `RespondToPrompt` with any of those operation ids resolves it, a waiter's cancel only detaches it, and the prompt resolves `cancelled` only when the run itself is cancelled. Also replace the operation id in the publish staging path (D5 `content/.staging/<op-id>/`, T2 "acquisition owner starts (.staging/<op>)") with a run id, since a run has no operation.
- **M3: applied.** D10 now covers all of it: the migration goes to the queue head, outside the 10 bound; a repeat reload retargets it; the `pluginVersion` write moves into the migration; "Gate" handles a failed migration and "Recovery" covers the valid save. These agree with the plugin-manifest delta (a running instance's next start is refused, and a stopped one fails until fixed) and with the instance-lifecycle "Queue full" scenario, which covers client requests only.
- **M4: applied.** D4 "Daemon to launcher" sends `LaunchInput` in both modes and fails with `launch_input_missing`. "Launcher to relay" adds the anonymous pipe with `STARTF_USESTDHANDLES` in both `CreateProcessAsUserW` and `spawnProcess`. "Relay" reads the line before `writeRelay` and the spawn. "Tests" names console mode in CI and service mode in the elevated workflow. The "already writes" claim is corrected.
- **M5: applied.** A1 now covers the installation file scan and the expired-cache behaviour with stdin on NUL. D3 "SteamCMD's own files" gives the post-run and startup scrub, with deletion as the last resort, and D2 adds the password-request match to `reauth_needed`. tasks.md does not exist yet, so task 1.1 has to carry these A1 items when it is written.
- **M6: applied, with one contradiction in the spec wording.** D7 "Names" and D5 "Metadata" now say that `SetMods` never waits, a background fetch fixes the name, the fallback is `@<item id>`, an apply waits for a fetch still running, and startup refetches unnamed mods. The spec scenario "Title unavailable when added" is present. The mod-management requirement still says the name is "fixed when the mod is added". That reads close enough to D7 not to block, but it should say "fixed once, when its metadata is first read or found unavailable".
- **M7: applied, but the edited requirement text contradicts an existing scenario.** D7 steps 3 and 4, `stage_kind`, the `.yagura-staged` marker, de-duplication against existing entries and the "Admin folder with the staged name" scenario are all present and coherent. The new requirement sentence "Staging SHALL never remove an entry Yagura did not create" conflicts with the scenario "Staged link replaced by the server" in the same requirement, and with D7 step 3 ("a link the server replaced is removed too"). There, staging removes a junction that `yagura-srv` created. Removing it loses no data, but the spec now asserts two incompatible things. **Remaining edit:** reword the requirement sentence, for example: "Staging SHALL never remove an entry Yagura did not create, except a link found at a path where Yagura recorded a link, which it removes without following."
- **M8: applied.** D1 covers "Rows while adding" and "Startup recovery" (row, `steam:<id>` secret, no-follow installation delete, run after the interrupted-operation pass). The T2 edge, the Failure table row "Account add", the Flow & State Gaps bullet and the steam-content scenario "Daemon restarted while adding" are present and consistent.
- **M9: applied.** The delta modifies "Methods a daemon version does not implement" to use `Rcon.Execute`, which replaces the main-spec `Mods.ListMods` example. The ADDED "Pending prompts reach every client" requirement has the snapshot, raised and resolved scenario, plus three refusal scenarios: `prompt_resolved`, `prompt_answer_invalid` and `too_many_subscribers`. D13 cites it. Resync is in D13 and not in a scenario, which is acceptable.
- **S7 rebuttal: accepted.** It is a Suggestion. Over-masking is the safe failure, and refusing short secrets at `SetSecret` would change shipped behaviour.
- **Follow-up pass (M2, M7 and the M6 wording): applied, no new contradiction.**
  - *M2.* D2 "Prompts in pipeline runs" covers the shared run: one prompt id is attached to every waiting operation and published once on `WatchPrompts`, `RespondToPrompt` accepts it with any of those operation ids (compare-and-set), a cancelled waiter only detaches, and the prompt resolves `cancelled` only when the run is cancelled. This agrees with D6 "Cancel" (a run is cancelled only when no key has a waiter) and with the WatchPrompts requirement (first valid answer wins, later ones get `prompt_resolved`). D5 now uses `content/.staging/<run-id>/<item>/`, the T2 edge "acquisition run starts (.staging/<run-id>)" matches, and D6 "Collection" still cleans `content/.staging/*`.
  - *M7.* The requirement now says "never remove an entry Yagura did not create, except a link where Yagura recorded one, removed without following". That matches D7 step 3 (a `link` row's link is removed whatever its target), the scenario "Staged link replaced by the server", and the scenario "Admin folder with the staged name".
  - *M6 wording.* The name is "fixed once when metadata is first read or found unavailable", which matches D7 "Names" and the scenario "Title unavailable when added".
  - *Link failure.* The requirement no longer says the step fails when linking fails and `copy_fallback` is false, but the scenario "Link not permitted" (`stage_link_failed`) still states that, so no behaviour is lost.
  - *Wording nit, non-blocking.* The WatchPrompts requirement says each snapshot entry comes "with its operation", in the singular, while a pipeline-run prompt is attached to several operations. Saying "with its operations" in the requirement, or in the proto comment, would remove the ambiguity. The behaviour itself is defined by D2.
- **Third pass (edits made after changes applied: yes): consistent, verdict kept.**
  - *plugin-hooks.* The scenario "Reading a staged mod" now reads `server/@CF/meta.cpp` with `server/@CF` as the recorded link, and "Edit into a staged mod refused" uses `server/@CF/config.cpp`. Both follow D7 "Frame of reference" (hook and manifest paths relative to the instance root, links staged in `mods.stage_dir`, default `server`) and M1/D12 (`stage_dir: server`). Both also follow D7 "The ADR 0015 exception": a read through a recorded link continues read-only in the content-store version directory, and writes below a recorded path are refused with `sandbox_violation`. "Staged mods in the context" still lists the staged name `@CF`, not a path, which matches D7 "Template".
  - *daemon-protocol.* "with its operations and their instance or account" closes the nit above, and matches D2 "Prompts in pipeline runs" (one prompt attached to every waiting operation).

**Outstanding before changes applied: yes:** none. All nine Required Changes are applied and re-checked, the M2 and M7 follow-ups hold, and the two later edits (plugin-hooks paths, WatchPrompts wording) are consistent with D2, D7 and M1. changes applied: yes.

#### Author response to the re-check

- **M2 follow-up fixed.** design D2 "Prompts in pipeline runs": one prompt id attached to every waiting operation and published once on `WatchPrompts`; `RespondToPrompt` accepts it with any of those operation ids; a cancelled waiter only detaches; the prompt resolves `cancelled` only when the run is cancelled. Staging path is now `content/.staging/<run-id>/` in D5 and the T2 diagram.
- **M7 follow-up fixed.** Spec mod-management "Staging by link with copy fallback": "Staging SHALL never remove an entry Yagura did not create, except a link where Yagura recorded one, removed without following."
- **M6 recommendation applied.** The same requirement now says the name is "fixed once when metadata is first read or found unavailable". The link-failure rule is now "A failed link is copied when `copy_fallback` is true", and the "Link not permitted" scenario keeps the failure case, so the description stays under 500 characters.
- **M5 note.** Task 1.1 in `tasks.md` will carry the extended A1 checks.
