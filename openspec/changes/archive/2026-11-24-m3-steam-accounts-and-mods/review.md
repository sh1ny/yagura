# Review

## Metadata

- **Round:** 5
- **Prior round:** 4 (re-check of the round-3 Required Changes; approve with changes, R4-M1 outstanding)
- **Re-check:** re-check of the round-4 Required Change R4-M1 and of the round-4 Suggestions the author applied (R4-S1, R4-S2). It covers those edits only, and checks whether they introduce new contradictions. The edits are:
  - the `login` outcome order and header comment in `steam/patterns.yaml`, with `patterns.g.dart` regenerated;
  - the precedence rule in D2 "Choice";
  - a new test group in `steam_patterns_test.dart`;
  - the silent-run bound restarted by every new `console_log.txt` line, in D2 "Silent run", the Failure row, the Resource Bounds row and the spec scenario "SteamCMD does not respond";
  - the sequence-diagram label;
  - spike finding 3's credit to D15.
- **Reviewer:** fresh-context subagent (specwright-reviewer, Claude Code)
- **Reviewed:**
  - `apps/yagurad/lib/src/steam/patterns.yaml` (the `login` group and its header comment);
  - `apps/yagurad/test/steam/steam_patterns_test.dart:77-155`;
  - `design.md`: A1, D2 "Choice" and "Silent run", the AddAccount sequence diagram, the Failure table and the Resource Bounds table;
  - `specs/steam-content/spec.md`, the scenario "SteamCMD does not respond";
  - `docs/spikes/m3-steam-guard.md`: "Output that tells the kinds apart" and findings 1, 3 and 4;
  - `openspec validate m3-steam-accounts-and-mods --strict`, which reports the change valid.

  I could not run `dart test test/steam` here: `dart` is not on this shell's PATH. The author reports +63, all passing. I checked the new test group by reading it against the table. Skills loaded: none (none named).

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

### Round 5 (re-check of the round-4 Required Change)

**R4-M1: applied.**
- In `login.outcomes` in `patterns.yaml`, `reauth_needed`, `rate_limited`, `guard_invalid` and `login_invalid` come first, then `ok`, then `guard_email`, `guard_authenticator` and `guard_mobile`.
- The header comment states the rule: outcomes are tried in table order, and the first that any line matches wins. Failures come first, so a later `...OK` does not hide one. `ok` comes before the guard kinds, so a code or approval that came through in the same run counts as a login.
- D2 "Choice" states the same rule in the same order, and adds that an `ok` line after a `guard_*` line means the run logged in. D2 "Mobile approval" ("the run ends with the `ok` pattern on stdout") now agrees with the table.
- The new test group "login outcomes classify the spike transcripts" reads the embedded table and applies the rule as written: list order first, then any line. It covers six transcripts:
  - an approved mobile login gives `ok`;
  - an accepted email code gives `ok`;
  - a mobile approval never given gives `guard_mobile`;
  - an email code asked gives `guard_email`;
  - a cached login gives `ok`;
  - a missing cached login gives `reauth_needed`.

  The group also checks `live.guard_mobile` against a timestamped `connection_log.txt` line. The transcripts use the spike document's stdout lines.
- Moving `ok` ahead of the guards does not let a failed guard run pass as `ok`. The `ok` pattern requires `...to Steam Public...OK` on one line. The spike's email-code-asked output ends with `Steam Guard code:ERROR (Account Logon Denied)`, and the test confirms it still gives `guard_email`.
- A rejected code or password still wins over `ok`, because the failure kinds come first.
- The never-approved mobile case is a classification only. In the step, that run is killed at the prompt expiry (`steam_guard_timeout`), and D2 still says so.

**R4-S1: applied.** D2 "Silent run" now counts the 60 s from the run's start and restarts it on every new `console_log.txt` line, so a self-update inside the run keeps it alive. The Resource Bounds row ("60 s without exit, prompt or a new `console_log.txt` line"), the Failure row and the spec scenario "SteamCMD does not respond" ("neither ends, asks for a code or an approval, nor writes to its SteamCMD log for 60 seconds") agree with it.

A run that keeps writing to the log but never logs in stays bounded by the login step's 10-minute cap (architecture Resource Bounds). D2 "Timing" already places all login waits inside that cap. Once the mobile prompt is raised, its own 2-minute expiry governs.

