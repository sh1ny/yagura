# Spec Delta

## Purpose

Defines how a game is described to Yagura as data: plugin discovery, manifest validation and versioning, the settings schema the client renders, launch templates, ports, and stop and health declarations.

## ADDED Requirements

### Requirement: Plugin version changes re-validate instances
When a reload changes a plugin's version or settings schema, the daemon SHALL run the optional `migrateSettings` hook per instance and re-validate the result. A stopped instance whose settings fail moves to `error` with `settings_invalid` (or `plugin_missing` if the plugin is gone); a running one keeps running with a `settings_invalid` flag and its next start is refused.

#### Scenario: Removed setting migrated
- **WHEN** plugin `dayz` 1.1 renames setting `logs` to `verboseLogs` and its `migrateSettings` copies the value
- **THEN** after reload each DayZ instance has `verboseLogs` with the old value and stays in its previous state

#### Scenario: Running instance after an invalidating reload
- **WHEN** a reload invalidates the settings of a running instance
- **THEN** the instance stays `running` with flag `settings_invalid` and a notice naming the fields, and a later Start fails with `invalid_state`

#### Scenario: Migration hook fails
- **WHEN** `migrateSettings` throws for an instance
- **THEN** that instance's stored settings are unchanged, it is marked `settings_invalid` with the hook error, and other instances are processed

#### Scenario: Settings no longer valid
- **WHEN** a reload makes `maxPlayers: 100` invalid (new maximum 80) for a stopped instance
- **THEN** the instance becomes `error` with `settings_invalid` naming `maxPlayers`, and starting it fails until the setting is fixed

## MODIFIED Requirements

### Requirement: Launch templates
The manifest SHALL declare the executable per OS and the launch arguments as templates over `settings`, `ports`, `paths`, `mods` and `os`, supporting conditional entries and list joins. The daemon renders them at start into an argument list without passing through a shell.

#### Scenario: Conditional and joined arguments
- **WHEN** a DayZ instance with `logs: true` and client mods `[@CF, @VPP]` is started
- **THEN** the rendered arguments contain `-dologs`, `-adminlog`, `-netlog` and `-mod=@CF;@VPP`, each as a separate argv entry

#### Scenario: Template references an unknown setting
- **WHEN** a manifest template uses `{{settings.doesNotExist}}`
- **THEN** the plugin is `rejected` at load with an error naming the template and the unknown path, rather than failing at start

#### Scenario: Missing executable for this OS
- **WHEN** a plugin declares only a `linux` executable and the daemon runs on Windows
- **THEN** the plugin is listed with status `loaded` and `platforms: [linux]`, and creating an instance of it fails with `FAILED_PRECONDITION` reason `unsupported_platform`

### Requirement: Stop and health declarations
The manifest SHALL declare a stop strategy (`rcon`, `signal` or `kill`, with command and grace seconds) and a health check (`process` alive, `port` listening, `log_match` regex on a log source, or `query` via Steam A2S), with a start timeout. `log_match` matches only lines written after the current start.

#### Scenario: Log-match health check
- **WHEN** a Valheim instance starts with health `log_match: "Game server connected"` on its log source `server`, whose file still holds that line from the previous run
- **THEN** the instance becomes `running` when the line is written during this run, not because of the old line

#### Scenario: Log file rewritten past its old size
- **WHEN** the previous run's log file is 40 KiB and still holds the match line, and the new run rewrites the file from the start past 40 KiB before the next poll
- **THEN** the instance becomes `running` on the new run's line

#### Scenario: Invalid health regex
- **WHEN** a manifest declares `log_match: "([unclosed"`
- **THEN** the plugin is `rejected` at load with an error naming `health.log_match` and the regex error

#### Scenario: Unsupported stop strategy
- **WHEN** a manifest declares `stop: {strategy: telnet}`
- **THEN** the plugin is `rejected` with an error naming `stop.strategy` and the supported strategies
