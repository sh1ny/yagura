# Yagura Roadmap

Strategy: openspec/strategy.md · Architecture: openspec/architecture.md

<!-- Status is derived: a change is done when archived; a milestone is done when its changes are done and its exit criteria pass. Do not add status checkboxes for changes. -->

Each milestone is one change. `init-core-platform` carries M1. The requirements, design decisions and task groups already written for M2-M5 are parked in `platform-backlog`, which is never applied or archived: when a milestone starts, `specwright-roadmap next` takes its part of the backlog into a new change named for the milestone (for example `m2-secure-remote-host`), with the requirements as delta specs and its own design review, and deletes that part from the backlog. A milestone change archives when its groups are done, so `openspec/specs/` only ever records built behaviour. The exit criteria below are what each milestone must show.

## Now: M3 - Steam accounts and mods

**Outcome:** An admin adds a Steam account with Steam Guard from the desktop, and a DayZ server with workshop mods goes from mod IDs to a running server with linked mods and keys in one action, staying correct across mod updates; its config files are written through round-tripping bindings, and plugin version changes migrate instance settings. Main risks retired: Steam Guard prompts relayed through a non-interactive SteamCMD, and mod content shared safely between instances. DayZ stops with the `signal` strategy in M3; `rcon` arrives in M4.

**Exit criteria:**
- Every test-map row of `m3-steam-accounts-and-mods` is green on Windows CI, or on a Windows machine where a row needs administrator rights, the service installed, or a real Steam account (agent)
- A Steam account protected by Steam Guard is added from the desktop: the code prompt reaches the desktop, the login completes, and the password appears in no file or log (user)
- DayZ with 10+ workshop mods goes from mod IDs to a running server with linked mods and keys in one action, and stays correct across a mod update (user)
- Two instances using the same mod version share one copy in the content store (agent)
- Every `ini`, `json`, `dayz-cfg` and `kv` corpus file round-trips byte for byte, and a manual edit to a bound file is detected, not overwritten (agent)
- A plugin version change re-validates its instances and migrates their settings, or reports `settings_invalid` (agent)

**Changes** (in order; each about one PR):
1. `m3-steam-accounts-and-mods` - taken from `platform-backlog` groups 14-17 (Steam accounts and Steam Guard; formats and config bindings; mod pipeline and content store; DayZ plugin and plugin migrations)

## Next: M4 - Operations and complex configs

RCON (BattlEye, Source, WebRCON) with a console UI and the `rcon` stop strategy, the `ue-ini`, `xml` and `vdf` formats, ARK:SA with repeatable config groups, SCUM (UTF-16 logs, graceful stop), Rust, and instance import and export. Main risk retired: three RCON protocols behind one console and stop path. Its change is taken from `platform-backlog` groups 18-19.

## Later

Each later milestone's change is taken from `platform-backlog` (M5: group 20; group 21 runs with the last one).

- M5 - Linux agent: systemd unit with servers in their own scopes, Linux process host, firewall and secret store adapters, reference plugins on Linux.

## Done

### M2 - Secure remote host (2026-10-20)

Change: `m2-secure-remote-host`. All 6 exit criteria pass (`docs/milestones/m2.md`); the two-daemons-and-a-conflict criterion was accepted by the user on the automated rows, with no second host to run it by hand. Learned: Windows account isolation has dependencies no fake shows (a server whose profile hive was unloaded could not save, found only on a real runner, task 12.7), CI runner images change under a green suite (Ubuntu 26.04's uutils `sleep`), and the user's manual run on a real host found a purge that could not be retried: keep the manual exit runs on a real host, and keep the account- and firewall-changing rows on runners, never on a desktop.

### M1 - Walking skeleton (2026-10-17)

Change: `init-core-platform`. All 8 exit criteria pass (`docs/milestones/m1.md`). Learned: the riskiest pieces held (quickjs-ng under MSVC, the relay surviving a daemon restart, Ctrl+C saves), but the real tools behave differently from their docs and fakes: SteamCMD exits 7 after its first self-update, the relay must be the compiled `yagurad`, and a 35-task change only got its review at the end, where it found 48 problems: review large changes per task group, not only before the merge.
