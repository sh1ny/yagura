# Proposal

## Why

The [Windows check on Yagura PR #7](https://github.com/sh1ny/yagura/actions/runs/46153946168/job/141006358478) failed in `long_download_that_keeps_progressing` before observing any progress. The test gives a real Dart child four seconds to start and emit a log line, then checks two elapsed wall-clock intervals. Those thresholds measure runner speed as well as the watchdog behavior.

This is a separate prerequisite for M3's Windows test exit criterion and the Flutter upgrade. It does not change the milestone's manual Steam or DayZ checks.

## What Changes

- Drive watchdog time explicitly in the failing test. Synchronize on observed log progress from the real child while its stdout is still buffered; check that progress resets the stall deadline and the child can finish.
- Keep production clock and timer defaults, deadline values, process launching, cancellation, log polling and watchdog decisions unchanged. Do not add test retries or adjust real timing thresholds to pass.
- Ship a separate PR from `main`. Do not merge either PR or carry the prerequisite into PR #7 without the owner's next decision.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. `steam-content` already requires long downloads with ongoing log progress to finish without a stall. The change makes its existing coverage deterministic.

## Impact

`SteamCmdService` gains optional time inputs. The failing watchdog test uses the real child, log follower and app install with explicit clock ticks; other tests and production callers use the defaults. No dependency, schema, or CI workflow changes.

### Branch gate

Specwright 0.39.1 (interface 3) found the clean Orca worktree on `bugfix/fix-steamcmd-watchdog-test`. HEAD, local `main`, and freshly fetched `origin/main` were all `c122e21954f6818fa7ec30426e5cb412440eea63`. Planning and code use this same worktree. No active change or archive of this name existed before scaffolding.

## Decision Making

DECISION_MAKING: autonomous
- **Source:** setting

### S1: Fix the flaky watchdog check separately

- **Choice:** Prove the watchdog against a controlled test clock while keeping the real SteamCMD fixture and log reading. Submit it on its own branch from `main`.
- **Rejected:** Treat the red run as transient, raise the timeout, or fold the fix directly into PR #7. The first two leave runner speed in the assertion; the last mixes the unrelated test repair with the SDK migration.
- **Reversal cost:** low; the timing seam and its test can be reverted together.
- **Important:** yes; the change must preserve the production deadline and process coverage.
- **Chosen by:** user.
