# Proposal

## Why

Update Yagura to Flutter 3.50.1 and Dart 3.14.0. The update moves the workspace off the SDK versions affected by the [eMudhra trust-store advisory](https://github.com/dart-lang/sdk/security/advisories/GHSA-frr6-h895-5pxp), and the new Flutter test pin supports `test` 1.32.0.

This is the next change in M3 (Steam accounts and mods). It keeps the M3 test rows runnable on the pinned Windows toolchain without reopening any milestone acceptance criterion or claiming a new manual result.

## What Changes

- Update `mise.toml`, the workspace SDK constraints, development documentation and OpenSpec context. Both PR jobs will enforce the committed lockfile and check after the last build or test step that Pub did not rewrite it. CI and Elevated already install Flutter from `mise.toml`; keep the existing matrix and mise executable pin, and do not add a second Flutter pin. Leave historical run records as recorded.
- Pin `test` 1.32.0 in the six members that declare it. Flutter 3.50.1 pins `test_api` 0.7.14; `test` 1.33.0 requires 0.7.15. Yagura does not use `build_runner`, so it needs neither that upgrade nor an analyzer bump solely to support it.
- Add `material_ui` 1.11.1 to the desktop manifest and replace the 29 legacy Material imports in desktop source and tests. Yagura has no `brand/` kit copy. Keep widget behavior and existing assertions unchanged. Add targeted coverage for selecting a settings enum value and rejecting an empty required enum. Ask the owner before a fix that goes beyond a mechanical migration.
- Build the Windows desktop in release mode and check the existing Windows daemon AOT smoke. If either hits [Dart SDK #64917](https://github.com/dart-lang/sdk/issues/64917), reword only the function named by the compiler trace, preserve its behavior, and verify the same target. Reference the SDK issue in code and open a Yagura issue labeled `p1` and `risk:high` to remove the workaround once Flutter bundles Dart 3.14.1 or later.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. The client still renders the same forms, actions, logs, pairing and Steam views described in `desktop-client`. There is no protocol change or data migration.

## Impact

The workspace keeps a single lockfile. The desktop owns the new runtime dependency; the daemon and shared packages do not import Flutter or Material as part of this change. Yagura has no standalone third-party notices file to update; the README will name the SDK and Material versions and link their upstream licenses. Pub may add transitive Flutter and localization packages. Keep other locked versions unless the solver requires a change, and check every newly selected version before accepting the lockfile.

### Flutter release review

The [Windows SDK archive](https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json) lists Flutter 3.48 and 3.49 only on the beta channel. The upstream comparisons cover [3.48 beta](https://github.com/flutter/flutter/compare/3.47.7...3.48.0-0.5.pre), [3.49 beta](https://github.com/flutter/flutter/compare/3.48.0-0.5.pre...3.49.0-0.2.pre) and [the remaining commits to 3.50.1](https://github.com/flutter/flutter/compare/3.49.0-0.2.pre...3.50.1). The 3.48 range includes Windows native-asset handling, focus history, accessibility and text gamma changes. The 3.49 range includes Windows UTF-8 paths and tool fixes, and Linux OpenGL and window fixes. No separate API migration was found in those beta ranges for the Yagura call sites. Check the desktop tests and release build under the final SDK.

The [3.50 release notes](https://docs.flutter.dev/release/release-notes/release-notes-3.50.0), [migration index](https://docs.flutter.dev/release/breaking-changes#released-in-flutter-3-50) and [3.50.1 patch log](https://github.com/flutter/flutter/blob/3.50.1/CHANGELOG.md#flutter-350-changes) cover the stable release. Android and web changes do not apply to this desktop app. Soft hyphens and right-to-left inline widgets can render differently upstream; Yagura has no `WidgetSpan` usage or golden fixtures. Both existing `DropdownButtonFormField` calls provide callbacks and can keep the compatible default for `enabled`. Flutter's SDK Material deprecation applies and is addressed by its [standalone package migration](https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui).

### Dependency vetting

Dates are UTC, from the Flutter SDK archive, the [Dart archive](https://storage.googleapis.com/dart-archive/channels/stable/release/3.14.0/VERSION) and version records on pub.dev. The [Flutter](https://github.com/flutter/flutter/security/advisories) and [Dart](https://github.com/dart-lang/sdk/security/advisories) advisory feeds list no advisory that applies to the target SDKs. The [pub.dev advisories API](https://pub.dev/api/packages/test/advisories) and [OSV](https://osv.dev/) returned no advisory for the hosted candidates below. The package release-age rule for npm does not apply here.

| Candidate | Released | Reason |
| --- | --- | --- |
| Flutter 3.50.1 | 2026-11-20 | Stable SDK; bundles Dart 3.14.0 |
| Dart 3.14.0 | 2026-11-04 | Compiler and VM bundled with Flutter |
| [`test` 1.32.0](https://pub.dev/packages/test/versions/1.32.0) | 2026-09-02 | Workspace test runner |
| [`test_api` 0.7.14](https://pub.dev/packages/test_api/versions/0.7.14) | 2026-09-02 | Exact Flutter test pin |
| [`test_core` 0.6.20](https://pub.dev/packages/test_core/versions/0.6.20) | 2026-09-02 | Exact `test` dependency |
| [`material_ui` 1.11.1](https://pub.dev/packages/material_ui/versions/1.11.1) | 2026-11-16 | Replacement for the SDK Material library |
| [`cupertino_ui` 1.1.7](https://pub.dev/packages/cupertino_ui/versions/1.1.7) | 2026-11-16 | Material dependency |
| [`intl` 0.20.3](https://pub.dev/packages/intl/versions/0.20.3) | 2026-06-25 | UI localization dependency |
| [`listen` 1.0.1](https://pub.dev/packages/listen/versions/1.0.1) | 2026-07-31 | New Flutter framework dependency |
| `flutter_localizations` from Flutter 3.50.1 | 2026-11-20 | SDK dependency of the standalone UI packages |

### Branch gate

Specwright 0.39.1 (interface 3) found the clean, precreated Orca branch `feat/upgrade-flutter-3-50` instead of an active `main` checkout. HEAD, local `main` and freshly fetched `origin/main` all pointed to `c122e21954f6818fa7ec30426e5cb412440eea63`. The code and planning roots are the same worktree; the change did not exist active or archived on either main ref. The branch passed the manual check without switching worktrees or changing the shared installation.

## Decision Making

DECISION_MAKING: autonomous
- **Source:** setting

### S1: Upgrade the pinned toolchain and Material together

- **Choice:** Update Flutter and Dart, pin the compatible `test`, and migrate Material imports in the same change. Leave the generator dependencies and unrelated packages alone.
- **Rejected:** Defer Material migration, mute the analyzer diagnostic, or override Flutter's test pin to use `test` 1.33.0.
- **Reversal cost:** medium; revert the manifests, imports and lockfile with the SDK pin.
- **Important:** yes; the Material package becomes a desktop runtime dependency.
- **Chosen by:** user.

### S2: Keep the pin if the AOT regression occurs

- **Choice:** Apply a narrow equivalent source workaround only after a release compile hits the known Dart failure. Keep the release build and existing assertions, and track removal in Yagura.
- **Rejected:** Skip AOT compilation, change production compiler flags, or defer the whole upgrade.
- **Reversal cost:** low; remove the source workaround after the fixed Dart SDK ships in Flutter.
- **Important:** yes; the compiler may require a source change outside the imports.
- **Chosen by:** user.
