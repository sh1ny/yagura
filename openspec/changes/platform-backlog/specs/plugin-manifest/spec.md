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
