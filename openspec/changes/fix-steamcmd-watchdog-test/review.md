# Review

## Metadata

- **Round:** 1, required-changes recheck
- **Prior round:** Round 1 identified three Moderate findings about readiness and cleanup, the watchdog timestamp, and resource bounds.
- **Reviewer:** Cross-model CLI (Codex)
- **Reviewed:** Current `review.md`, `design.md`, and `proposal.md` for `fix-steamcmd-watchdog-test`, the installed Specwright review instruction and template, and the project `dart-add-unit-test` skill. Compared the three edits with tracked source at `c122e21954f6818fa7ec30426e5cb412440eea63`. No files were edited and no checks were run.

## Findings

### Critical (blocking)

None.

### Moderate

All three round 1 findings are closed. See the evidence for each item below.

### Suggestions

None.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **Readiness race and cleanup. Accepted.** Failure & Visibility and Flow & State Gaps require the combined readiness wait to race both outcomes of the install. Early success fails the test, and early failure preserves the original error and stack. The design requires teardown registration before install starts. If the test fails or its guard fires, teardown cancels this install, removes the hold file, and awaits settlement before directory deletion. The baseline judge can accept a zero exit without a progress requirement. `CancelToken` retains cancellation in a completed future, and `_execute` subscribes after assigning the process handle, so a cancellation requested during launch still reaches the child. `_execute` awaits exit and stops its log readers during cleanup. The planned async teardown follows the project test skill's guidance on awaited work and teardown callbacks. [Failure & Visibility](/F:/Dev/Orca/Workspace/yagura/fix-steamcmd-watchdog-test/openspec/changes/fix-steamcmd-watchdog-test/design.md:91) · [Flow & State Gaps](/F:/Dev/Orca/Workspace/yagura/fix-steamcmd-watchdog-test/openspec/changes/fix-steamcmd-watchdog-test/design.md:103) · [Install judgment](/F:/Dev/Orca/Workspace/yagura/fix-steamcmd-watchdog-test/apps/yagurad/lib/src/steam/steamcmd_service.dart:795) · [CancelToken](/F:/Dev/Orca/Workspace/yagura/fix-steamcmd-watchdog-test/apps/yagurad/lib/src/operations/cancel_token.dart:15) · [Cancellation and cleanup](/F:/Dev/Orca/Workspace/yagura/fix-steamcmd-watchdog-test/apps/yagurad/lib/src/steam/steamcmd_service.dart:981)
2. **Watchdog timestamp origin and tick. Accepted.** D2 starts at `t=0` for `_execute`'s pre-launch timestamp, advances to `t=3` before delegating to the real launcher, and holds that time until watchdog registration and the first parsed log report. The fixture remains gated for the `t=5` tick. In the baseline, `lastProgressAt` starts at `started` and the first parsed progress refreshes it before the reporter callback. With the four-second limit, the stale timestamp gives five elapsed seconds and triggers `steam_stalled` with `limit: no_progress`. The refreshed timestamp gives two seconds, allowing the install to finish once the gate is released. [D2](/F:/Dev/Orca/Workspace/yagura/fix-steamcmd-watchdog-test/openspec/changes/fix-steamcmd-watchdog-test/design.md:32) · [Timestamp initialization and refresh](/F:/Dev/Orca/Workspace/yagura/fix-steamcmd-watchdog-test/apps/yagurad/lib/src/steam/steamcmd_service.dart:860) · [Watchdog and error mapping](/F:/Dev/Orca/Workspace/yagura/fix-steamcmd-watchdog-test/apps/yagurad/lib/src/steam/steamcmd_service.dart:969) · [Fixture hold](/F:/Dev/Orca/Workspace/yagura/fix-steamcmd-watchdog-test/apps/yagurad/test/fixtures/fake_steamcmd/fake_steamcmd.dart:309)
3. **Log polling and resource bounds. Accepted.** Resource Bounds now describes the limits per poll and for retained data. The baseline follower reads at most 64 KiB per poll, keeps up to 4,096 bytes per line and retains five lines. It polls on a real 250 ms timer while the test waits. The design limits its scheduler-independence claim to the logical-time assertion when both readiness events arrive within the outer guard. [Resource Bounds](/F:/Dev/Orca/Workspace/yagura/fix-steamcmd-watchdog-test/openspec/changes/fix-steamcmd-watchdog-test/design.md:99) · [Follower limits](/F:/Dev/Orca/Workspace/yagura/fix-steamcmd-watchdog-test/apps/yagurad/lib/src/steam/steam_log_follower.dart:30) · [Periodic polling](/F:/Dev/Orca/Workspace/yagura/fix-steamcmd-watchdog-test/apps/yagurad/lib/src/steam/steam_log_follower.dart:75)

CHANGES_APPLIED: yes

## Rebuttals

The reviewer accepts the author's fix notes for all three required changes.

## Implementation follow-through

The accepted review above covers the original design. Pre-ship review moved the clock advance from launch to the `0 / 5000` download report, so refreshing on zero-byte reports alone cannot pass. The test holds the child at the first nonzero report for the tick and again before exit until the final report arrives. Both gates keep stdout buffered; the test still depends on the live log.