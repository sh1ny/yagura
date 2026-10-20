# Spec Delta

## Purpose

Lets a plugin run small JavaScript functions at fixed lifecycle points for game-specific steps the manifest cannot express, inside a sandbox that cannot stall the daemon or reach outside the instance.

## MODIFIED Requirements

### Requirement: Sandboxed host API
Hooks SHALL reach the system only through the `yagura` object: logging, read-only reading and listing inside the instance root (staged mod folders included), and parsing or serialising every supported config format (`json`, `ini`, `ue-ini`, `xml`, `vdf`, `dayz-cfg`, `kv`). Hooks SHALL NOT write files; the daemon applies the edits a hook returns through the config binder, atomically, only inside the instance root and never inside a staged mod. Hooks have no network, process, environment-variable or timer access.

#### Scenario: File edit returned and applied by the daemon
- **WHEN** `onPreStart` returns `{"files": [{"path": "cfggameplay.json", "format": "json", "patch": {"GeneralData": {"disableBaseDamage": true}}}]}`
- **THEN** the daemon applies the patch atomically, the file contains `disableBaseDamage: true` with all other keys and their order kept, and the next start reports no external edit for that file

#### Scenario: Reading a staged mod
- **WHEN** a hook calls `yagura.fs.readText("server/@CF/meta.cpp")` and `server/@CF` is a staged mod link recorded by the daemon
- **THEN** the call returns the file's content from the content store

#### Scenario: Edit in an unsupported format
- **WHEN** `onPreStart` returns a file edit with `format: toml`
- **THEN** the operation fails with `unsupported_in_this_version` naming the edit's path and format, and no file changes

#### Scenario: Write attempted from a hook
- **WHEN** a hook calls a file write function
- **THEN** the call throws `not_supported` because `yagura.fs` has no write functions

#### Scenario: Path escape refused
- **WHEN** a hook calls `yagura.fs.readText("../../Windows/win.ini")`
- **THEN** the call throws `sandbox_violation` inside the hook, and no file outside the instance root is read

#### Scenario: Edit into a staged mod refused
- **WHEN** a hook returns a file edit for `server/@CF/config.cpp`, a path inside a staged mod link that resolves into the content store
- **THEN** the operation fails with `sandbox_violation` naming the path, and no content-store file changes

#### Scenario: Edit through a link refused
- **WHEN** a hook returns a file edit for `cfg/server.json` where `cfg` is a junction to a directory outside the instance root
- **THEN** the operation fails with `sandbox_violation` naming the path, and no file outside the instance root changes
