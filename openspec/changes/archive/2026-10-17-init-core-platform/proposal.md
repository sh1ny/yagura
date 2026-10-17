# Proposal

## Why

There is no tool that manages modded dedicated game servers on Windows hosts the way an admin actually works: from a desktop elsewhere, with mods that stay consistent, configs that survive manual edits, and a channel that is safe to expose. WindowsGSM couples UI and host and compiles game support into the app; panels like AMP or Pterodactyl bring web stacks, containers or licensing. Yagura splits a headless daemon from a desktop client and makes every game a data-first plugin, so a game patch is fixed by editing a file on the box.

This change is milestone M1, the Walking skeleton (`openspec/roadmap.md`; strategy in `openspec/strategy.md`, baseline ADRs 0001-0013 in `openspec/architecture.md`). It retires the two riskiest assumptions first (quickjs-ng built through a Dart build hook with MSVC, and Ctrl+C reaching a server through the relay so it saves) and builds the smallest end-to-end path: on one Windows machine, `yagurad run --console --dev` installs Valheim anonymously, runs it under the relay, streams its log to a minimal desktop client over localhost gRPC, stops it with the world saved, and keeps it running across a daemon restart. The M2-M5 requirements and task groups are parked in `openspec/changes/platform-backlog/`, and each later milestone is taken out of it as its own change.

## What Changes

- **Workspace and spikes**: the Dart pub workspace with the daemon, desktop app and packages; the quickjs-ng build spike and the process-model spike; generated protocol code.
- **Daemon (`yagurad`)**: data directory, exclusive lock, SQLite with migrations, a startup sequence that separates fatal from degraded steps; instances (create, install, update, validate, start, stop, restart, delete) with one operation per instance at a time, streamed and resumable progress, cancellation, interrupted-operation recovery, a portable `instance.json`, error reasons with defined exits, snapshots of save data, and autostart.
- **Process model**: `launch`, `relay` and `signal` entry points that keep game servers running across daemon restarts, re-attach by PID, executable and start time, stop by Ctrl+C or kill with a grace period, and restart crashed servers by policy. Servers run as the current user in console mode.
- **Plugin platform**: `plugin.yaml` manifests validated against a versioned JSON Schema (settings schema, launch templates, ports, stop and health, data paths), `yagura plugin lint`, reload on request, and optional `hooks.js` lifecycle hooks in a sandboxed quickjs-ng runtime with deadlines, memory caps, a read-only host API and JSON file edits applied by the daemon. Manifest features later milestones build (RCON stop, query health, bindings, mods) are rejected as unsupported, and `secret` settings stay unset until the secret store exists.
- **Steam content**: one anonymous SteamCMD installation managed by the daemon, run non-interactively and bounded; app install, update and validate with progress and disk checks.
- **Logs**: stdout capture and file sources with encodings and rotation, bounded buffers, backlog and live follow with drop markers.
- **Protocol**: gRPC `yagura.v1` for the M1 services with version negotiation, structured errors, size limits, slim instance deltas, JSON documents for plugin-shaped data, and `not_implemented` for methods M1 does not build; plaintext only in loopback dev mode, which is the only mode in M1.
- **Desktop client**: a minimal Flutter app on one dev-mode connection that reconnects after a daemon restart: instance list, create/install/start/stop/delete, schema-driven settings form, operation progress, log view.
- **Reference plugin**: Valheim, manifest only.

## Capabilities

### New Capabilities
- `instance-lifecycle`: instances, their state machine, operations and their serialisation, persistence and `instance.json`, crash handling, re-attach after daemon restart, snapshots, autostart.
- `plugin-manifest`: plugin discovery, manifest validation and versioning, settings schema declaration (types, constraints, nested and repeatable structures), launch templates, ports, stop and health declarations, data paths, reload.
- `plugin-hooks`: lifecycle hook points, the hook input/output contract, the sandboxed host API, deadlines and memory limits, error reporting.
- `steam-content`: SteamCMD management for anonymous logins (account plugins refused until M3), non-interactive runs, app install/update/validate, run bounds and cleanup.
- `daemon-protocol`: the gRPC API contract, versioning, operation streaming, error model, plugin-shaped JSON payloads, message size limits.
- `daemon-security`: development mode restricted to loopback (pairing, mTLS and the rest arrive in M2).
- `log-streaming`: log source declaration, tailing, encodings, rotation, buffering, backlog and live follow.
- `host-service`: data directory layout, startup sequence, single daemon per data directory (the Windows service arrives in M2).
- `desktop-client`: one daemon connection with reconnect, instance actions, schema-driven forms and log views (pairing and several daemons arrive in M2).

### Modified Capabilities
<!-- None: new project. -->

## Impact

- New repository layout (Dart pub workspace): `apps/yagurad`, `apps/yagura_desktop`, `packages/yagura_proto`, `packages/yagura_js`, `packages/yagura_formats`, `packages/yagura_plugin`, `proto/yagura/v1/`, `schemas/plugin-manifest.v1.json`, `plugins/valheim`, `tool/`.
- Dependencies: `grpc`, `protobuf`, `sqlite3`, `path`, `yaml`, a JSON Schema validator, `win32`/`ffi`, `hooks`, `native_toolchain_c`; vendored quickjs-ng (MIT).
- External systems: Steam (SteamCMD, anonymous).
- Builds on ADRs 0001-0013 (proposed in the baseline, accepted at baseline review).
