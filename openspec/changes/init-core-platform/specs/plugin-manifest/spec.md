# Spec Delta

## Purpose

Defines how a game is described to Yagura as data: plugin discovery, manifest validation and versioning, the settings schema the client renders, launch templates, ports, and stop and health declarations.

## ADDED Requirements

### Requirement: Plugin discovery and validation
The daemon SHALL load every folder under its plugins directory that contains `plugin.yaml`, validate it against the manifest JSON Schema for its `manifest_version`, and list each plugin as `loaded` or `rejected` with the reasons. A rejected plugin cannot be used for new instances.

#### Scenario: Valid plugin loaded
- **WHEN** the daemon starts with `plugins/valheim/plugin.yaml` that satisfies the v1 manifest schema
- **THEN** `ListPlugins` returns `valheim` with status `loaded`, its name, version and supported platforms

#### Scenario: Invalid manifest rejected with location
- **WHEN** `plugins/broken/plugin.yaml` has `ports[0].protocol: tcpp`
- **THEN** `ListPlugins` returns `broken` with status `rejected` and an error naming `ports[0].protocol`, the allowed values, and the file line

#### Scenario: Unknown manifest version
- **WHEN** a manifest declares `manifest_version: 2` and the daemon supports only version 1
- **THEN** the plugin is `rejected` with reason `unsupported_manifest_version` and the supported versions listed

### Requirement: Plugin size limits
The daemon SHALL reject a plugin whose `plugin.yaml` exceeds 256 KiB or whose `hooks.js` exceeds 1 MiB, before parsing it.

#### Scenario: Oversized hooks file
- **WHEN** `plugins/x/hooks.js` is 3 MiB
- **THEN** plugin `x` is `rejected` with reason `file_too_large` naming `hooks.js` and the 1 MiB limit

#### Scenario: Within limits
- **WHEN** `plugin.yaml` is 20 KiB and `hooks.js` is 40 KiB
- **THEN** the plugin is validated normally

### Requirement: Plugin reload without restart
The daemon SHALL reload plugins only on explicit request, never on file change. Instances whose plugin reloads successfully use the new manifest from their next operation; a running operation keeps the manifest it started with. If a plugin fails to reload, the previously loaded version stays active for existing instances and the failure is reported.

#### Scenario: Fixed manifest picked up
- **WHEN** an admin edits a launch argument in `plugins/valheim/plugin.yaml` and calls `ReloadPlugins`
- **THEN** the response lists `valheim` as `reloaded` and the next `Start` uses the new argument

#### Scenario: Broken edit keeps the old version
- **WHEN** the edited manifest no longer validates and `ReloadPlugins` is called
- **THEN** the response lists `valheim` as `reload_failed` with the errors, and existing Valheim instances keep starting with the previous manifest

### Requirement: Settings schema types and constraints
The manifest's `settings` SHALL support the types `string`, `integer`, `number`, `boolean`, `enum`, `secret`, `string_list`, `object` (nested fields) and `list` (repeatable rows of an object type), with `label`, `description`, `default`, `required`, `min`, `max`, `pattern`, `group` and `advanced`. The daemon serves this schema to clients and validates values against it.

#### Scenario: Repeatable structure validated
- **WHEN** an ARK:SA instance sets `itemStackOverrides` (type `list` of objects with `class: string`, `max: integer`) to two rows
- **THEN** the values are accepted and returned as an ordered array of two objects

#### Scenario: Row with missing required field
- **WHEN** a row in `itemStackOverrides` omits required `class`
- **THEN** validation fails with `INVALID_ARGUMENT` naming `itemStackOverrides[1].class`

### Requirement: Secret settings stay unset without a secret store
A `default` on a `secret` setting SHALL be rejected at load. This version has no secret store, so a value for a `secret` setting SHALL be refused with `FAILED_PRECONDITION` reason `secret_store_unavailable`, and secret settings stay unset.

#### Scenario: Secret values refused
- **WHEN** a client submits a value for a `secret` setting, when creating an instance or updating its settings
- **THEN** the call fails with `FAILED_PRECONDITION` reason `secret_store_unavailable`, nothing is saved, and reading the settings returns the field as `{"secret": true, "set": false}`