One wording difference does not matter: the spec says "its SteamCMD log" and the design names `console_log.txt`. The spec scenario stays at the behaviour level, and the design binds it.

**R4-S2: applied.** The AddAccount sequence diagram now says `guard_authenticator (run exited)`, which matches D2 "Choice" (classification at exit) and "Silent run". Spike finding 3 now says "Design D15 (with D5 "Progress") is added".

**New contradictions:** none found. The A1 sentence "the daemon kills it as soon as a prompt or password-request pattern matches" remains, but the Spike result in the same bullet still says it cannot apply, as accepted in round 4.

#### Critical (blocking)

None.

#### Moderate

None.

#### Suggestions

None.

### Round 4 (re-check of the round-3 Required Changes)

**R3-M1: applied.**
- The author ran a real anonymous install (app 896660, 2,112,080,121 bytes, exit 0, 65.3 s). Spike finding 3 and the two new Results rows record it: stdout delivered every progress line at the exit, while `logs/console_log.txt` had each one live, one every 2 s.
- A1 now says the held-back stdout applies to login and download runs alike, so the general statement is backed by evidence instead of narrowed.
- D15 "Context" names the consequence for the stall timer (`steamcmd_service.dart:424-462` reads stdout only) as an M2 defect fixed here. D15 "Uses" moves progress and the 15-minute stall timer to `console_log.txt` for every run. D5 "Progress" and the Resource Bounds workshop-run row ("15 min without progress in `console_log.txt` (D15)") agree.
- The MODIFIED requirement "SteamCMD runs are bounded and cleaned up" keeps the main spec's three scenarios unchanged ("Stalled download", "Stray SteamCMD after a crash", "Stray SteamCMD cannot be terminated"). It adds the sentence on reading progress from the log, and the scenario "Long download that keeps progressing", whose THEN can be asserted against the fake.
- Task 5.5 cites `stalled_download`, `total_time_cap`, `cancel_terminates_steamcmd` and the existing install rows. All of them exist in `steamcmd_runs_are_bounded_and_cleaned_up_test.dart:58-149`.
- This agrees with ADR 0014's "15 minutes without download progress", and the outcome is still classified from stdout at exit. The rejected alternatives (a pseudo-console, watching directory size) have stated reasons.

**R3-M2: applied.** D15 bounds the follower:
- 64 KiB per poll;
- lines cut at 4 KiB, with the rest dropped up to the next LF, so the partial line carried between polls is at most 4 KiB;
- the last 5 scrubbed lines kept for failure messages.

The new Resource Bounds row repeats those numbers. D15 "Start" reads the size and file id (volume serial and file index) before the process starts. A size below the offset, or a changed file id, restarts at offset 0. A missing file is "no signal yet". The follower opens the file no-follow through the installation's `ConfinedFs` with full sharing. The new Failure row covers a missing, rotated, truncated or unreadable log, and ends each case with a named error. The design does not depend on the follower ever catching up, because the stall timer and the silent-run bound end the run regardless.

**R3-M3: applied in the design, but the new `login` table misclassifies an approved mobile login (R4-M1).**
- `patterns.yaml` version 3 has `login.live.guard_mobile: 'Waiting for confirmation'`, with `connection_log: 'logs/connection_log.txt'`, and D2 "Mobile approval" cites it.
- D2 "Silent run" kills a login run that has neither exited nor raised a prompt within 60 s, with `steam_login_unresponsive` and the last scrubbed `console_log.txt` lines. The Failure row, the Resource Bounds row, the spec scenario "SteamCMD does not respond", the test-map row `steamcmd_does_not_respond` and task 5.3 agree with it.
- The old D2 sentence "killed when still alive after a `guard_*` pattern matched" is gone. The A1 sentence remains, but the Spike result in the same bullet says explicitly that it "cannot apply", which is enough.

**R3-S1: applied.** Task 1.2 now has the fake reproduce:
- stdout held back until exit (banner lines aside);
- live `console_log.txt` and `connection_log.txt`;
- a log rotated or truncated at start;
- a silent run.

**R3-S2: applied.** D15 "Lines": log lines are scrubbed, matched and dropped, never stored or logged, apart from the 5-line failure tail.

#### Critical (blocking)

None.

#### Moderate

