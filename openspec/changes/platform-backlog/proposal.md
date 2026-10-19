# Proposal

## Why

Yagura was first specified as one change covering milestones M1-M5. Archiving a change records its requirements in `openspec/specs/` as current behaviour, so one change for the whole platform would either never archive or record unbuilt behaviour. `init-core-platform` therefore carries M1 only, and this change parks everything planned for M2-M5 (Secure remote host, Steam accounts and mods, Operations and complex configs, Linux agent; see `openspec/roadmap.md`) until its milestone starts. M2 (Secure remote host) has been taken out into `m2-secure-remote-host`.

This change is never applied or archived. At the start of each milestone, `specwright-roadmap next` takes that milestone's requirements, decisions and task groups out of it into a new change (for example `m2-secure-remote-host`), which gets its own design review against the code M1 and the earlier milestones built. This change is deleted when nothing is left in it.

## What Changes

- **Steam accounts (M3)**: account logins with Steam Guard relayed to the client, credential retention, GSLT injection, workshop downloads.
- **Config bindings (M3, M4)**: settings applied to game files through round-tripping parsers (`ini`, `json`, `dayz-cfg`, `kv`, then `ue-ini`, `xml`, `vdf`) with manual-edit detection.
- **Mods (M3)**: the mod pipeline with a shared, versioned content store, junction staging with copy fallback, key files, load order and update detection; plugin version migration.
- **RCON (M4)**: BattlEye, Source RCON and Rust WebRCON adapters with shared sessions, one-shot commands and a console stream; RCON stop strategy.
- **More games (M3, M4)**: DayZ, ARK:SA, SCUM and Rust plugins; import and export of instances.

## Capabilities

### New Capabilities
- `config-bindings`: binding settings to files, supported formats, round-trip preservation, manual edit detection, atomic writes.
- `mod-management`: mod sources, the content store, staging strategies, key files, load order, mod updates and removal.
- `rcon`: protocol adapters, sessions, commands, console streaming.

### Modified Capabilities
Created by `init-core-platform` (M1); this backlog adds requirements to them and extends some M1 requirements (listed as MODIFIED in their delta specs).
- `instance-lifecycle`, `plugin-manifest`, `plugin-hooks`, `steam-content`, `daemon-protocol`, `log-streaming`, `host-service`, `desktop-client`.

## Impact

- Adds `plugins/{dayz,ark_sa,scum,rust}` and the Linux service files.
- External systems: Steam accounts and Steam Guard, Steam Web API for workshop metadata, CurseForge (ARK:SA mods are server-managed), systemd.
