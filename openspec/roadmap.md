# Yagura Roadmap

Strategy: openspec/strategy.md · Architecture: openspec/architecture.md

<!-- Status is derived: a change is done when archived; a milestone is done when its changes are done and its exit criteria pass. Do not add status checkboxes for changes. -->

The whole platform is specified by one umbrella change, `init-core-platform`, at the author's request. Its `tasks.md` groups are tagged by milestone (M1-M5) in order. Specwright derives a milestone's status from archived changes, and an umbrella change archives only when all its groups are done; so at the close of each milestone the remaining task groups move into a follow-up change named for the next milestone (for example `m2-secure-remote-host`), carrying their specs as deltas, and `init-core-platform` archives with the groups already done. The exit criteria below are what each milestone must show, whichever change carries the work.

## Now: M1 - Walking skeleton

**Outcome:** On a Windows machine, `yagurad --console --dev` installs a Valheim server with SteamCMD, starts it under the relay, streams its log to a minimal desktop client over localhost gRPC, stops it gracefully with the world saved, and keeps it running across a daemon restart. The Valheim plugin is a manifest with no hooks; a test plugin proves JS hooks run with deadlines and memory caps.

**Exit criteria:**
- quickjs-ng compiles through the Dart build hook with MSVC on Windows and `yagura_js` tests pass there (agent)
- Every M1-tagged test-map row of `init-core-platform` is green on Windows CI (agent)
- A hook with `while(true){}` is interrupted within 6 s while the daemon keeps answering `System.GetInfo` (agent)
- Valheim installs anonymously, starts, reaches `running` via its log-match health check, and its log streams to the desktop client (user)
- Stopping Valheim from the client delivers Ctrl+C through the relay and the world file timestamp updates before the process exits (user)
- Killing and restarting the daemon while Valheim runs leaves the server PID unchanged and the client shows it `running` again (user)
- The Valheim plugin has no `hooks.js` (agent)

**Changes** (in order; each about one PR):
1. `init-core-platform` - umbrella specification; M1 task groups 1-9 (see tasks.md)

## Next: M2 - Secure remote host

The daemon runs as a Windows service, pairs with desktops over mTLS with per-device revocation and renewal, runs game servers as `yagura-srv`, and opens firewall ports itself; the desktop manages several daemons and detects concurrent edits. Main risks retired: certificate signing in Dart, TLS request-mode behaviour, and WinSW leaving relays running on service stop and upgrade. Exit criteria include: a fresh host is installed and paired in under 5 minutes with no manual certificate or firewall work (user); service stop and upgrade leave running servers untouched (user); a revoked device's next call fails (agent).

## Later

- M3 - Steam accounts and mods: account logins with Steam Guard relay, DayZ plugin with workshop mods (versioned content store, junctions, bikeys, load order), config bindings (ini, json, dayz-cfg, kv), plugin version migration.
- M4 - Operations and complex configs: RCON (BattlEye, Source, WebRCON) with console UI, `ue-ini`/`xml`/`vdf` formats, ARK:SA with repeatable config groups, SCUM (UTF-16 logs, graceful stop), Rust, import/export.
- M5 - Linux agent: systemd unit with servers in their own scopes, Linux process host, firewall and secret store adapters, reference plugins on Linux.

## Done