**R4-M1. The `login` outcome order classifies a successful mobile-approval run as `guard_mobile`.**
The new `login.outcomes` comment in `patterns.yaml` says "the first outcome any line matches wins". `guard_mobile` (`Please confirm the login in the Steam Mobile app`) comes before `ok` in the list.

The spike's approved mobile run printed both lines on stdout ("Mobile approval" under "Output that tells the kinds apart"):
- `Please confirm the login in the Steam Mobile app on your phone.`
- `Waiting for confirmation...`
- `Logging in user '<user>' ... to Steam Public...OK`

Because the whole stdout arrives at exit and is classified then (D2 "Choice"), a mobile login that the admin approved matches `guard_mobile` before `ok`. Reading the rule by line order instead of list order gives the same result, because the `guard_mobile` line comes first. D2 "Mobile approval" expects the step to see "the run end with the `ok` pattern on stdout". Implemented as written, the table would turn every approved phone login into a guard result, and the step would then either raise a second prompt (the Pending prompts bug guard fails the operation) or fail the login. Exit criterion 3 needs an account login, and the spike's mobile account offers phone approval only, so this path is the one the milestone run takes.

The same ordering issue does not affect the email code retry. Its stdout (`Steam Guard code provided.`, then `...OK`) matches neither `guard_email` alternative.

Fix:
- State the precedence in D2 "Choice". The guard kinds describe a run that did not log in, so either `ok` wins over every `guard_*` kind, or a `guard_*` kind counts only when no `ok` line follows it. The failure kinds (`reauth_needed`, `rate_limited`, `guard_invalid`, `login_invalid`) can keep their "an earlier failure is not hidden" rule.
- Order or annotate `patterns.yaml` to match, and regenerate `patterns.g.dart`.
- Add a `steam_patterns_test.dart` case with the spike's approved-mobile transcript, which classifies as `ok`.

#### Suggestions

- **R4-S1. The 60 s silent-run bound does not count SteamCMD's self-update.** Spike finding 4 shows that SteamCMD schedules an "immediate update check" after an unclean shutdown, which is what follows a silent-run or expiry kill. The bootstrap self-update took 10-12 s on the spike machine. When Valve ships a SteamCMD build, the first login run in each account installation downloads it inside the run. On a slow link that can take longer than 60 s, and the run is then killed as `steam_login_unresponsive` while it is visibly working: its update progress is in `console_log.txt`, which D15 already follows. Consider counting new `console_log.txt` lines as liveness, or starting the 60 s at the first `steam_login` step line (`Logging in user`) seen in `console_log.txt`.
- **R4-S2. Stale wording.**
  - The AddAccount sequence diagram still says `guard_authenticator (killed if still alive)`. Under D2 "Silent run", a run waiting on stdin is killed by the 60 s bound, not by a pattern match.
  - Spike finding 3 says "Design D2 and D5 are amended". The stall-timer change is in D15.

#### Round 4 Required Changes (history, applied and re-checked in round 5)

1. **R4-M1.** In D2 "Choice", state the precedence between `ok` and the `guard_*` kinds for a run classified at exit: a run whose stdout has the `ok` line after a `guard_*` line logged in. Make `apps/yagurad/lib/src/steam/patterns.yaml` (`login.outcomes`, order and comment) follow that rule, and regenerate `patterns.g.dart`. Add a `steam_patterns_test.dart` case for the spike's approved-mobile stdout (`Please confirm the login in the Steam Mobile app on your phone.`, `Waiting for confirmation...`, `Logging in user '<user>' ... to Steam Public...OK`) that expects `ok`.

### Round 3 (amendment re-check)

**What holds.**
- The 15-minute code wait is the same everywhere it appears:
  - D2 "Code kinds" (`expires_at = now + 15 min`);
  - D2 "Timing" (a prompt inside an instance run holds a heavy slot for at most 15 minutes);
  - the AddAccount sequence diagram ("raise prompt (15 min)");
  - the Resource Bounds "Pending prompts" row ("15 min codes, 2 min mobile");
  - the steam-content requirement and its "No code submitted in time" scenario;
  - task 5.3.

  A grep of the change finds no 5-minute prompt bound left. The daemon-protocol and desktop-client deltas carry the expiry as data and name no duration, so they need no edit.
