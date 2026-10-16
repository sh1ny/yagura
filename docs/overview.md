# Garrison — how it works

A high-level walk-through of the system. The baseline tables (components, state ownership, bounds) are in [openspec/architecture.md](../openspec/architecture.md); decisions are in [docs/adr/](adr/); behaviour contracts are the specs under [openspec/changes/init-core-platform/specs/](../openspec/changes/init-core-platform/specs/).

## The shape

```
 Desktop (Flutter)                       Host (Windows, later Linux)
 ┌─────────────────────┐   gRPC/mTLS    ┌──────────────────────────────────────────┐
 │ Daemon list         │◄──────────────►│ garrisond (Windows service via WinSW)    │
 │ Instance views      │                │  ├─ plugins/<game>/plugin.yaml + hooks.js │
 │ Forms from schemas  │                │  ├─ SQLite state + DPAPI secrets          │
 │ Logs / RCON console │                │  ├─ content store (workshop, shared)     │
 │ Device key (keychain)│               │  ├─ instances/<id>/ (+ instance.json)    │
 └─────────────────────┘                │  └─ SteamCMD per account                 │
                                        │        │ launcher → relay (garrison-srv)  │
                                        │        ▼                                 │
                                        │  game server processes ◄─ RCON, log tail │
                                        └──────────────────────────────────────────┘
```

- **The daemon owns everything on the host** (ADR 0001). The client is a view: it never edits host files and never runs plugin code.
- **A game is a plugin folder**: `plugin.yaml` declares content, launch, ports, settings, config bindings, mods, RCON, logs and stop strategy; optional `hooks.js` handles the odd cases (ADR 0002).
- **Hooks run in quickjs-ng** inside a throwaway worker isolate with a deadline and a memory cap; they decide, the daemon does (ADR 0003).
- **Game servers outlive the daemon** (ADR 0009): each runs under a small relay process started outside the service's process tree, so restarting or upgrading the daemon keeps players connected; the relay captures stdout, records the exit code and lets the daemon deliver Ctrl+C for a graceful stop.
- **Game servers run as `garrison-srv`** (ADR 0013), a low-privilege account; the daemon's secrets and database are not readable by them.

## A plugin, end to end

```yaml
# plugins/dayz/plugin.yaml (abridged)
manifest_version: 1
id: dayz
name: DayZ
version: 1.0.0
steam:
  app_id: 223350          # dedicated server
  login: account          # anonymous | account | account_optional
  workshop_app_id: 221100 # mods come from the game's workshop
executable:
  windows: DayZServer_x64.exe
  linux: DayZServer
ports:
  - { name: game,  default: 2302, protocol: udp, purpose: game }
  - { name: query, default: 27016, protocol: udp, purpose: query }
  - { name: rcon,  default: 2310, protocol: udp, purpose: rcon }
settings:                          # drives the client form
  - { key: hostname,   type: string,  label: Server name, default: "My DayZ" }
  - { key: maxPlayers, type: integer, label: Max players, default: 60, min: 1, max: 127 }
  - { key: cpuCount,   type: integer, label: CPU threads, default: 4 }
  - { key: logs,       type: boolean, label: Verbose logs, default: true }
  - { key: rconPassword, type: secret, label: RCON password }
bindings:                          # settings -> files, no code
  # Garrison-owned copy, so a Steam "validate" never overwrites it
  - { file: garrison/serverDZ.cfg, format: dayz-cfg, key: hostname,   setting: hostname,
      create: true, template: templates/serverDZ.cfg }
  - { file: garrison/serverDZ.cfg, format: dayz-cfg, key: maxPlayers, setting: maxPlayers }
  - { file: "{{profiles}}/BattlEye/BEServer_x64.cfg", format: kv, key: RConPassword, setting: rconPassword,
      create: true, template: templates/BEServer_x64.cfg }
  - { file: "{{profiles}}/BattlEye/BEServer_x64.cfg", format: kv, key: RConPort, value: "{{ports.rcon}}" }
launch:
  args:
    - "-config=garrison/serverDZ.cfg"
    - "-port={{ports.game}}"
    - "-profiles={{profiles}}"
    - "-cpuCount={{settings.cpuCount}}"
    - { if: settings.logs, then: ["-dologs", "-adminlog", "-netlog"] }
    - { if: mods.client, then: "-mod={{mods.client | join(';')}}" }
    - { if: mods.server, then: "-serverMod={{mods.server | join(';')}}" }
mods:
  source: steam_workshop
  stage: link                      # junction to the pinned content-store version
  link_name: "@{{mod.name_safe}}"  # sanitised, de-duplicated, fixed when added
  copy_fallback: true
  keys: { from: "**/*.bikey", to: keys/ }
  roles: [client, server]          # each mod tagged client or server side
rcon: { protocol: battleye, port: rcon, password: rconPassword }
logs:
  - { name: rpt, path: "{{profiles}}/*.RPT", encoding: utf-8, rotate: newest }
  - { name: adm, path: "{{profiles}}/*.ADM", encoding: utf-8, rotate: newest }
stop: { strategy: rcon, command: "#shutdown", grace_seconds: 60, then: kill }
data_paths: ["{{profiles}}", mpmissions/]   # snapshotted before update and delete
```

Valheim needs no `hooks.js` at all; its manifest passes `-savedir {{instance}}/save` and `-logFile {{instance}}/logs/server.log` so saves and logs stay inside the instance, and stops with `strategy: signal` (Ctrl+C through the relay) so the world is saved. DayZ uses one only for things the vocabulary can't say (for example rewriting `cfggameplay.json` paths when a mod ships its own).

