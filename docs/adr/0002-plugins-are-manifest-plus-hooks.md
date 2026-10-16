# 0002. Game plugins are a declarative manifest plus optional JS hooks

- Status: accepted
- Date: 2026-10-16
- Supersedes: —

## Context
Most dedicated servers follow one loop: download with SteamCMD, write config files, launch an executable with arguments, watch the process, read logs, maybe talk RCON. A minority need odd steps (generated files, renamed mod folders, chained pre-start scripts). Admins must be able to fix a plugin on the box after a game patch without a compiler, and the daemon is an AOT-compiled Dart binary that cannot load Dart code at runtime.

## Decision
A plugin is a folder `plugins/<id>/` holding `plugin.yaml` (the manifest) and optionally `hooks.js`. The manifest declares, as data: identity and versions, Steam content (app id, branch, login requirement), executables per OS, launch arguments as templates over settings, ports (with protocol and purpose), the settings schema, config bindings (ADR 0004), the mod strategy (ADR 0005), RCON protocol, log sources, stop strategy, health checks, and `data_paths` (where the game keeps saves and player data; must resolve inside the instance, e.g. Valheim `-savedir`). `hooks.js` may export lifecycle hooks that run at fixed points and return data the daemon applies (extra args, env, file edits through host functions). The daemon does the work; hooks decide. The manifest format carries `manifest_version` and is validated against a JSON Schema shipped with the daemon.

**Rejected: plugins as separate executables speaking JSON-RPC (HashiCorp style).** Crash isolation is better, but every game needs a compiled binary per OS, admins cannot patch them in place, and a plugin could do anything the daemon user can.

**Rejected: dart_eval plugins.** Keeps one language, but every host type needs generated bridge classes and the supported language subset trails Dart.

**Reversal cost: high.** The manifest format and hook contract are the public plugin interface; once third-party plugins exist, changing them needs a migration.

## Consequences
- The manifest must be expressive enough that Valheim needs no hooks; that is the test of the format.
- The daemon owns a growing set of generic mechanisms (bindings, mod strategies, RCON adapters) instead of plugins re-implementing them.
- Manifest changes are versioned; the daemon refuses a manifest whose `manifest_version` it does not know.
- Plugins reload only on explicit request; each operation runs on the manifest snapshot it started with.
- When a plugin's version changes, each instance's stored settings are re-validated (after an optional `migrateSettings` hook); an instance whose settings no longer validate, or whose plugin is gone, moves to `error` with `settings_invalid` or `plugin_missing` until fixed.
