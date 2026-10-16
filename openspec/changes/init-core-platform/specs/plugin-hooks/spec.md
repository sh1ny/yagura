# Spec Delta

## Purpose

Lets a plugin run small JavaScript functions at fixed lifecycle points for game-specific steps the manifest cannot express, inside a sandbox that cannot stall the daemon or reach outside the instance.

## ADDED Requirements

### Requirement: Hook points
The daemon SHALL call these optional hooks when `hooks.js` exports them: `onPostInstall`, `onPostUpdate`, `onPreStart` and `onPostStop` after the daemon's own work for that step. A missing export is skipped.

#### Scenario: Pre-start hook adds arguments
- **WHEN** `onPreStart` returns `{"args": ["-freezecheck"], "env": {"SteamAppId": "221100"}}`
- **THEN** the server is launched with `-freezecheck` appended after the manifest's arguments and `SteamAppId=221100` in its environment

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

### Requirement: Hook deadline
Each hook call SHALL be interrupted when it exceeds its deadline: 5 s by default, or the manifest's `hooks.timeout_seconds` up to 60 s. Interruption stops the script inside the engine and frees its runtime.

#### Scenario: Infinite loop interrupted
- **WHEN** `onPreStart` runs `while (true) {}` with the default deadline
- **THEN** the start operation fails with `hook_timeout` naming `onPreStart` within 7 s, and the daemon keeps answering other calls throughout

#### Scenario: Manifest deadline above the cap
- **WHEN** a manifest sets `hooks.timeout_seconds: 300`
- **THEN** the plugin is `rejected` at load with an error naming the field and the 60 s maximum

### Requirement: Hook memory cap
Each hook runtime SHALL be limited to 64 MiB of heap and a 1 MiB result; exceeding either fails the hook.

#### Scenario: Allocation beyond the cap
- **WHEN** a hook builds a 200 MiB string
- **THEN** the hook fails with `hook_out_of_memory`, the operation fails, and after 100 such hooks the daemon's resident memory is within 32 MiB of its level before them

#### Scenario: Oversized result
- **WHEN** a hook returns a result that serialises to 2 MiB
- **THEN** the operation fails with `hook_result_too_large`

### Requirement: Hook errors are reported with location
An exception thrown by a hook SHALL fail the operation with the hook name, the error message and the JavaScript stack (file and line), and SHALL be recorded in the operation history.

#### Scenario: Thrown error
- **WHEN** `onModsStaged` throws `new Error("missing cfg")` at `hooks.js:42`
- **THEN** the operation ends `failed` with `hook_error`, message `missing cfg`, and a stack containing `hooks.js:42`

#### Scenario: Syntax error at load
- **WHEN** `hooks.js` has a syntax error
- **THEN** the plugin is `rejected` at load with reason `hook_syntax_error` and the line, and no instance operation runs it

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

### Requirement: Hook host calls are bounded
Each host read or parse call SHALL handle at most 16 MiB and each list call at most 10,000 entries. At most 4 hooks run at once per host; time spent waiting for a worker does not count against a hook's deadline. After 2 hook workers fail to exit, hooks SHALL be refused until the daemon restarts.

#### Scenario: Large file read refused
- **WHEN** a hook reads a 100 MiB log file with `yagura.fs.readText`
- **THEN** the call throws `host_limit_exceeded` naming the 16 MiB limit

#### Scenario: Waiting for a worker
- **WHEN** 4 hooks are running and a fifth is requested with a 5 s deadline, and a worker frees after 8 s
- **THEN** the fifth hook runs with its full 5 s deadline

#### Scenario: Degraded hook runtime
- **WHEN** 2 hook workers stuck in native code have not exited after their watchdog fired
- **THEN** further hook calls fail with `hook_runtime_degraded` and `GetHealth` reports 2 leaked hook workers

#### Scenario: Directory listing within limit
- **WHEN** a hook lists `keys/` containing 40 files
- **THEN** it receives 40 entries with names and sizes