### Requirement: Launch templates
The manifest SHALL declare the executable per OS and the launch arguments as templates over `settings`, `ports`, `paths` and `os`, supporting conditional entries and list joins. The daemon renders them at start into an argument list without passing through a shell.

#### Scenario: Conditional and joined arguments
- **WHEN** an instance with `logs: true` and the `string_list` setting `serverMods: ["@CF", "@VPP"]` is started from a manifest that adds `-dologs`, `-adminlog` and `-netlog` when `logs` is true and joins `serverMods` with `;` into `-mod=`
- **THEN** the rendered arguments contain `-dologs`, `-adminlog`, `-netlog` and `-mod=@CF;@VPP`, each as a separate argv entry

#### Scenario: Template references an unknown setting
- **WHEN** a manifest template uses `{{settings.doesNotExist}}`
- **THEN** the plugin is `rejected` at load with an error naming the template and the unknown path, rather than failing at start

#### Scenario: Missing executable for this OS
- **WHEN** a plugin declares only a `linux` executable and the daemon runs on Windows
- **THEN** the plugin is listed with status `loaded` and `platforms: [linux]`, and creating an instance of it fails with `FAILED_PRECONDITION` reason `unsupported_platform`

### Requirement: Port declarations
Each declared port SHALL have a name, default number, protocol (`udp`, `tcp` or `both`), purpose (`game`, `query`, `rcon`, `web`, `other`) and whether it is exposed through the firewall (default true; RCON default false). Ports may be derived from another port with an offset.

#### Scenario: Derived port follows its base
- **WHEN** Valheim declares `query: {from: game, offset: 1}` and an instance sets `game` to 2466
- **THEN** the instance's `query` port is 2467

#### Scenario: Derived port collides
- **WHEN** a derived port lands on a port another instance uses
- **THEN** the settings change fails with `FAILED_PRECONDITION` naming both instances and the port

### Requirement: Stop and health declarations
The manifest SHALL declare a stop strategy (`signal` or `kill`, with grace seconds) and a health check (`process` alive, `port` listening, or `log_match` regex on a declared log source), with a start timeout. `log_match` matches only lines written after the current start. In this version a plugin that declares stop strategy `rcon`, health `query`, or a `bindings`, `mods` or `rcon` section is `rejected` at load with reason `unsupported_in_this_version` naming the field.

#### Scenario: Log-match health check
- **WHEN** a Valheim instance starts with health `log_match: "Game server connected"` on its log source `server`, whose file still holds that line from the previous run
- **THEN** the instance becomes `running` when the line is written during this run, not because of the old line

#### Scenario: Unsupported stop strategy
- **WHEN** a manifest declares `stop: {strategy: rcon}`
- **THEN** the plugin is `rejected` with reason `unsupported_in_this_version` naming `stop.strategy`

#### Scenario: Invalid health regex
- **WHEN** a manifest declares `log_match: "([unclosed"`
- **THEN** the plugin is `rejected` at load with an error naming `health.log_match` and the regex error

### Requirement: Save data paths stay inside the instance
The manifest SHALL declare `data_paths` (templated paths of save and player data); each must resolve inside the instance directory, so plugins pass the game's save-directory argument where needed.

#### Scenario: Valheim save directory inside the instance
- **WHEN** the Valheim plugin declares `data_paths: ["save/"]` and launches with `-savedir {{instance}}/save`
- **THEN** the rendered `-savedir` argument and the declared data path both resolve to the instance's `save/` directory

#### Scenario: Data path outside the instance
- **WHEN** a manifest declares `data_paths: ["{{instance}}/../shared"]`
- **THEN** the plugin is `rejected` at load with an error naming the path

### Requirement: Executable is the long-running server
The manifest's executable SHALL be the process that runs for the server's lifetime; launcher or bootstrapper executables that exit after spawning another process are not supported.

#### Scenario: Long-running executable tracked
- **WHEN** an instance starts an executable that keeps running until it is stopped
- **THEN** the recorded server PID stays alive for the whole run and its exit is detected

#### Scenario: Bootstrapper exits
- **WHEN** a manifest names a launcher executable that exits within 5 s while spawning the real server
- **THEN** the start fails with `launch_failed` as specified for the health window, naming the exited executable
