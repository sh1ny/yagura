# Yagura Roadmap

Strategy: openspec/strategy.md · Architecture: openspec/architecture.md

<!-- Status is derived: a change is done when archived; a milestone is done when its changes are done and its exit criteria pass. Do not add status checkboxes for changes. -->

Each milestone is one change. `init-core-platform` carries M1. The requirements, design decisions and task groups already written for M2-M5 are parked in `platform-backlog`, which is never applied or archived: when a milestone starts, `specwright-roadmap next` takes its part of the backlog into a new change named for the milestone (for example `m2-secure-remote-host`), with the requirements as delta specs and its own design review, and deletes that part from the backlog. A milestone change archives when its groups are done, so `openspec/specs/` only ever records built behaviour. The exit criteria below are what each milestone must show.

## Now: M2 - Secure remote host

**Outcome:** The daemon runs as a Windows service, pairs with desktops over mTLS with per-device revocation and renewal, runs game servers as `yagura-srv`, and opens firewall ports itself; the desktop manages several daemons and detects concurrent edits. Main risks retired: certificate signing in Dart, TLS request-mode behaviour, and WinSW leaving relays running on service stop and upgrade.

**Exit criteria:**
- Every test-map row of `m2-secure-remote-host` is green on Windows CI, or on a Windows machine where a row needs administrator rights or the service installed (agent)
- A fresh host is installed and paired in under 5 minutes with no manual certificate or firewall work (user)
- Service stop and upgrade leave running servers untouched (user)
- A revoked device's next call fails (agent)
- A game server runs as `yagura-srv`, and its ports are open in the firewall only while its instance exists (agent)
- One desktop manages two daemons, and a settings edit made from a second desktop is detected as a conflict, not overwritten (user)

**Changes** (in order; each about one PR):
1. `m2-secure-remote-host` - taken from `platform-backlog` groups 10-13 (PKI, pairing and mTLS; Windows service and game-server account; firewall reconciler; remote desktop)

## Next: M3 - Steam accounts and mods

Steam account logins with the Steam Guard relay, the DayZ plugin with workshop mods (versioned content store, junctions, bikeys, load order), config bindings (`ini`, `json`, `dayz-cfg`, `kv`) and plugin version migration. Main risks retired: Steam Guard prompts relayed through a non-interactive SteamCMD, and mod content shared safely between instances. DayZ stops with the `signal` strategy in M3; `rcon` arrives in M4.

**Changes:** `m3-steam-accounts-and-mods`, taken from `platform-backlog` groups 14-17 when M3 starts.

## Later

Each later milestone's change is taken from `platform-backlog` (M4: groups 18-19; M5: 20; group 21 runs with the last one).

- M4 - Operations and complex configs: RCON (BattlEye, Source, WebRCON) with console UI, `ue-ini`/`xml`/`vdf` formats, ARK:SA with repeatable config groups, SCUM (UTF-16 logs, graceful stop), Rust, import/export.
- M5 - Linux agent: systemd unit with servers in their own scopes, Linux process host, firewall and secret store adapters, reference plugins on Linux.

## Done

### M1 - Walking skeleton (2026-10-17)

Change: `init-core-platform`. All 8 exit criteria pass (`docs/milestones/m1.md`). Learned: the riskiest pieces held (quickjs-ng under MSVC, the relay surviving a daemon restart, Ctrl+C saves), but the real tools behave differently from their docs and fakes: SteamCMD exits 7 after its first self-update, the relay must be the compiled `yagurad`, and a 35-task change only got its review at the end, where it found 48 problems: review large changes per task group, not only before the merge.
