# Review

## Metadata

- **Round:** 3
- **Prior round:** Round 2 (whole platform, M1-M5) ended APPROVE_WITH_CHANGES with 1 Critical (SYSTEM `app_update` writing through junctions planted by another instance), 8 Moderate and 8 Suggestions. A re-check confirmed all 10 Required Changes and marked the changes applied. The change has since been cut down to M1, with M2-M5 moved to `platform-backlog`, so that verdict no longer applies. The R2-C1 fix now sits in backlog D13 and the ADR 0014 note.
- **Reviewer:** fresh-context subagent (Claude Code, `specwright-reviewer` role). Project skills loaded and applied: `dart-setup-ffi-assets`, `dart-use-ffigen`, `dart-build-cli-app`, `flutter-apply-architecture-best-practices`.
- **Reviewed:**
  - The change: `openspec/changes/init-core-platform/proposal.md`, `design.md`, `tasks.md`, and all 9 `specs/*/spec.md`.
  - Prior round: the round-2 `review.md`.
  - Split check (spot-check, not a full review): `openspec/changes/platform-backlog/proposal.md`, `design.md`, `specs/*/spec.md`, and the `tasks.md` group list.
  - Baseline: `openspec/roadmap.md`. I read ADR 0007, 0009, 0011 and 0013 in full; for the other ADRs and `openspec/architecture.md` I only grepped for console mode, dev mode, secrets and Valheim. I also read `docs/protocol.md` (reason codes), `docs/overview.md` (Valheim manifest), and the `proto/yagura/v1/*.proto` service lists.
  - Checks:
    - `openspec validate init-core-platform --strict` passes.
    - All 134 scenarios in the 9 specs have a test-map row; I checked this by script.
    - The spikes come first: 1.2 runs before group 2 and 1.3 before group 5.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

The split is mostly clean:
- The backlog keeps D8, D13, D16, D19 and D20, the InstanceFs and process-verification requirements, roots, the secret store, `onModsStaged`/`migrateSettings`, masking, revisions and the service-identity spike 11.3.
- Its MODIFIED requirements are M1's text plus the later additions, with nothing dropped.
- The "M1 scope" lines on D2, D3, D7, D10 and D21 hold.

The findings below are places where the M1 change still depends on behaviour only the backlog provides, or where it cannot meet its own exit criteria as written.

### Critical (blocking)

None.

### Moderate

**R3-M1. The Valheim manifest sends its log to a file, but the health check and log scenarios expect it on stdout.**
- *Location:*
  - `tasks.md` 9.1 (`-savedir`/`-logFile` inside the instance, "log-match health").
  - `docs/overview.md` line 85 (`-logFile {{instance}}/logs/server.log`).
  - `specs/plugin-manifest/spec.md` scenario "Log-match health check" (health `log_match: "Game server connected"` on source `stdout`).
  - `specs/log-streaming/spec.md` scenario "Stdout survives daemon restart" ("a Valheim server keeps writing to stdout").
  - `openspec/roadmap.md` M1 exit criterion "reaches `running` via its log-match health check, and its log streams to the desktop client".
- *Problem:* With `-logFile <path>`, a Unity dedicated server writes its log to that file, not to stdout. A Valheim manifest built as 9.1 describes, with its health check on `stdout` as the scenario does, never matches "Game server connected". After `start_timeout` (300 s) the instance moves to `running` with `health: unknown` (instance-lifecycle "Health check never passes"), so the M1 exit criterion fails. Task 9.1 does not name the log source the manifest must declare or which source the health check reads.
- *Fix:* Required Change 1.

**R3-M2. `secret` settings are in M1, but M1 has nowhere ADR 0011 allows to store them.**
- *Location:*
  - `specs/plugin-manifest/spec.md` "Settings schema types and constraints" (type `secret`; scenario "Secret values are write-only").
  - `specs/instance-lifecycle/spec.md` scenario "Secrets excluded from instance.json" (RCON password and GSLT set).
  - `specs/plugin-hooks/spec.md` scenario "Context contents" (RCON password set).
  - `tasks.md` 3.2 and 4.3 ("secret placeholders").
  - `design.md` D9 ("The secret store ... join[s] the fatal steps ... in M2").
  - ADR 0011 (secrets only through `SecretStore`, as DPAPI blobs).
  - Backlog `daemon-security` "Secrets never leave the daemon" ("stored only through the OS-backed secret store").
