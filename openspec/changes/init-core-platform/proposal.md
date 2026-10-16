# Proposal

## Why

There is no tool that manages modded dedicated game servers on Windows hosts the way an admin actually works: from a desktop elsewhere, with mods that stay consistent, configs that survive manual edits, and a channel that is safe to expose. WindowsGSM couples UI and host and compiles game support into the app; panels like AMP or Pterodactyl bring web stacks, containers or licensing. Garrison splits a headless daemon from a desktop client and makes every game a data-first plugin, so a game patch is fixed by editing a file on the box.

This is the umbrella change for the whole platform (strategy: `openspec/strategy.md`, baseline ADRs 0001-0013 in `openspec/architecture.md`). It defines every capability's behaviour once and phases the work in `tasks.md` by roadmap milestone: M1 Walking skeleton, M2 Secure remote host, M3 Steam accounts and mods, M4 Operations and complex configs, M5 Linux agent. Each task group names the milestone and the exit criteria it advances.

## What Changes

- **Daemon (`garrisond`)**: a Dart AOT service that owns instances (create, install, update, validate, start, stop, restart, delete, import/export), runs one operation per instance at a time with streamed progress, keeps game servers alive across its own restarts and re-attaches to them, and persists state in SQLite with a portable `instance.json` per instance.
- **Plugin platform**: game plugins as `plugin.yaml` manifests (content, executables, launch templates, ports, settings schema with nested and repeatable structures, config bindings, mods, RCON, logs, stop strategy, health) validated against a versioned JSON Schema, plus optional `hooks.js` lifecycle hooks run in a sandboxed quickjs-ng runtime with deadlines, memory caps and a fixed host API.
- **Config bindings**: settings applied to game files through round-tripping parsers (`ini`, `ue-ini`, `json`, `xml`, `vdf`, `dayz-cfg`, `kv`) that preserve comments, order and unknown keys, with detection of manual edits.
- **Steam content**: SteamCMD managed per account; anonymous, account and token (GSLT) flows; Steam Guard relayed to the client; cached logins; app install/update/validate and workshop downloads.
- **Mods**: a daemon pipeline (resolve, acquire, stage, post-process, expose) configured per game by a declared strategy, with a shared, versioned, immutable content store, directory-junction staging with copy fallback, key-file handling and load-order launch arguments; update detection.
- **Protocol**: gRPC `garrison.v1` with typed messages for fixed concepts and versioned JSON documents for plugin-shaped data; streams for operations, logs and RCON.
- **Security**: daemon-local CA, one-time pairing codes with CA fingerprint pinning, mTLS on every call, per-device revocation, audit log, localhost-only dev mode; secrets in DPAPI/OS stores and never returned by the API.
- **Host integration**: Windows service via WinSW, firewall rules owned by group and reconciled from instance ports; Linux systemd and firewall adapters in M5.
- **RCON**: BattlEye, Source RCON and Rust WebRCON adapters with shared sessions, one-shot commands and an interactive console stream.
- **Logs**: declared log sources (files with globs, rotation and encodings including UTF-16LE; captured stdout) tailed into bounded buffers and streamed with backlog.
- **Desktop client**: Flutter app managing several paired daemons; forms rendered from plugin schemas; operation progress; Steam Guard prompts; logs and RCON console.
- **Reference plugins**: Valheim (manifest only), DayZ, ARK:SA, SCUM, Rust.

## Capabilities

### New Capabilities
- `instance-lifecycle`: instances, their state machine, operations and their serialisation, persistence and `instance.json`, re-attach after daemon restart, import/export.
- `plugin-manifest`: plugin discovery, manifest validation and versioning, settings schema declaration (types, constraints, nested and repeatable structures), launch templates, ports, stop and health declarations, reload.
- `plugin-hooks`: lifecycle hook points, the hook input/output contract, the sandboxed host API, deadlines and memory limits, error reporting.
- `config-bindings`: binding settings to files, supported formats, round-trip preservation, manual edit detection, apply ordering.
- `steam-content`: SteamCMD management, account and anonymous logins, Steam Guard relay, credential retention, GSLT injection, app install/update/validate.
- `mod-management`: mod sources, the content store, staging strategies, key files, load order, mod updates and removal.
- `daemon-protocol`: the gRPC API contract, versioning, operation streaming, error model, plugin-shaped JSON payloads.
- `daemon-security`: pairing, mTLS, device revocation, audit log, dev mode restrictions, secret handling at the API.
- `firewall-rules`: owned rule naming, desired-state reconcile, port changes and instance deletion.
- `rcon`: protocol adapters, sessions, commands, console streaming.
- `log-streaming`: log source declaration, tailing, encodings, rotation, buffering, backlog and live follow.
- `host-service`: running as a Windows service (later systemd), service install/uninstall, data directory layout, startup sequence.
- `desktop-client`: multi-daemon management, schema-driven forms, operation progress, interactive prompts, logs and console views.

### Modified Capabilities
<!-- None: new project. -->

## Impact

- New repository layout (Dart pub workspace): `apps/garrisond`, `apps/garrison_desktop`, `packages/garrison_proto`, `packages/garrison_js`, `packages/garrison_formats`, `packages/garrison_plugin`, `proto/garrison/v1/`, `schemas/plugin-manifest.v1.json`, `plugins/{valheim,dayz,ark_sa,scum,rust}`, `tool/` (packaging, WinSW config).
- Dependencies: `grpc`, `protobuf`, `sqlite3`, `x509`, `pointycastle`, `path`, `yaml`, `json_schema`-style validator, `win32`/`ffi`, `hooks`, `native_toolchain_c`; vendored quickjs-ng (MIT); bundled WinSW 2.x (MIT); Flutter `flutter_secure_storage`.
- External systems: Steam (SteamCMD), Steam Web API for workshop metadata, CurseForge (ARK:SA mods are server-managed), Windows Firewall, Windows Service Control Manager.
- Builds on ADRs 0001-0013 (proposed in the baseline, accepted at baseline review).