## Flow: create, install, start

```mermaid
sequenceDiagram
  participant C as Desktop
  participant A as API
  participant I as Instance manager
  participant S as Steam service
  participant B as Config binder
  participant H as Hook worker
  participant F as Firewall
  participant P as Process supervisor
  C->>A: CreateInstance(plugin=dayz, settings)
  A->>I: validate settings vs schema
  I-->>C: instance (state: not_installed)
  C->>A: Install(instance)
  A->>I: enqueue operation
  I->>S: app_update 223350 (account login)
  S-->>C: progress events (WatchOperation)
  I->>H: onPostInstall(ctx)  [optional]
  I-->>C: state: stopped
  C->>A: Start(instance)
  I->>B: apply bindings (detect manual edits)
  I->>I: stage mods, render launch args
  I->>H: onPreStart(ctx) -> extra args/env
  I->>F: ensure rules for instance ports
  I->>P: launcher -> relay (garrison-srv) -> server; relay.json
  P-->>C: state: starting -> running (health check)
```

## Flow: Steam Guard

The daemon never types into SteamCMD (ADR 0010). It runs `+login … +quit` as arguments with stdin closed; when Steam asks for a code, the daemon recognises the prompt in the output and asks the client. (How SteamCMD behaves with stdin closed for each Guard kind is pinned down by an M3 spike.)

```mermaid
sequenceDiagram
  participant C as Desktop
  participant S as Steam service
  participant SC as SteamCMD
  C->>S: AddSteamAccount(user, password, remember?)
  S->>SC: +login user pass +quit
  SC-->>S: "Steam Guard code required" (email|2FA) / "confirm in app"
  S-->>C: operation event steam_guard_required(kind)
  C->>S: SubmitSteamGuard(code)
  S->>SC: +login user pass CODE +quit
  SC-->>S: logged in (login cached in this account's SteamCMD dir)
  S-->>C: account ready; password kept (DPAPI) only if remember
```

## Flow: mods (DayZ)

1. **Resolve** — workshop IDs → names, sizes, `time_updated` (from SteamCMD/Steam web API).
2. **Acquire** — `workshop_download_item 221100 <id>` into `content/.staging/`, then renamed atomically to `content/steam_workshop/221100/<id>/<time_updated>/`; single-flight per item version; published versions are never modified.
3. **Stage** — junction `instances/<id>/@Community-Framework → content/…/<id>/<version>`; copy if linking fails and `copy_fallback` allows.
4. **Post-process** — copy `*.bikey` into `keys/`; `onModsStaged` hook for fix-ups.
5. **Expose** — ordered `mods.client` / `mods.server` lists feed the launch template.

Updates compare each instance's pinned version with the workshop; the client shows "update available". An update downloads the new version next to the old one and re-links an instance only while it is stopped, so a running instance keeps its files.

## Flow: pairing and the secure channel

```mermaid
sequenceDiagram
  participant Admin
  participant D as garrisond
  participant C as Desktop
  Admin->>D: garrisond pair (local admin pipe)
  D-->>Admin: garrison://host:7443?code=K7Q2-M9XD&ca=sha256:ab12…
  Admin->>C: paste pairing string
  C->>D: Pairing.Info -> CA cert; check SHA-256 == pin
  C->>C: generate device key (keychain), CSR
  C->>D: TLS (CA as sole root, authority garrisond-<id>) Pairing.Enroll(code, name, CSR)
  D->>D: check code (single use, 10 min), sign client cert
  D-->>C: client cert + CA cert
  C->>D: mTLS on every call; interceptor checks device not revoked
```

Before pairing exists (first milestone) the daemon runs a localhost-only plaintext dev listener; it refuses to bind that mode to any other address.

## Protocol surface (v1)

Services in `proto/garrison/v1/` (details and security in [protocol.md](protocol.md)): `System` (info, health, audit), `Pairing` (enroll, info, list/revoke devices), `Plugins` (list, get schema, reload), `Instances` (CRUD, settings, install, update, start, stop, restart, validate, import/export), `Operations` (watch, cancel, list), `Steam` (accounts, guard submit), `Mods` (list, add, remove, reorder, check updates), `Logs` (sources, backlog, follow), `Rcon` (open console: bidirectional, one-shot command), `Firewall` (list owned rules, reconcile). Fixed concepts are typed messages; plugin-shaped data (schemas, setting values) travels as versioned JSON strings.

## Phases

| Milestone | Delivers | Proves |
|---|---|---|
| M1 Walking skeleton | Daemon console mode, Valheim plugin (manifest only), SteamCMD anonymous install, launcher/relay process model, graceful Ctrl+C stop, log stream, dev-mode gRPC, minimal desktop | quickjs-ng builds on Windows via build hook; gRPC streaming; relay re-attach; Valheim stop without data loss |
| M2 Secure remote host | Pairing + mTLS, revocation, renewal, multi-daemon desktop, Windows service, `garrison-srv` account, firewall rules | x509 signing in Dart; service stop/upgrade leaves servers running; relay console starts as `garrison-srv` from the service; untrusted reparse point refused |
| M3 Steam accounts and mods | Accounts + Guard relay, DayZ plugin, mod pipeline, config bindings (dayz-cfg, json, xml) | Workshop at scale; round-trip parsers |
| M4 Operations and complex configs | RCON (BattlEye, Source, WebRCON), file log tailing with encodings, ARK:SA (ue-ini, repeatable groups), SCUM, Rust | Complex configs editable without corruption |
| M5 Linux agent | systemd unit, Linux firewall adapter, Linux secret store, Linux executables in plugins | Platform interfaces hold |
