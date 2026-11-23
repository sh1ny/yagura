# Proposal

## Why

Yagura was first specified as one change covering milestones M1-M5. Archiving a change records its requirements in `openspec/specs/` as current behaviour, so one change for the whole platform would either never archive or record unbuilt behaviour. `init-core-platform` therefore carries M1 only, and this change parks everything planned for M2-M5 (Secure remote host, Steam accounts and mods, Operations and complex configs, Linux agent; see `openspec/roadmap.md`) until its milestone starts. M2 (Secure remote host) has been taken out into `m2-secure-remote-host`, and M3 (Steam accounts and mods) into `m3-steam-accounts-and-mods`.

This change is never applied or archived. At the start of each milestone, `specwright-roadmap next` takes that milestone's requirements, decisions and task groups out of it into a new change (for example `m2-secure-remote-host`), which gets its own design review against the code M1 and the earlier milestones built. This change is deleted when nothing is left in it.

## What Changes

- **Config bindings (M4)**: the `ue-ini`, `xml` and `vdf` formats and `repeat` list bindings on top of M3's binder.
- **RCON (M4)**: BattlEye, Source RCON and Rust WebRCON adapters with shared sessions, one-shot commands and a console stream; RCON stop strategy.
- **More games (M4)**: ARK:SA, SCUM and Rust plugins; import and export of instances.
- **Linux agent (M5)**: the systemd service and the POSIX process host.

## Capabilities

### New Capabilities
- `rcon`: protocol adapters, sessions, commands, console streaming.

### Modified Capabilities
Created by `init-core-platform` (M1), or by `m3-steam-accounts-and-mods` for `config-bindings`; this backlog adds requirements to them and extends some earlier requirements (listed as MODIFIED in their delta specs).
- `config-bindings`, `instance-lifecycle`, `plugin-manifest`, `plugin-hooks`, `desktop-client`, `host-service`.

## Impact

- Adds `plugins/{ark_sa,scum,rust}`, the `rcon` section of `plugins/dayz`, and the Linux service files.
- External systems: CurseForge (ARK:SA mods are server-managed), game RCON endpoints, systemd.