- The spike supports the 15 minutes: the first email arrived more than 10 minutes after the attempt, and a code from an earlier email still completed a later login. The code wait sits between runs, outside the login step's 10-minute cap (architecture Resource Bounds, "login step 10 min"), and D2 "Timing" says so. ADR 0014 fixes no duration for the code wait and leaves the timeouts to the spike, so the change does not contradict it.
- The 2-minute mobile bound matches ADR 0014 ("waits for SteamCMD to report approval within 2 minutes"), the spec scenario "Mobile approval not given" and the spike, where approvals came 16-21 s after the start.
- The stdout finding does not affect the code kinds. Email and expired-cache runs exit at once (exit 5 within 1-5 s, spike Results), so classifying stdout after exit works for them.
- D2 "Prompts in pipeline runs" and D6 still hold. The log follow is part of the login step, so a mobile prompt inside a pipeline-owned run uses the same single prompt id and waiter rules.
- Reading the log is confined as described:
  - `ConfinedFs` opens each path component relative to its parent's handle, with `FILE_OPEN_REPARSE_POINT` (`confined_fs_windows.dart:35-40`). A link that `yagura-steam` plants as `logs` or as `connection_log.txt` is therefore not followed; ADR 0014 line 17 says `yagura-steam` can plant such links.
  - The open uses share mode 7 (`confined_fs_windows.dart:737`), so the daemon's polling never blocks SteamCMD from writing, renaming or deleting the file.
  - `readAt(offset, count)` (`confined_fs.dart:52-53`) gives a bounded read at an offset.
  - Passing each line through the run's Scrubber matches D3 and ADR 0014, and the spike found no password or code in any SteamCMD file in 10 runs.

#### Critical (blocking)

None.

#### Moderate

**R3-M1. The amendment says SteamCMD's stdout reaches the pipe only at exit, for every run, but the existing stall timer depends on the opposite.**
The amended text makes a general claim:
- A1: "SteamCMD writes its console output to a pipe only when it exits";
- D2 "Mobile approval": "SteamCMD writes its stdout to a pipe only at exit".

The spike observed this only for login runs, whose whole output is a few hundred bytes (`docs/spikes/m3-steam-guard.md`, finding 1). It did not run workshop downloads ("Not covered").

The 15-minute no-progress timer reads only stdout lines. `lastProgressAt` moves when a progress line arrives, and the watchdog kills the run with `steam_stalled` (`steamcmd_service.dart:424-462`). The design relies on that timer for long runs:
- the Resource Bounds row "SteamCMD workshop run": "120 mods in one run; progress is per item, so the stall timer stays valid";
- D2 "Timing": prompt waits "never meet the 15-minute download stall timer";
- ADR 0014: "15 minutes without download progress".

