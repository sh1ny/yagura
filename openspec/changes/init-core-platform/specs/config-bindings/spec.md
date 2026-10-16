# Spec Delta

## Purpose

Applies instance settings to game configuration files declared by the plugin, preserving everything the admin or the game wrote that Garrison does not own.

## ADDED Requirements

### Requirement: Bindings map settings to file keys
A binding SHALL name a file (relative to the instance root, templated), a format, a key path in that format, and a setting (or a structured setting and a mapping for `list`/`object` types). The daemon applies all bindings of an instance before `onPreStart` on every start and on `ApplyConfig`.

#### Scenario: Scalar binding applied
- **WHEN** an instance with `maxPlayers: 40` and a binding `{file: serverDZ.cfg, format: dayz-cfg, key: maxPlayers}` is started
- **THEN** `serverDZ.cfg` contains `maxPlayers = 40;` before the process is launched

#### Scenario: Bound file missing
- **WHEN** the bound file does not exist and the binding does not set `create: true`
- **THEN** the start fails with `binding_file_missing` naming the file and binding, and the process is not launched

#### Scenario: Missing file created from the plugin template
- **WHEN** the bound file does not exist and the binding sets `create: true` with `template: templates/serverDZ.cfg`
- **THEN** the file is created from the plugin's template and then patched

### Requirement: Supported formats
The daemon SHALL support the formats `ini`, `ue-ini` (Unreal: sections, repeated keys, `+`/`-` prefixed array entries, struct values in parentheses), `json`, `xml` (element and attribute paths), `vdf`, `dayz-cfg` (class blocks, `key = value;`, arrays in braces) and `kv` (one `key value` or `key=value` per line).

#### Scenario: Repeated UE keys from a list setting
- **WHEN** an ARK:SA `list` setting `itemStackOverrides` with two rows is bound to `Game.ini` `[/script/shootergame.shootergamemode]` key `ConfigOverrideItemMaxQuantity` with mode `repeat`
- **THEN** the section contains exactly two `ConfigOverrideItemMaxQuantity=(ItemClassString="...",Quantity=(MaxItemQuantity=...))` lines in row order and no other lines of that key

#### Scenario: Unknown format name
- **WHEN** a manifest binding declares `format: toml`
- **THEN** the plugin is `rejected` at load with an error listing supported formats

### Requirement: Round-trip preservation
Parsing and serialising a file without changes SHALL produce byte-identical output, and applying bindings SHALL change only the bound keys, keeping comments, blank lines, key order, unknown keys, line endings and encoding.

#### Scenario: Unchanged file stays identical
- **WHEN** bindings are applied with values equal to those in the file
- **THEN** the file's bytes and modification time are unchanged

#### Scenario: Comments and unknown keys survive
- **WHEN** `GameUserSettings.ini` has an admin comment and a key `MyCustomKey=1` and the binding changes `MaxPlayers`
- **THEN** only the `MaxPlayers` line differs from the original file

#### Scenario: Unparseable file
- **WHEN** a bound `cfggameplay.json` contains invalid JSON
- **THEN** the apply fails with `config_parse_error` naming the file, line and column, and the file is left unchanged

### Requirement: Manual edits are detected, not overwritten blindly
The daemon SHALL be the only writer of bound files and hook-requested edits, and SHALL record each file's content hash after applying. If a file changed since then, the next apply SHALL re-read it, apply only bound keys on top, never block the start, and emit an `external_edit` event naming bound keys it overwrote, unless the binding declares `game_writes: true`.

#### Scenario: Admin edit to an unbound key kept
- **WHEN** the admin adds `disableRespawnDialog = 1;` to `serverDZ.cfg` by hand and the instance is restarted
- **THEN** the line is still present after apply and no conflict is reported

#### Scenario: Admin edit to a bound key reported
- **WHEN** the admin changes `maxPlayers = 60;` by hand while the setting is 40, then starts the instance
- **THEN** the file has `maxPlayers = 40;`, the server starts, and an `external_edit` event lists `maxPlayers` with old value 60

#### Scenario: Secret values masked in the event
- **WHEN** a hand edit changed `RConPassword`, a key bound to a secret setting
- **THEN** the `external_edit` event lists `RConPassword` with old and new values shown as `***`

#### Scenario: Game rewrites its own config
- **WHEN** ARK:SA rewrites `GameUserSettings.ini` on shutdown and its bindings declare `game_writes: true`
- **THEN** the next start applies bound keys without an `external_edit` event

### Requirement: Writes are atomic
Each file write SHALL go to a temporary file in the same directory and replace the original atomically, so an interruption leaves either the old or the new file.

#### Scenario: Interrupted apply
- **WHEN** the daemon is killed while applying bindings to `Game.ini`
- **THEN** `Game.ini` is either fully the previous version or fully the new version, never truncated

#### Scenario: File locked by a running process
- **WHEN** the target file is locked by another process on Windows
- **THEN** the apply retries for up to 5 s and then fails with `file_locked` naming the file, leaving it unchanged
