# Tasks

## Test map

No delta scenarios. This change preserves the desktop and daemon contracts. Use the existing widget tests for the create-instance flow and app startup, plus two focused form cases: selecting a non-default enum value submits that value; saving a required enum without a selection shows `Choose a value` and submits nothing. If an AOT target hits Dart SDK #64917, its red build trace is the failing check and the existing tests for the affected function and callers protect behavior.

## 1. Upgrade the workspace and desktop Material imports

- [x] 1.1 [evidence] Update the mise Flutter pin to 3.50.1 and the workspace Dart constraints to 3.14.0. Pin `test` 1.32.0 in the six members that use it. Add desktop-only `material_ui` 1.11.1. Settle A1 before accepting the lock by resolving from the committed lockfile with a targeted Pub dry run; vet each selected version and record its release date in the proposal. Accept only the required lockfile delta. Verify `mise exec -- flutter --version` and `mise exec -- flutter pub get --enforce-lockfile`. Migrate all 29 Material imports; keep application logic and existing test assertions unchanged. Add the two enum checks, and settle A2 with focused desktop analysis plus the form, instance creation and startup widget tests on the new SDK. Run the startup widget test in a clean CI profile if the local profile has Yagura data. Add C1 to the desktop registry startup doc comment. Update the README's SDK and license links and the OpenSpec context. Enforce the lockfile in both PR jobs and compare it to the checkout after the last Pub-capable step. Preserve historical run records, the CI matrix and the mise executable pin. Record the resolved delta and verification results → `evidence/1.1.md`.

## 2. Verify the release compiler

- [x] 2.1 [evidence] Settle A3 for the desktop with `mise exec -- flutter build windows --release --no-pub` from `apps/yagura_desktop` on the committed code. Run the gaming check before building. If gaming blocks the build, keep this task open until the workstation is free or hosted desktop verification is approved. Record the exact command, the Flutter and Dart versions, the source SHA and the successful exit. If #64917 hits, record the trace before applying S2/C2, rerun the same target and the affected existing tests, and record the Yagura follow-up labeled `p1` and `risk:high`. Desktop release launch is optional and must follow C1 → `evidence/2.1.md`.

## Workflow follow-up

- Run pre-ship review without changing project workflow settings. Ship to GitHub as KintsugiBot; request the Codex PR review using the process-scoped owner exception. Wait for Windows and Linux PR checks, including the Windows daemon AOT bundle smoke and lockfile comparison. A daemon-side #64917 failure follows the same S2/C2 trace, verification and issue procedure. Record whether each target hit the compiler regression.
- After checks and reviews settle, archive on the PR branch and verify CI passes on the archived head. Carry forward the desktop AOT proof only if subsequent commits changed planning records alone; rebuild after any other change. Do not merge.
- Optional manual check: start the verified Windows release executable in an isolated Windows account with no live Yagura credentials and confirm the first window opens. The build and widget tests do not prove that native launch.