- *Problem:* M1 accepts, validates and masks secret values, but no M1 requirement, decision or task says where they are stored or how they are set. `SetSecret` is in the proto, but no M1 spec mentions it. In practice the only place left is the SQLite settings row in plaintext, which contradicts in-force ADR 0011. The backlog has no task to move M1-era plaintext values into the store and scrub them. Its "Data directory scan" scenario would then fail on any database carried over from M1.
- *Fix:* Required Change 2. Refuse secret values in M1, so nothing exists to migrate. Do not store them in plaintext.

**R3-M3. Two M1 scenarios depend on backlog-only hooks and mods, so their tests cannot be written as specified.**
- *Location:*
  - `specs/plugin-hooks/spec.md` scenario "Thrown error" (uses `onModsStaged`, which is not in M1's "Hook points" list; the backlog adds it through MODIFIED).
  - Scenario "Edit into a staged mod refused" (a staged mod link resolving into the content store, which is M3).
  - The "Hook input and output contract" text ("staged mods") and the "Sandboxed host API" text ("including staged mod folders").
  - `tasks.md` test-map rows 11 and 26, both in group 2 (M1).
- *Problem:*
  - The M1 hook runner never calls `onModsStaged` and has no result schema for it. Its test would have to call an unsupported hook point, or it ends up testing `onPreStart` under a scenario that names a different hook.
  - The staged-mod scenario needs a content store and mod staging, which do not exist until M3.
  - The general risk the staged-mod scenario covers (a hook edit escaping through a link) is real in M1 and worth keeping, but in an M1 form.
  - When the backlog's M3 change is taken out, it will not restore the staged-mod wording, because its plugin-hooks delta modifies only "Hook points".
- *Fix:* Required Change 3.

**R3-M4. The manifest accepts features M1 cannot run, and their M1 behaviour is not defined.**
- *Location:*
  - `specs/plugin-manifest/spec.md` "Stop and health declarations" (stop strategy `rcon`; health `port` and `query` via Steam A2S).
  - `specs/steam-content/spec.md` "Login mode per plugin" (`account`, `account_optional`; the only scenario is anonymous).
  - `tasks.md`:
    - 3.2: reserved sections for bindings, mods and rcon are "validated in their own groups", and those groups are in the backlog.
    - 5.3: "`rcon` comes with RCON in M4".
    - No task implements runtime health checks at all: neither 4.3, 5.2, 5.3 nor 7.2 mentions evaluating `process`, `port`, `log_match` or `query`.
- *Problem:* Under M1, any of these plugins loads as `loaded` and then fails in ways the specs do not define:
  - A plugin with `stop.strategy: rcon` (any DayZ-style manifest an admin drops in) has no defined Stop path.
  - An `account`-login plugin's Install has no defined failure.
  - `health: query` has no implementation, so the instance waits the full 300 s and reports `health: unknown`.
  - Unvalidated `bindings`/`mods`/`rcon` sections pass `yagura plugin lint` in M1 and only fail at M3/M4.

  Separately, no task builds the start-time health evaluator, including `log_match` on the log hub, which the Valheim exit criterion needs.
- *Fix:* Required Change 4.

**R3-M5. Some test-map rows sit at a boundary that cannot observe their THEN, and one needs real Valheim on CI.**
- *Location:* `tasks.md` test map:
  - **Daemon behaviour mapped to the manifest package.** The THENs below describe running daemon behaviour, but their rows point at `packages/yagura_plugin/test/...`, which cannot observe it:
    - plugin-manifest "Log-match health check": "becomes `running` when that line appears".
    - "Long-running executable tracked": recorded PID alive, exit detected.
    - "Bootstrapper exits": start fails `launch_failed`.
    - "Fixed manifest picked up": "the next `Start` uses the new argument".
    - "Broken edit keeps the old version": "existing DayZ instances keep starting".
  - **Client behaviour mapped to a daemon test.** The daemon-protocol "API version negotiation" rows ("client shows the daemon as connected / `incompatible`", "client manages it over API 1.9") point at `apps/yagurad/test/api/...`. No M1 task builds client-side negotiation (9.3 does not mention `GetInfo` or `incompatible`).
  - **A real-game row in the CI gate.** instance-lifecycle "Valheim saves on a signal stop" sits in group 9 at `apps/yagurad/test/instances/...`, while the roadmap requires "Every test-map row ... green on Windows CI".
- *Problem:*
  - Tests written at the mapped boundary either cannot assert the THEN or quietly test something smaller, and the rows still go green.
  - The client behaviour in the negotiation scenarios is never built.
  - The Valheim row needs the real `valheim_server.exe`, an anonymous SteamCMD download of about 1 GB, on every CI run, or it gets faked with `fake_server` and stops proving that Valheim saves. In both cases the exit criterion "every row green on Windows CI" is either flaky or hollow.
- *Fix:* Required Change 5.

### Suggestions

**R3-S1. The exit criterion and the spec disagree on the hook timeout.**
- *Location:* the roadmap says "interrupted within 6 s"; `specs/plugin-hooks/spec.md` "Infinite loop interrupted" says "within 7 s".
- *Problem:* A test written to the spec does not prove the exit criterion.
- *Fix:* Assert the 6 s exit bound in the test as well, or align the roadmap to 7 s. Required Change 6.

**R3-S2. The desktop client's reconnect after a daemon restart is not specified.**
- *Location:* the exit criterion says "the client shows it `running` again". D10's M1 scope covers one connection, but neither the desktop spec nor 9.3 says the client reconnects and re-subscribes to `WatchInstances`.
- *Problem:* Without that, the user-verified criterion depends on restarting the client.
- *Fix:* Required Change 6.

**R3-S3. Spike 1.3 does not cover the conditions M1 actually runs in.**
- *Location:* tasks 1.3.
- *Problem:*
  - The process tests run on the Windows CI runner. `CREATE_BREAKAWAY_FROM_JOB` fails with access denied when the parent's job does not allow breakaway, which CI runners and some terminals can cause.
  - The `signal` helper is spawned by a daemon that owns a console (`run --console`). `AttachConsole` fails while the helper still shares the daemon's console, so the helper must be created detached or call `FreeConsole` first.
- *Fix:* Run the spike's parent from a console window, and also once on the CI runner. Record the outcome of both in `docs/spikes/m1-process-model.md`.

**R3-S4. Dev mode leaves its defaults and edge cases unstated.**
- *Location:* `specs/daemon-security/spec.md`.
- *Problem:* The spec does not say:
  - what the default bind is when `--dev` is given without `--bind`;
  - what `yagurad run --console` without `--dev` does in M1 (no TLS exists yet);
  - whether `[::1]` and `localhost` count as loopback.
- *Fix:* State these. Recommended: default `127.0.0.1:7443`; without `--dev` M1 exits non-zero, rather than opening a listener with no authentication.

**R3-S5. Some M1 steps and settings are named but not defined.**
- *Location and problem:*
  - **`apply_config` step:** `specs/instance-lifecycle/spec.md` "Update while running" and tasks 6.3 ("apply config") name this step, but bindings are M3. M1 does not say what the step does.
  - **Snapshots root:** D12's "configurable per host" has no M1 mechanism.
  - **D6:** the title says "without following links", but the body never defines it.
- *Fix:* Add M1 scope lines. For example, `apply_config` runs `onPostUpdate` only, and the snapshots root is fixed at `<data>/snapshots` in M1.

**R3-S6. A failed stray-SteamCMD sweep still lets runs start (re-raising R2-S4).**
- *Location:* D9 (sweep failure is a degraded step); steam-content "Stray SteamCMD after a crash" covers only success.
- *Problem:* M1 has one anonymous installation. If a stray SteamCMD survives the sweep, the next run breaks D7's rule of one process per installation.
- *Fix:* Mark that installation unavailable until a sweep succeeds.

**R3-S7. Unbuilt RPCs in M1 services have no defined response.**
- *Location:* task 8.2.
- *Problem:* 8.2 serves the full `Instances` service. That service includes `SetSecret`, `DeleteSecret`, `ImportInstance`, `ExportInstance` and `ApplyConfig`, which M1 does not build. Their response is not specified.
- *Fix:* Return `UNIMPLEMENTED` with a reason documented in `docs/protocol.md`, so the 8.3 reason-code test covers it.

**R3-S8. Later-milestone wording remains in M1 specs, and these texts become the main specs on archive.**
- *Location:*
  - Purpose texts of `daemon-security` (paired devices, mTLS), `host-service` ("starts at boot"), `steam-content` (workshop, accounts, Steam Guard) and `desktop-client` ("several daemons", prompts, consoles).
  - "mods" in the "Durable state" requirement.
  - "mod update counts" in "Instance state and event stream".
  - "including any pending prompt" in "Missed events no longer retained".
  - `content/` in "Default layout created".
- *Fix:* Trim these to M1 wording, so `openspec/specs/` records only built behaviour, as the roadmap intends.

**R3-S9. The restart counter has no row in State & Ownership.**
- *Location:* design State & Ownership.
- *Problem:* The crash-loop restart counter and window (owner, memory or SQLite, reset on Acknowledge/Start) are missing. Whether the counter survives a daemon restart decides whether the crash-loop guard holds across restarts.
- *Fix:* Add the row.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **R3-M1.**
   - In `tasks.md` 9.1, replace "log-match health" with "a log source `server` for `logs/server.log` (`utf-8`, rotation `fixed`), and health `log_match: \"Game server connected\"` on source `server`".
   - In `specs/plugin-manifest/spec.md` scenario "Log-match health check", replace "on source `stdout`" with "on its declared log source".
   - In `specs/log-streaming/spec.md` scenario "Stdout survives daemon restart", replace "a Valheim server keeps writing to stdout" with "a server whose log source is `stdout` keeps writing to it".
2. **R3-M2.**
   - In `design.md` D9 (or a new M1 scope note under Context), add: "M1 has no secret store: setting a value for a `secret` setting, through settings or `SetSecret`, fails `FAILED_PRECONDITION` with reason `secret_store_unavailable`, and no secret value is persisted anywhere; secret settings stay unset until M2."
   - In `specs/plugin-manifest/spec.md`, replace scenario "Secret values are write-only" with:
     - **WHEN** a client submits a value for a `secret` setting
     - **THEN** the call fails with `FAILED_PRECONDITION` reason `secret_store_unavailable`, nothing is saved, and reading the settings returns the field as `{"secret": true, "set": false}`
   - In `specs/instance-lifecycle/spec.md` scenario "Secrets excluded from instance.json", change the WHEN to "an instance's plugin declares a `secret` setting `rconPassword`" and the THEN to "`instance.json` contains `\"rconPassword\": {\"secret\": true}` and no other value for it".
   - In `specs/plugin-hooks/spec.md` scenario "Context contents", replace "with an RCON password set" with "whose plugin declares a `secret` setting `rconPassword`".
   - In task 9.1, state how the Valheim manifest handles the server password in M1 without a `secret` value.
3. **R3-M3.**
   - In `specs/plugin-hooks/spec.md` scenario "Thrown error", replace `onModsStaged` with `onPreStart`.
   - Replace scenario "Edit into a staged mod refused" with "Edit through a link refused":
     - **WHEN** a hook returns a file edit for `cfg/server.json` where `cfg` is a junction to a directory outside the instance root
     - **THEN** the operation fails with `sandbox_violation` naming the path, and no file outside the instance root changes
   - Update test-map row 26 to match.
   - Remove "staged mods" from the "Hook input and output contract" text and "including staged mod folders" from the "Sandboxed host API" text.
   - In `openspec/changes/platform-backlog/specs/plugin-hooks/spec.md`, add MODIFIED copies of "Hook input and output contract" and "Sandboxed host API" that restore the staged-mod wording and the original "Edit into a staged mod refused" scenario.
4. **R3-M4.**
   - In `specs/plugin-manifest/spec.md` "Stop and health declarations", append: "A plugin that declares stop strategy `rcon`, health `query`, or a `bindings`, `mods` or `rcon` section is `rejected` at load with reason `unsupported_in_this_version` until the milestone that builds it." Add a scenario:
     - **WHEN** a manifest declares `stop: {strategy: rcon}`
     - **THEN** the plugin is `rejected` with `unsupported_in_this_version` naming `stop.strategy`
   - In `specs/steam-content/spec.md` "Login mode per plugin", add a scenario:
     - **WHEN** an instance of a plugin with `login: account` is installed
     - **THEN** the operation fails with `FAILED_PRECONDITION` reason `steam_account_required` before SteamCMD runs
   - State that `account_optional` installs anonymously.
   - Add `unsupported_in_this_version` to `docs/protocol.md`.
   - In `tasks.md` 3.2, replace "validated in their own groups" with "rejected with `unsupported_in_this_version` in M1".
   - In 5.3, add "health checks `process`, `port` and `log_match` (on the log hub) with `start_timeout` and `health: unknown`".
5. **R3-M5.**
   - In the `tasks.md` test map, move these rows to `apps/yagurad/test/...` in the group that builds the behaviour:
     - group 5: "Log-match health check", "Long-running executable tracked" and "Bootstrapper exits";
     - group 4: "Fixed manifest picked up" and "Broken edit keeps the old version".
   - Move the three "API version negotiation" rows to `apps/yagura_desktop/test/api_version_negotiation_test.dart` (group 9). Add to 9.3: "`System.GetInfo` on connect, choose the highest shared major, show `incompatible` and stop calling when none is shared".
   - Tag "Valheim saves on a signal stop" `valheim` and run it in 9.6 on a Windows machine with Valheim installed.
   - Change the roadmap M1 criterion to "Every test-map row of `init-core-platform` except those tagged `valheim` is green on Windows CI (agent)".
6. **R3-S1, R3-S2.**
   - In `specs/plugin-hooks/spec.md` "Infinite loop interrupted", replace "within 7 s" with "within 6 s". The interrupt fires at the 5 s deadline; the 7 s watchdog covers native hangs only.
   - Add to task 9.3: "reconnect with backoff after the connection drops and re-subscribe to `WatchInstances`".

CHANGES_APPLIED: no

## Rebuttals

<!-- Author: fixed (cite) or rebutted (reason) per finding. A Critical/Moderate rebuttal counts only once marked "accepted by reviewer". -->

The user treated round 3 as REVISE, taking this review together with the OMP review in `review-round3-omp.md` (R3-C1/C2, R3-M1..M10 and R3-S1..S4 there are marked "OMP" below). Every finding of both was fixed; none is rebutted. Round 4 reviews the result.

| Finding | Response |
|---|---|
| R3-M1 (Valheim log vs health) / OMP M2 | Fixed. Task 9.1 declares log source `server` (`logs/server.log`) with `log_match` on it; "Log-match health check" uses the declared source and matches only lines of the current run; "Stdout survives daemon restart" no longer names Valheim; the `log_match` evaluator is task 7.3 and the `process`/`port` evaluator with `start_timeout`, exit and cancellation is in 5.3. |
| R3-M2 (secrets) / OMP C2 | Fixed. New requirement "Secret settings stay unset without a secret store" (`secret_store_unavailable` for create, settings update, `SetSecret`, `DeleteSecret`; secret defaults rejected at load); "Context contents" and "Secrets excluded from instance.json" use declared, unset secrets; D24; task 4.3; Valheim runs with `-public 0` and no password (9.1, checked by spike 1.3, risk listed). Backlog: MODIFIED settings schema with "Secret values are write-only" and REMOVED for the M1 requirement. |
| R3-M3 (M3 references in hooks) / OMP M1 | Fixed. "Thrown error" uses `onPreStart`; "Edit through a link refused" replaces the staged-mod scenario; "staged mods" removed from the contract and host API. Backlog: MODIFIED "Hook input and output contract" and "Sandboxed host API" restore the M3 wording and scenarios. |
| R3-M4 (manifest features M1 cannot run) / OMP M1 | Fixed. "Stop and health declarations" rejects `rcon` stop, `query` health and `bindings`/`mods`/`rcon` sections with `unsupported_in_this_version` (scenario "Unsupported stop strategy"); `account` installs fail `steam_account_required` and `account_optional` installs anonymously ("Account login not available"); task 3.2; reasons added to `docs/protocol.md`; templates over `mods` replaced by a `string_list` setting (backlog restores `mods`). |
| R3-M5 (test boundaries) / OMP M4 | Fixed. Runtime manifest rows moved to daemon tests (groups 4, 5, 7); negotiation rows moved to `apps/yagura_desktop` (group 9) with client negotiation in 9.3; the Valheim row is tagged `valheim` and runs in 9.7; the roadmap criterion excludes `valheim` rows from CI and requires them on a Valheim machine; Linux CI runs tests not tagged `windows`/`valheim` (9.5); the MSVC fallback needs the user to amend the criterion (1.2, Risks, roadmap). "Valheim save directory" and "Long-running executable tracked" reworded to what their tests observe. |
| R3-S1 / OMP M4 (6 s vs 7 s) | Fixed. "Infinite loop interrupted" asserts 6 s. |
| R3-S2 / OMP M5 (reconnect, client actions) | Fixed. New requirements "Connection to one daemon" (negotiation, backoff reconnect, fresh snapshot) and "Instance actions" (create, install, start, stop, delete); task 9.3. Backlog: REMOVED "Connection to one daemon" in favour of "Multiple paired daemons", which now keeps negotiation and resync. |
| R3-S3 / OMP M6 (signal console, breakaway) | Fixed. D2 "Signal helper and jobs": helper spawned `DETACHED_PROCESS`, ignore handler after attaching, Win32 errors returned; refused breakaway fails `launch_failed`, never dropped. Spike 1.3 runs from a console parent and once on the CI runner. |
| R3-S4 (dev mode defaults) | Fixed. Default `127.0.0.1:7443`, `::1` and all-loopback `localhost` accepted, no `--dev` exits `secure_mode_unavailable`; scenarios "Dev mode default bind" and "Started without dev mode"; backlog MODIFIED drops the M1-only refusal. |
| R3-S5 / OMP S3 (`apply_config`, snapshots root, D6) | Fixed. `apply_config` runs `onPostUpdate` and applies its edits (spec, 6.3); snapshots root fixed at `<data>/snapshots` (D12 M1 scope); D6 retitled and the M1 path rule is the new D22; D21 M1 scope states the allowed `instances/` subtree. |
| R3-S6 / OMP M7 (failed SteamCMD sweep) | Fixed. Installation unavailable with `steamcmd_unavailable` until a sweep retried every 60 s succeeds (spec, D9, 6.2, Failure & Visibility); scenario "Stray SteamCMD cannot be terminated". |
| R3-S7 / OMP M3 (unbuilt RPCs) | Fixed. Requirement "Methods a daemon version does not implement" (`UNIMPLEMENTED` / `not_implemented`), D24 method table, `revision` 0 with `expected_revision` unchecked, `GetHealth.not_built` (proto field 10), "Methods by daemon version" in `docs/protocol.md`; 8.3 checks emitted reasons one way and the method table against the server. |
| R3-S8 / OMP S3 (later wording in M1 specs) | Fixed. Purposes of daemon-security, host-service, steam-content and desktop-client trimmed; "mods" removed from durable state, mod update counts and pending prompts from daemon-protocol, `content/` from the layout (backlog MODIFIED requirements restore them); T1 is now an M1 process view. |
| R3-S9 / OMP S1 (restart counter, last requested state) | Fixed. State & Ownership rows for the restart counter (crash timestamps in SQLite) and the last requested state; D14 and the autostart requirement define clearing (scenario "Cancelled update not autostarted"). |
| OMP C1 (hook file edits need the binder) | Fixed. D23 and task 2.3: lossless JSON tree in `yagura_formats` and a file-edit writer (resolved path, atomic, all or nothing) before the group-2 green gate; other formats fail `unsupported_in_this_version` (scenario "Edit in an unsupported format"); the "no external edit" clause moved to the backlog with hash tracking; backlog 15.3 reuses the writer. |
| OMP M8 (hook worker bound) | Fixed. A timed-out worker keeps its slot until its isolate exits, so at most 4 isolates exist (D4, Resource Bounds, spec; scenario "Timed-out worker keeps its slot"). |
| OMP M9 (log line, paused client) | Fixed. Lines cut at 64 KiB with `truncated: true` ("Line without a newline"); follow lag bound 1,000 lines or 4 MiB; desktop pause holds 10,000 lines ("Pause longer than the buffer"); backlog "Logs and console views" keeps the pause bound. |
| OMP M10 (launch commit boundary) | Fixed. D2 "Launch records": `pending` run record and run directory before `launch`, relay identity written before the server starts, startup resolution; requirement text and scenario "Daemon killed during a start"; task 5.2. The relay dying in the moment between starting the server and recording it is listed as a residual risk. |
| OMP S2 (AOT bundle smoke) | Fixed. Task 9.4 and a roadmap M1 criterion. |
| OMP S4 (mixed backlog blocks) | Fixed. Backlog design "Extraction notes" lists each mixed MODIFIED requirement with its clauses by milestone and the rule for taking them out. |
