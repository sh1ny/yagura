# Tasks

## Test map

No requirements change. The existing Steam content behavior must survive a watchdog check after real log progress.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| Steam content → bounded SteamCMD operation | Real file-log progress refreshes the no-progress deadline | `apps/yagurad/test/steam/steamcmd_runs_are_bounded_and_cleaned_up_test.dart` | `long_download_that_keeps_progressing` | red |

## 1. Drive the watchdog from observed progress

- [x] 1.1 Verify the fixture writes the first progress line to the live log and holds the child until its flag is removed. Confirm install cancellation remains latched while the child launches.
- [x] 1.2 Replace this test's wall-clock inference with an injected clock and watchdog callback. Wait for actual log progress and registration; race readiness against install completion, and pre-register cleanup using this install's cancel token. Demonstrate that the test fails with `steam_stalled` (`limit: no_progress`) when the timestamp refresh is deliberately disabled.
- [ ] 1.3 Restore the original timestamp refresh with the scoped injected clock. Keep the default production clock, periodic schedule, bounds and progress policy. Run the watchdog test file and its callers' relevant tests, including the real log path.

## PR verification

Wait for the existing Windows and Linux hosted jobs before reporting the PR ready.
