# Review

## Metadata

- **Round:** 2
- **Prior round:** Round 1 approved with five required changes, pending re-check.
- **Reviewer:** Codex CLI
- **Reviewed:** `review.md`, `proposal.md`, `design.md`, `.openspec.yaml`, the installed Specwright review instruction and template, the three named Dart and Flutter project skills, and the tracked source cited below. Scope was limited to M1–M5. No files were edited or checks run.

## Findings

### Critical (blocking)

None.

### Moderate

None remain open from M1–M5.

### Suggestions

None.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **M1. Accepted.** D1 starts from the checked-in root lockfile. The design requires `flutter pub get --enforce-lockfile` under Flutter 3.50.1 and in both PR jobs, followed by `git diff --exit-code -- pubspec.lock` after the last Pub-capable command. The proposal authorizes the workflow edit and preserves the matrix and mise executable pin. The tracked workflow still shows the Windows/Linux matrix, plain `flutter pub get`, and the later Windows AOT smoke, so the enforcement and comparison remain implementation tasks. `design.md:28–34,127–129`, `proposal.md:9–11`, `.github/workflows/ci.yml:22–23,28–59`.

2. **M2. Accepted.** The implementer must record the Windows desktop release command, Flutter and Dart versions, source SHA, and successful exit before completing apply. A gaming deferral leaves the build task open, and an isolated launch remains optional. Merge waits for fresh PR CI on the archived head. Desktop AOT evidence carries forward only across planning-only changes, and any other change requires a rebuild. The tracked Windows smoke builds the daemon target in `apps/yagurad`. `design.md:44–50,131–133`, `.github/workflows/ci.yml:56–59`, `tool/bundle_smoke.dart:343–359`.

3. **M3. Accepted.** D2 preserves existing assertions and adds two settings enum checks. One selects a non-default value and verifies the submitted value. The other submits a required enum with no selection and checks for `Choose a value` and no submission. Both run with the existing create-instance and startup widget tests under the final SDK. The tracked form test submits the enum default, and the create-instance test selects a plugin. The new checks cover the settings callback and validator directly. `design.md:36–42,130`, `apps/yagura_desktop/lib/src/ui/settings_form.dart:289–307`, `apps/yagura_desktop/test/forms_rendered_from_plugin_schemas_test.dart:325–339,360–403`, `apps/yagura_desktop/test/instance_actions_test.dart:123–147`, `apps/yagura_desktop/test/app_test.dart:8–21`.

4. **M4. Accepted.** Context now cites the existing daemon ownership and schema-form contracts. C1 puts the isolated Windows account requirement in the doc comment for `registry.dart`’s `_load`. The tracked implementation shows `_load` reaches the keychain sweep and that the daemon list file and OS keychain use separate storage. C2 assigns the SDK issue and Dart 3.14.1 removal condition to the rewritten function’s doc comment if a matching trace identifies the function and the workaround ships. Apply must then record the follow-up issue labeled `p1` and `risk:high`. `design.md:22–24,68–71,132`, `proposal.md:14`, `docs/adr/0001-daemon-owns-the-host.md:10–11`, `openspec/specs/desktop-client/spec.md:9–10`, `apps/yagura_desktop/lib/src/registry.dart:28–58,163–175`, `apps/yagura_desktop/lib/src/providers.dart:19–27`, `apps/yagura_desktop/lib/src/keychain.dart:20–33`.

5. **M5. Accepted.** T2 is Yes and names committed dependency resolution as the changed persistent state. The updated citations show the root workspace parser, the awaited runner exit, the mise task dispatch, the fresh daemon build and bundle copy, and the settings callback’s `_edited(path)` call. `design.md:7–12,18–20,96–112`, `pubspec.yaml:8–15`, `pubspec.lock:1–11`, `tool/test.dart:11–27,34–44`, `mise.toml:6–12`, `tool/bundle_smoke.dart:140–150,343–359`, `apps/yagura_desktop/lib/src/ui/settings_form.dart:292–307`.

CHANGES_APPLIED: yes

## Rebuttals

The round 1 responses for M1–M5 are accepted by the reviewer. Acceptance covers the planning edits. Dependency resolution, lockfile enforcement, widget checks, desktop AOT, and archived-head CI still require execution evidence.