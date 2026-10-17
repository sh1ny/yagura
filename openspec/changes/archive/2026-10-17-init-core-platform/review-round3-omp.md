# Review

## Metadata

- **Round:** 3
- **Prior round:** Round 2 reviewed M1–M5 and ended APPROVE_WITH_CHANGES, with changes subsequently marked applied, according to the review request. That verdict is void after the M1 split. The current `review.md` already contains a different round-3 review rather than the original round-2 document; its findings were checked against the artifacts, not treated as proof.
- **Reviewer:** OMP 18.10.4 (`gpt-6.1-sol`, high) through the specwright-review omp route. The script rejected the run as `output too large` (sh1ny/specwright#95); this text is the final assistant message recovered from the OMP session file. Kept as evidence: the user chose to treat round 3 as REVISE.
- **Reviewed:**
  - `openspec/changes/init-core-platform/{proposal,design,tasks,review}.md` and all nine capability specifications.
  - `openspec/changes/platform-backlog/{proposal,design,tasks}.md` and its capability specifications, for split consistency rather than full backlog approval.
  - `openspec/{strategy,architecture,roadmap}.md`, ADRs 0001–0013, `docs/{protocol,overview}.md`, and all `proto/yagura/v1/*.proto`.
  - The four requested project skills covering native assets, FFI generation, CLI applications and Flutter architecture.
  - Static review only. The supplied strict-validation pass was not rerun. No repository files were created or edited.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Critical (blocking)

**R3-C1 — M1 hook file edits still require the deferred config binder and parsers.**

- **Location:** `specs/plugin-hooks/spec.md`, “Sandboxed host API”, especially “File edit returned and applied by the daemon”; `design.md`, start-operation sequence; task 2.3; backlog task 15.3; ADRs 0003 and 0004.
- **Problem:** M1 requires a JSON patch to be applied atomically, preserve other keys and their order, and establish file-hash state so the next start reports no external edit. The baseline assigns these responsibilities to the config binder. That binder, the lossless JSON parser and hash tracking are implemented only by backlog task 15.3. Task 2.3 explicitly leaves format APIs as “stubs … as formats land”, yet requires this scenario to be green before group 2 finishes. Neither the diagram’s “apply … edits” box nor an empty `yagura_formats` package supplies the implementation.
- **Concrete fix:** Bring the minimum hook-edit implementation into M1: the JSON parser/patcher needed by the existing scenario, atomic replacement, file-hash ownership and the associated error paths. Assign these to explicit tasks before group 2’s green gate. State which format APIs M1 actually exposes; unsupported formats must fail explicitly, not remain stubs. Keep declarative bindings and the additional formats in the backlog, updating task 15.3 to reuse rather than reimplement the M1 edit writer. Define `apply_config` in the M1 update sequence in terms of this implemented subset and `onPostUpdate`, not deferred bindings.

**R3-C2 — M1 promises populated secret settings without an allowed storage mechanism.**

- **Location:** `specs/plugin-manifest/spec.md`, “Secret values are write-only”; `specs/plugin-hooks/spec.md`, “Context contents”; `specs/instance-lifecycle/spec.md`, “Secrets excluded from instance.json”; `design.md` D9; tasks 3.2, 4.3 and 9.1; ADR 0011.
- **Problem:** These M1 scenarios require instances with stored RCON passwords or GSLTs, but D9 and backlog task 10.3 defer the secret store to M2. ADR 0011 requires secret references backed by `SecretStore`, not plaintext settings rows. Masking responses and `instance.json` does not resolve persistence. The reference Valheim task also leaves its password handling unspecified.
- **Concrete fix:** Preserve the stated M1 boundary by refusing secret values with `FAILED_PRECONDITION` / `secret_store_unavailable`, before persistence, through `SetSecret`, settings submissions and schema defaults. Keep declared secret fields unset and return placeholders with `set: false`. Rewrite the three scenarios to exercise unset declarations and rejected writes; move populated-secret expectations into the backlog. Task 9.1 and spike 1.3 must specify and prove a Valheim development launch that does not require persisted credentials. Do not disguise its password as an ordinary string setting.

### Moderate

**R3-M1 — Several remaining M1 contracts still require mods, unsupported hooks or other deferred runtime capabilities.**

- **Location:**
  - `specs/plugin-hooks/spec.md`: `onModsStaged` in “Thrown error”, staged mods in the context and host API, and “Edit into a staged mod refused”.
  - `specs/plugin-manifest/spec.md`: `mods` template scope, the DayZ mod-list launch scenario, and `rcon`/A2S `query` declarations.
  - `specs/steam-content/spec.md`: `account` and `account_optional`.
  - Task 3.2: reserved sections “validated in their own groups”.
- **Problem:** M1 has no mod list, staging, content-store acquisitions, RCON adapter, account management or `onModsStaged` lifecycle point. Their successful behavior cannot be exercised end to end in M1. Accepted manifests also lack a defined failure for unsupported features.
- **Concrete fix:** Use `onPreStart` for the thrown-error scenario; replace the staged-mod escape fixture with an ordinary junction escaping the instance root. Exercise conditional/list-join templates using an M1 `string_list` setting rather than managed mods. Reject deferred manifest sections and unsupported runtime declarations with a documented `unsupported_in_this_version` problem naming the field. Define `account` installation as failing `steam_account_required` before spawning SteamCMD, and `account_optional` as anonymous in M1. Update the test map accordingly. Add backlog MODIFIED requirements that restore the removed vocabulary and scenarios when their implementations arrive.

**R3-M2 — The Valheim readiness path is not specified consistently or assigned an implementation task.**

- **Location:** `specs/plugin-manifest/spec.md`, “Log-match health check”; task 9.1; tasks 5.2–5.3 and 7.2; `docs/overview.md`, Valheim description; roadmap M1 readiness criterion.
- **Problem:** The scenario watches `stdout`, while the reference plugin is instructed to use `-logFile` inside the instance. Task 9.1 names neither the declared file source nor the source consumed by health evaluation. More generally, no task explicitly implements the start-time `process`, `port` or `log_match` evaluator, its timeout, or cancellation.
- **Concrete fix:** Specify a named file source for `logs/server.log` and point Valheim’s `log_match` health check at that source. Make the manifest scenario refer to its declared source rather than `stdout`; keep stdout-capture coverage on the fake server. Add an explicit health-evaluator task, including `start_timeout`, `health: unknown`, process exit, cancellation and log-hub integration. Define readiness as consuming current-run output, not a matching line left in an old log.

**R3-M3 — The M1 protocol boundary still imports later-milestone behavior.**

- **Location:** Task 8.2’s service list; task 8.3; `design.md`, boundary diagram using `expected_revision`; `docs/protocol.md`; `proto/yagura/v1/{system,instances,operations}.proto`.
- **Problem:** “Implement … `System`, `Instances`, `Operations`” includes `ListAudit`, secret mutation, import/export, `ApplyConfig` and prompt responses, although those features are deferred. Revision enforcement is likewise described by the wire baseline but implemented only in backlog group 13. Task 8.3 requires every documented reason code to occur in the M1 daemon, including pairing, firewall, RCON, workshop and systemd reasons.
- **Concrete fix:** Add a method-level M1 support table. Define unsupported methods as returning `UNIMPLEMENTED` with a documented stable reason, except the explicit secret-store rejection from R3-C2. State M1’s treatment of `expected_revision` and deferred response fields without implying concurrency control is implemented. Scope task 8.3 to M1-supported reason codes; retain the one-way check that every emitted code is documented. Define how health responses represent components that are not built, rather than reporting them healthy.

**R3-M4 — The test map’s presence does not establish observable scenario coverage, and several exit gates conflict.**

- **Location:** `tasks.md`, test map and tasks 1.2, 3.1, 9.4; `openspec/roadmap.md`, M1 exit criteria; `specs/plugin-hooks/spec.md`, “Infinite loop interrupted”.
- **Problem:**
  - Plugin-package tests are assigned daemon outcomes: actual readiness, PID lifetime, bootstrapper failure, and subsequent launches after plugin reload.
  - API negotiation scenarios assert desktop connection state but map to daemon tests.
  - The real-Valheim save scenario is included in the unconditional Windows-CI green gate without a real-game provisioning/tagging contract.
  - Task 9.4 requires all tests on Linux, although the native process implementation is explicitly deferred to M5.
  - The hook scenario allows 7 seconds; the roadmap requires 6.
  - The MSVC exit criterion has no acceptance rule for task 1.2’s clang-cl fallback.
- **Concrete fix:** Move runtime plugin scenarios to daemon/process tests and negotiation scenarios to desktop tests; leave pure validation/rendering tests in `yagura_plugin`. Define OS tags and CI selection explicitly. Mark the real-Valheim row as requiring the designated Windows qualification host, and state that separately in the roadmap’s CI criterion without replacing it with fake-server proof. Align the hook bound to 6 seconds. State that compiler fallback does not satisfy the MSVC criterion unless that criterion is explicitly amended.

**R3-M5 — The desktop implementation task omits actions and reconnection required by the M1 exit.**

- **Location:** `specs/desktop-client/spec.md`; `design.md` D10; task 9.3; roadmap M1 client-driven stop and daemon-restart criteria.
- **Problem:** Task 9.3 lists an instance list, form, progress view and log view, but not the create/install/start/stop actions needed to operate the skeleton. It also omits version negotiation, reconnect and stream re-subscription. Those behaviors are not supplied by the M1 desktop requirements; reconnect currently appears in the multi-daemon backlog requirement.
- **Concrete fix:** Add the single-daemon connection lifecycle and required controls to the M1 desktop specification and task 9.3: negotiate through `GetInfo`, create/install/start/stop through the API, watch returned operations, reconnect with bounded backoff, obtain a fresh instance snapshot and resume applicable streams. Add observable desktop scenarios for incompatible versions and recovery after daemon restart. Keep pairing and multi-daemon ownership deferred.

**R3-M6 — The signal-helper console state is missing from the supposedly complete Windows process sequence.**

- **Location:** `design.md` D2; tasks 1.3 and 5.2; ADR 0009.
- **Problem:** The helper is told to call `AttachConsole`, but its own console ownership is unspecified. M1’s parent runs with a console. [INFERENCE] If the helper inherits that console, attachment to the server console fails unless it detaches first. The design also applies breakaway flags without defining behavior when an enclosing job forbids breakaway.
- **Concrete fix:** Specify that `signal` is created without an attached console or explicitly calls `FreeConsole` before attaching, installs its ignore handler after attachment, checks Win32 errors and returns failure when signaling fails. Run spike 1.3 from the actual console-mode parent and exercise the native process fixture on the Windows CI runner, including its job constraints. Record the supported spawn policy; do not silently drop the survival guarantee when breakaway is denied.

**R3-M7 — A degraded stray-SteamCMD sweep can violate the one-process-per-installation invariant.**

- **Location:** `design.md` D9 and Failure & Visibility; D7; `specs/steam-content/spec.md`, “SteamCMD runs are bounded and cleaned up”; task 6.2.
- **Problem:** D9 permits the listener to open after sweep failure and says failed components retry on their own schedules. The Steam spec requires stale processes to be terminated before operations are accepted. Nothing prevents a new anonymous run while an old process remains alive.
- **Concrete fix:** Keep the listener available for diagnosis, but mark the affected SteamCMD installation unavailable until its sweep succeeds. Refuse dependent operations without spawning another process, expose the degradation through health/notices, and add a failed-sweep scenario followed by successful recovery. Specify the retry owner and schedule.

**R3-M8 — The hook-worker bound is contradicted by watchdog slot release.**

- **Location:** `design.md` D4, Failure & Visibility and Resource Bounds; task 2.3; `specs/plugin-hooks/spec.md`, “Hook host calls are bounded”.
- **Problem:** A watchdog releases the slot immediately, but a non-exiting isolate is counted as leaked only five seconds later. New native workers may start during that gap. [INFERENCE] Four simultaneous native hangs can therefore coexist with replacements before degradation is recorded. The table’s “2 leaked workers max” is not an enforced bound.
- **Concrete fix:** Count timed-out, non-exited workers against the live-worker budget immediately. Keep their capacity reserved until exit; refuse new hooks once two workers are quarantined. Distinguish active, quarantined and confirmed-leaked counts, and state the actual maximum live-worker bound. Add a simultaneous-timeout scenario proving replacements cannot exceed it.

**R3-M9 — Log bounds do not cover an oversized line or a paused client.**

- **Location:** `specs/log-streaming/spec.md`, capture rotation, bounded buffers and message limits; `specs/desktop-client/spec.md`, “Follow and pause”; design Resource Bounds; tasks 7.2 and 9.3.
- **Problem:** Limits are expressed in completed lines or completed ring-buffer entries. There is no bound for an unterminated line. The specifications simultaneously require no line splitting, bounded capture files and bounded response messages. Pausing the desktop must later display accumulated lines, but its pending storage and overflow behavior are unspecified.
- **Concrete fix:** Define a byte limit for incremental line assembly and an explicit oversized-line policy, with a visible truncation/drop indication. Apply byte bounds to subscriber queues as well as line counts. Define a bounded desktop paused buffer and its overflow marker. Add scenarios for a newline-free stream exceeding the limit and a pause exceeding client capacity.

**R3-M10 — Launch recovery has no defined commit boundary between starting a surviving process and recording it.**

- **Location:** `design.md` D2, State & Ownership and “Daemon restart mid-operation”; task 5.2; ADR 0009.
- **Problem:** The relay record’s authority is the launcher report, while the game can run independently under the relay. The documents do not define recovery if the daemon dies after process creation but before that report is durably recorded. Existing coverage starts from an already-recorded running server. [INFERENCE] A restart can leave an untracked server or initiate another run without reconciling the first.
- **Concrete fix:** Define a durable pending-run record and a launch handshake that prevents the server from running before the supervisor has committed the relay identity. Specify timeout/recovery for an unacknowledged relay and distinguish successive runs’ files. Add crash-point coverage around relay creation, record commit and server spawn, asserting that recovery never creates a second live server for the instance.

### Suggestions

**R3-S1 — Complete the state ownership contract for restart intent and crash-loop accounting.**

- **Location:** `design.md` D14, D18 and State & Ownership.
- **Problem:** The restart counter/window has no ownership or persistence row. “Cleared on Stop” does not distinguish an explicit user Stop from the internal stop during Update/Restart, nor explain cancellation after that internal stop.
- **Concrete fix:** Record the counter’s owner, persistence/reset rules and behavior across daemon restart. Define durable requested state for explicit Stop, internal stops and cancelled operations, so a later restart does not unexpectedly undo a completed cancellation.

**R3-S2 — Add an AOT/native-asset smoke gate, not just package tests.**

- **Location:** Tasks 1.2, 5.2 and 9.4–9.6; D1–D2.
- **Problem:** The design specifies an AOT daemon whose executable re-enters helper modes, but no task explicitly builds and launches the distributable bundle with its native code assets.
- **Concrete fix:** Add a Windows bundle smoke that launches the compiled daemon outside the source working directory, evaluates a hook and exercises launch/relay/signal against the fake server. Verify helper resolution and native-library loading from the bundle.

**R3-S3 — Finish the M1 scope annotations rather than leaving target-platform text authoritative by implication.**

- **Location:** D6, D12, D15 and D21; the T1 diagram; Purpose sections for security, host service, Steam and desktop.
- **Problem:** D6 promises not to follow links without defining the M1 mechanism; D12 offers a configurable snapshot root without a configuration task; D15 still names mod updates. D21’s overlap wording also needs to exempt the intended instance subtree beneath the data directory. Several Purpose sections describe unbuilt service/security/account features.
- **Concrete fix:** Define M1 path handling explicitly without requiring the deferred InstanceFs component; fix the snapshot root at `<data>/snapshots` unless an M1 configuration mechanism is assigned. Clarify allowed versus forbidden data-directory subtrees. Trim M1 requirements and purposes, and provide an M1 process view or visibly mark deferred diagram nodes and edges.

**R3-S4 — The backlog preserves the major mechanisms, but is not yet a milestone-safe extraction source.**

- **Location:** Backlog `specs/instance-lifecycle/spec.md`, “Graceful stop per plugin strategy”; backlog `specs/desktop-client/spec.md`, “Forms rendered from plugin schemas”; backlog task groups 11, 13, 18 and 19.
- **Problem:** The graceful-stop MODIFIED block combines M2 service identity with M4 RCON. The forms block combines M2 revision conflicts with M4 table editing. Copying either whole block into the earlier milestone records later unbuilt behavior—the same problem this split is intended to prevent.
- **Concrete fix:** Identify per-milestone replacement text and scenario ownership for these mixed blocks before extraction. The major deferred mechanisms—InstanceFs, account isolation, PKI, audit, mods, bindings and RCON—are present; that spot-check does not establish that whole MODIFIED blocks can be applied unchanged at their earliest milestone.

## Verdict

VERDICT: REVISE

## Required Changes

Not applicable to this verdict. Each blocking and moderate finding above includes its location and concrete correction. The M1 change is not yet self-contained: mandatory hook-edit and secret-setting behavior still depends on deferred implementations, and several verification gates do not prove their stated outcomes.

CHANGES_APPLIED: n/a

## Rebuttals

None. Read-only review; no fixes were applied or marked verified.