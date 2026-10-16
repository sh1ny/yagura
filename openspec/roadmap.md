# Yagura Roadmap

Strategy: openspec/strategy.md · Architecture: openspec/architecture.md

<!-- Status is derived: a change is done when archived; a milestone is done when its changes are done and its exit criteria pass. Do not add status checkboxes for changes. -->

Each milestone is one change. `init-core-platform` carries M1. The requirements, design decisions and task groups already written for M2-M5 are parked in `platform-backlog`, which is never applied or archived: when a milestone starts, `specwright-roadmap next` takes its part of the backlog into a new change named for the milestone (for example `m2-secure-remote-host`), with the requirements as delta specs and its own design review, and deletes that part from the backlog. A milestone change archives when its groups are done, so `openspec/specs/` only ever records built behaviour. The exit criteria below are what each milestone must show.

## Now: M1 - Walking skeleton

**Outcome:** On a Windows machine, `yagurad run --console --dev` installs a Valheim server with SteamCMD, starts it under the relay, streams its log to a minimal desktop client over localhost gRPC, stops it gracefully with the world saved, and keeps it running across a daemon restart. The Valheim plugin is a manifest with no hooks; a test plugin proves JS hooks run with deadlines and memory caps.

**Exit criteria:**
- quickjs-ng compiles through the Dart build hook with MSVC on Windows and `yagura_js` tests pass there (agent); a clang-cl or prebuilt fallback meets this only if the user amends this criterion
- Every test-map row of `init-core-platform` not tagged `valheim` is green on Windows CI, and the `valheim` rows pass on a Windows machine with Valheim installed (agent)
- The compiled `yagurad` bundle, run from outside the repository, evaluates a hook and starts, stops and re-attaches a test server (agent)
- A hook with `while(true){}` is interrupted within 6 s while the daemon keeps answering `System.GetInfo` (agent)
- Valheim installs anonymously, starts, reaches `running` via its log-match health check, and its log streams to the desktop client (user)
- Stopping Valheim from the client delivers Ctrl+C through the relay and the world file timestamp updates before the process exits (user)
- Killing and restarting the daemon while Valheim runs leaves the server PID unchanged and the client shows it `running` again (user)
- The Valheim plugin has no `hooks.js` (agent)

**Changes** (in order; each about one PR):
1. `init-core-platform` - the walking skeleton; task groups 1-9

## Next: M2 - Secure remote host

The daemon runs as a Windows service, pairs with desktops over mTLS with per-device revocation and renewal, runs game servers as `yagura-srv`, and opens firewall ports itself; the desktop manages several daemons and detects concurrent edits. Main risks retired: certificate signing in Dart, TLS request-mode behaviour, and WinSW leaving relays running on service stop and upgrade. Exit criteria include: a fresh host is installed and paired in under 5 minutes with no manual certificate or firewall work (user); service stop and upgrade leave running servers untouched (user); a revoked device's next call fails (agent).

**Changes:** `m2-secure-remote-host`, taken from `platform-backlog` groups 10-13 when M2 starts.

## Later

Each later milestone's change is taken from `platform-backlog` (M3: groups 14-17; M4: 18-19; M5: 20; group 21 runs with the last one).

- M3 - Steam accounts and mods: account logins with Steam Guard relay, DayZ plugin with workshop mods (versioned content store, junctions, bikeys, load order), config bindings (ini, json, dayz-cfg, kv), plugin version migration.
- M4 - Operations and complex configs: RCON (BattlEye, Source, WebRCON) with console UI, `ue-ini`/`xml`/`vdf` formats, ARK:SA with repeatable config groups, SCUM (UTF-16 logs, graceful stop), Rust, import/export.
- M5 - Linux agent: systemd unit with servers in their own scopes, Linux process host, firewall and secret store adapters, reference plugins on Linux.

## Done
