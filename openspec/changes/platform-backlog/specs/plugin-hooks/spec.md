# Spec Delta

## Purpose

Lets a plugin run small JavaScript functions at fixed lifecycle points for game-specific steps the manifest cannot express, inside a sandbox that cannot stall the daemon or reach outside the instance.

## MODIFIED Requirements

### Requirement: Hook points
The daemon SHALL call these optional hooks when `hooks.js` exports them: `onPostInstall`, `onPostUpdate`, `onModsStaged`, `onPreStart` and `onPostStop` after the daemon's own work for that step, and `migrateSettings` (old settings and plugin versions in, new settings out) on plugin version changes. A missing export is skipped.

#### Scenario: Pre-start hook adds arguments
- **WHEN** `onPreStart` returns `{"args": ["-freezecheck"], "env": {"SteamAppId": "221100"}}`
- **THEN** the server is launched with `-freezecheck` appended after the manifest's arguments and `SteamAppId=221100` in its environment

#### Scenario: Migration hook result applied
- **WHEN** `migrateSettings` returns `{"settings": {...}}` that validates against the new schema
- **THEN** the instance's settings are replaced, its revision increments, and `instance.json` is rewritten

#### Scenario: Hook not exported
- **WHEN** a plugin's `hooks.js` exports only `onPreStart` and the instance is installed
- **THEN** install completes without calling any hook and without a warning

### Requirement: Hook input and output contract
Each hook SHALL receive one JSON context (instance id, plugin id and version, OS, paths relative to the instance root, settings with secrets replaced by placeholders, ports, staged mods) and SHALL return a JSON object validated against that hook's result schema; unknown keys are rejected.

#### Scenario: Context contents
- **WHEN** `onPreStart` runs for an instance with an RCON password set
- **THEN** the context contains `settings.rconPassword` as `{"secret": true}` and not the password

#### Scenario: Invalid result shape
- **WHEN** `onPreStart` returns `{"args": "-freezecheck"}` (a string instead of an array)
- **THEN** the operation fails with error `hook_result_invalid` naming `onPreStart` and the path `args`, and the server is not started

### Requirement: Sandboxed host API
Hooks SHALL reach the system only through the `yagura` object: logging, reading and listing files inside the instance root (read-only, including staged mod folders), and parsing or serialising config text. Hooks SHALL NOT write files; they return file edits in their result, which the daemon applies. Hooks have no network, process, environment-variable or timer access.

#### Scenario: File edit returned and applied by the daemon
- **WHEN** `onPreStart` returns `{"files": [{"path": "cfggameplay.json", "format": "json", "patch": {"GeneralData": {"disableBaseDamage": true}}}]}`
- **THEN** the daemon applies the patch atomically, the file contains `disableBaseDamage: true` with all other keys and their order kept, and the next start reports no external edit for that file

#### Scenario: Write attempted from a hook
- **WHEN** a hook calls a file write function
- **THEN** the call throws `not_supported` because `yagura.fs` has no write functions

#### Scenario: Path escape refused
- **WHEN** a hook calls `yagura.fs.readText("../../Windows/win.ini")`
- **THEN** the call throws `sandbox_violation` inside the hook, and no file outside the instance root is read

#### Scenario: Edit into a staged mod refused
- **WHEN** a hook returns a file edit for `@CF/config.cpp`, a path inside a staged mod link that resolves into the content store
- **THEN** the operation fails with `sandbox_violation` naming the path, and no content-store file changes

#### Scenario: Edit through a link refused
- **WHEN** a hook returns a file edit for `cfg/server.json` where `cfg` is a junction to a directory outside the instance root
- **THEN** the operation fails with `sandbox_violation` naming the path, and no file outside the instance root changes

#### Scenario: Edit in an unsupported format
- **WHEN** `onPreStart` returns a file edit with `format: toml`
- **THEN** the operation fails with `unsupported_in_this_version` naming the edit's path and format, and no file changes
