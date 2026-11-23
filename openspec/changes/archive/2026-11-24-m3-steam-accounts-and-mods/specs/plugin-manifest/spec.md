# Spec Delta

## ADDED Requirements

### Requirement: Plugin version changes re-validate instances
When a reload changes a plugin's version, the daemon SHALL run the optional `migrateSettings` hook for each instance of that plugin and re-validate the result. A stopped instance whose settings fail moves to `error` with `settings_invalid` (or `plugin_missing` if the plugin is gone). A running one keeps running with a `settings_invalid` flag, and its next start is refused.

#### Scenario: Removed setting migrated
- **WHEN** plugin `dayz` 1.1 renames setting `logs` to `verboseLogs` and its `migrateSettings` copies the value
- **THEN** after reload each DayZ instance has `verboseLogs` with the old value, records plugin version 1.1, and stays in its previous state

#### Scenario: Running instance after an invalidating reload
- **WHEN** a reload invalidates the settings of a running instance
- **THEN** the instance stays `running` with flag `settings_invalid` and a notice naming the fields, and a later Start fails with `invalid_state`

#### Scenario: Migration hook fails
- **WHEN** `migrateSettings` throws for an instance
- **THEN** that instance's stored settings are unchanged, it is marked `settings_invalid` with the hook error, and the other instances are still processed

#### Scenario: Settings no longer valid
- **WHEN** a reload makes `maxPlayers: 100` invalid (new maximum 80) for a stopped instance
- **THEN** the instance becomes `error` with `settings_invalid` naming `maxPlayers`, and starting it fails until the setting is fixed

## MODIFIED Requirements

### Requirement: Launch templates
The manifest SHALL declare the executable per OS and the launch arguments as templates over `settings`, `ports`, `paths`, `os`, `mods` (one ordered list per mod role) and `secrets` (top-level secret settings), supporting conditional entries and list joins. The daemon renders them at start into an argument list without passing through a shell. A `secrets` value reaches only the launched process, never a file.

#### Scenario: Conditional and joined arguments
- **WHEN** an instance with `logs: true` and the `string_list` setting `serverMods: ["@CF", "@VPP"]` is started from a manifest that adds `-dologs`, `-adminlog` and `-netlog` when `logs` is true and joins `serverMods` with `;` into `-mod=`
- **THEN** the rendered arguments contain `-dologs`, `-adminlog`, `-netlog` and `-mod=@CF;@VPP`, each as a separate argv entry

#### Scenario: Mod roles joined into arguments
- **WHEN** a DayZ instance with client mods `[@CF, @VPP]` and server mod `[@VPPAdminTools]` is started from a manifest that joins `mods.client` into `-mod=` and `mods.server` into `-serverMod=`
- **THEN** the rendered arguments contain `-mod=@CF;@VPP` and `-serverMod=@VPPAdminTools` as separate argv entries, and an empty role renders no entry

#### Scenario: Template references an unknown setting
- **WHEN** a manifest template uses `{{settings.doesNotExist}}`
- **THEN** the plugin is `rejected` at load with an error naming the template and the unknown path, rather than failing at start

#### Scenario: Secret outside the secrets namespace
- **WHEN** a manifest template uses `{{settings.rconPassword}}` for a `secret` setting, or `{{secrets.maxPlayers}}` for a setting that is not secret
- **THEN** the plugin is `rejected` at load with an error naming the template and the path

#### Scenario: Missing executable for this OS
- **WHEN** a plugin declares only a `linux` executable and the daemon runs on Windows
- **THEN** the plugin is listed with status `loaded` and `platforms: [linux]`, and creating an instance of it fails with `FAILED_PRECONDITION` reason `unsupported_platform`

### Requirement: Stop and health declarations
The manifest SHALL declare a stop strategy (`signal` or `kill`, with grace seconds) and a health check (`process` alive, `port` listening, or `log_match` regex on a declared log source), with a start timeout. `log_match` matches only lines written after the current start. In this version a plugin that declares stop strategy `rcon`, health `query`, or an `rcon` section is `rejected` at load with reason `unsupported_in_this_version` naming the field.

#### Scenario: Log-match health check
- **WHEN** a Valheim instance starts with health `log_match: "Game server connected"` on its log source `server`, whose file still holds that line from the previous run
- **THEN** the instance becomes `running` when the line is written during this run, not because of the old line

#### Scenario: Log file rewritten past its old size
- **WHEN** the previous run's log file is 40 KiB and still holds the match line, and the new run rewrites the file from the start past 40 KiB before the next poll
- **THEN** the instance becomes `running` on the new run's line

#### Scenario: Unsupported stop strategy
- **WHEN** a manifest declares `stop: {strategy: rcon}`
- **THEN** the plugin is `rejected` with reason `unsupported_in_this_version` naming `stop.strategy`

#### Scenario: Bindings and mods sections accepted
- **WHEN** the DayZ manifest declares `bindings` and `mods` sections that satisfy the v1 manifest schema
- **THEN** the plugin is `loaded`, and only an `rcon` section in it would be rejected

#### Scenario: Invalid health regex
- **WHEN** a manifest declares `log_match: "([unclosed"`
- **THEN** the plugin is `rejected` at load with an error naming `health.log_match` and the regex error