Either way, the design has a problem:
- **If the claim holds for every run,** every install, update or workshop run longer than 15 minutes is killed as `steam_stalled`. That includes the DayZ server install and the 120-mod batch of exit criterion 3.
- **If it does not** (more likely: block buffering, which flushes once enough output builds up and would explain why M1's 2.1 GB Valheim install passed), the design states something false. An implementer could then rebuild progress tracking or the stall timer on the log file for no reason.

So the design contradicts its own Resource Bounds row, and an implementation mistake is likely in both cases. Narrow the claim in A1 and D2 to what was observed: a login run's output reaches the pipe only when the run exits. Then record whether download progress lines arrive live. The real installs from M1 and M2, or task 10.3's real DayZ run, can show this from line offsets. If they do not arrive live, the design needs another source for the stall timer, for example the growth of `logs/console_log.txt` or `logs/content_log.txt`.

**R3-M2. The log follow has no read bound and no rule for a log that shrinks or is replaced.**
`logs/connection_log.txt` is written by `yagura-steam`, which ADR 0014 treats as able to plant links and write anything in its installation. D2 says only that the step reads the log "from its size at the run's start ... every 250 ms". Three gaps follow:
- **No bound.** D2 sets no limit on bytes read per poll, on line length, or on a partial last line kept between polls. A runaway or hostile SteamCMD that writes hundreds of MB to the log makes the daemon read and split all of it in its own process. The other read path, `readBytes` (`confined_fs.dart:304-325`), takes a `maxBytes`. The Resource Bounds table has no row for this follower.
- **Shrink or replacement.** The spike ran on fresh installations only (`F:\spike\<kind>\steamcmd`), so it never saw what SteamCMD does at startup with a log that has grown. Valve's clients rotate their logs (for example to `*.previous.txt`) or truncate them. If SteamCMD rotates or truncates the file after the daemon records the start size, every read at the old offset returns nothing. The `Waiting for confirmation` line is never seen, and no device gets a mobile prompt. D2 needs a rule: when the size drops below the offset, or the file id changes (`FILE_ID_INFO`, read on the confined handle), restart at offset 0 of the current file. A missing file means "no signal yet", not an error.
- **Start offset.** D2 should say that the start size is read before the process is created. Otherwise an early `Waiting for confirmation` line can be written below the recorded offset and missed.

The first gap lets a SteamCMD run drive the daemon's memory and CPU without limit. The second and third make a mobile login wait silently with no prompt.

**R3-M3. A login run that stays silent on stdout and in the log has no defined outcome, and the log line is a hard-coded literal rather than a versioned pattern.**
The mobile prompt's 2-minute expiry starts when the daemon first sees the log line. If the line never comes, only the login step's 10-minute cap ends the run. The line can fail to come in three ways:
- the log is rotated (R3-M2);
- a SteamCMD build changes the wording;
- an authenticator-code run waits for `Two-factor code:` on stdin instead of exiting. The spike did not observe this kind, and with stdout held back, the stdout pattern can match only at exit.

Until the cap kills the run:
- no prompt reaches any device;
- an install holds a heavy slot for 10 minutes, not the 2 the spec states;
- at the kill, the output SteamCMD held back is lost, so classification has nothing to match.

D2 and the Failure table do not say what error the operation then ends with. The spec scenario "Mobile approval not given" (`steam_guard_timeout` after 2 minutes) does not hold for this case.

Separately, ADR 0014 keeps SteamCMD's recognisable output "per SteamCMD version in a table", and task 1.1 adds the `login` group to `steam/patterns.yaml`. D2 still names `Waiting for confirmation` as a literal, so a wording change in a SteamCMD update would need a code change instead of a pattern update.

The design needs:
- the log signal in the `login` pattern group, for example `guard_mobile_waiting` with source `connection_log`, marked as verified by the spike;
- a defined outcome for a silent run. A login run that writes neither stdout nor a log signal within a stated bound (for example 2 minutes, the mobile bound) is killed and fails with a named reason: `steam_guard_timeout`, or `steam_unknown_error` with "no output before the kill". Add a test row for it against the fake SteamCMD.

Also correct two sentences:
- A1: "If a run keeps waiting on stdin, the daemon kills it as soon as a prompt or password-request pattern matches (D2 works either way)";
- D2 "Choice": "When a run is still alive after a `guard_*` pattern matched, it is killed".

With stdout held until exit, those stdout patterns cannot match while the run lives. Only the log signal or the silent-run bound can end a waiting run.

#### Suggestions

- **R3-S1. Make the fake SteamCMD reproduce the behaviour the amendment relies on.** Task 1.2 says "a log file under the installation's `logs/` when the spike shows SteamCMD writes one", and the spike now shows that it does. Name the behaviours, so the task 5.3 tests exercise the log path and not live stdout:
  - stdout held until exit on the login transcripts;
  - `Waiting for confirmation` written to `logs/connection_log.txt` every few seconds;
  - a log that has already grown and is truncated or rotated at start (R3-M2);
  - a silent run that writes no line (R3-M3).
- **R3-S2. Say where the scrubbed log lines go.** D2 passes each log line through the Scrubber but does not say whether the lines reach the operation log, the failure tail, or only the pattern matcher. If they reach the operation log, the client shows the "Waiting for confirmation" lines live, which helps the admin. If they do not, the scrub only guards against a future change. One clause in D2 settles it.

#### Round 3 Required Changes (history, re-checked in round 4)

R3-M1 and R3-M2 are applied. R3-M3 is applied in the design, and the classification order it led to is R4-M1:

1. **R3-M1.** In A1 and D2 "Mobile approval", narrow the stdout statement to what the spike observed: a login run's output reaches the pipe only when the run exits. Record whether download progress lines (`app_update`, `workshop_download_item`) arrive on stdout while the run lives. Use line offsets from an existing real install, or add the check to task 10.3. If they do not arrive live, give the 15-minute stall timer another source, and update the Resource Bounds "SteamCMD workshop run" row to match.
2. **R3-M2.** In D2 "Mobile approval", bound the log follower: a maximum number of bytes read per poll, a maximum line length (longer lines cut and counted), and a limit on the partial line carried between polls. Add a Resource Bounds row for it. State that the start size is read before the process is created. State that a size below the offset, or a changed file id, restarts the read at offset 0 of the current file, and that a missing file is "no signal yet".
3. **R3-M3.** Move `Waiting for confirmation` into the `login` pattern group of `steam/patterns.yaml` as a log-sourced pattern, verified by the spike. Define the outcome of a login run that writes neither stdout nor a log signal within a stated bound: the run is killed and fails with a named reason. Add that outcome to the Failure table, and add a test-map row against the fake SteamCMD. Correct the A1 sentence "the daemon kills it as soon as a prompt or password-request pattern matches" and the D2 sentence "When a run is still alive after a `guard_*` pattern matched, it is killed", so that neither relies on stdout patterns matching while the run is alive.

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

#### Round 2 Required Changes (history, all applied)

The round-2 verdict was approve with changes. Both of its Required Changes were applied and re-checked in round 2 (see Rebuttals, round 2):

1. **R2-M1.** Bring ADR 0004's "Bindings apply before `onPreStart`" into line with the amended specs. Record a superseding ADR or an amendment note stating that bindings and hook edits apply in one pass after the hooks return, bindings first, so hooks read bound files as they were before this start's bindings. Update the design's "ADRs: To record during apply" to name it.
2. **R2-M2.** Give `ApplyConfig` an owner. Either park its requirement in `platform-backlog` (the config-bindings delta, with a task group under a named milestone), or state in the proposal that it is dropped from the roadmap and why.

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

1. **R4-M1 (applied, re-checked in round 5).** In D2 "Choice", state the precedence between `ok` and the `guard_*` kinds for a run classified at exit: a run whose stdout has the `ok` line after a `guard_*` line logged in. Make `apps/yagurad/lib/src/steam/patterns.yaml` (`login.outcomes`, order and comment) follow that rule, and regenerate `patterns.g.dart`. Add a `steam_patterns_test.dart` case for the spike's approved-mobile stdout that expects `ok`.

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

## Rebuttals

<!-- Author: fixed (cite) or rebutted (reason) per finding. A Critical/Moderate rebuttal counts only once marked "accepted by reviewer". -->

### Round 5

None: round 5 raised no findings.

### Round 4

- **R4-M1 fixed.**
  - `apps/yagurad/lib/src/steam/patterns.yaml`: `ok` sits after the failure kinds and before the guard kinds, the header comment states the order rule, and `patterns.g.dart` is regenerated.
  - design D2 "Choice": failures, then `ok`, then guards; an `ok` line after a `guard_*` line means the run logged in.
  - `apps/yagurad/test/steam/steam_patterns_test.dart`: the group "login outcomes classify the spike transcripts" covers six spike transcripts and the `live.guard_mobile` signal. The author reports `dart test test/steam` at +63, all passing.
- **R4-S1 fixed.** The 60 s silent-run bound restarts on every new `console_log.txt` line: design D2 "Silent run", the Failure row, the Resource Bounds row "Silent login run", and the steam-content scenario "SteamCMD does not respond".
- **R4-S2 fixed.** The AddAccount sequence diagram says `guard_authenticator (run exited)`, and spike finding 3 credits D15 (with D5 "Progress").

#### Reviewer re-check (round 5)

- **R4-M1: applied.**
  - The table order, the header comment and D2 "Choice" state one rule. The test group applies that rule to the spike's transcripts, and an approved mobile login now gives `ok`.
  - Failures still win over `ok`, and an email-code-asked run still gives `guard_email`, because its output has no `...OK` line.
  - I did not run the tests here (`dart` is not on this shell's PATH). I read the test against the table.
- **R4-S1: applied.** The design, the Failure row, the bounds row and the spec scenario agree. The login step's 10-minute cap still bounds a run that keeps writing to its log.
- **R4-S2: applied.**

**Outstanding:** none. R4-M1 is applied and re-checked, and the edits introduce no new contradiction. Changes applied: yes.

### Round 3

- **R3-M1, R3-M2, R3-M3, R3-S1, R3-S2.** The author left no written entries. The edits are listed in the round-4 Metadata, and the round-4 Findings record what the reviewer found applied.

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
