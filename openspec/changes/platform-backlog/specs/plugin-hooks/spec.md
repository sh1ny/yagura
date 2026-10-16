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
