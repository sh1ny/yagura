# Spec Delta

## Purpose

Lets an admin create game server instances from plugins, install and run them, and keeps their state correct and durable across operations, crashes and daemon restarts.

## ADDED Requirements

### Requirement: Import and export instances
The daemon SHALL export an instance as its directory's `instance.json` and SHALL import a directory containing a valid `instance.json` as a new instance, validating it like a create and listing the secrets that must be re-entered.

#### Scenario: Import a copied instance
- **WHEN** a client imports `D:/servers/dayz-main`, under a configured instance root and containing a valid `instance.json` for an installed plugin
- **THEN** a new instance is created in state `stopped` pointing at that directory with the game-server account's access set, and the response lists `rconPassword` as a secret to set

#### Scenario: Import with unknown plugin version
- **WHEN** the `instance.json` names plugin `dayz` version `3.0.0` and the installed plugin's settings schema rejects its settings
- **THEN** the import fails with `FAILED_PRECONDITION`, the error lists each invalid field, and no instance is created

## MODIFIED Requirements

### Requirement: Graceful stop per plugin strategy
Stopping SHALL follow the plugin's stop strategy (`rcon` command, `signal` (Linux SIGTERM / Windows Ctrl+C to the server's console), or `kill`), wait up to the grace period, then kill the process if it is still alive, and report which step ended it. This holds for servers started from the console and for servers the service started as the game-server account.

#### Scenario: Valheim saves on a signal stop
- **WHEN** a client stops a running Valheim instance started by `yagurad run --console` whose strategy is `signal`
- **THEN** the server receives Ctrl+C, its world save file is written before the process exits, and the result reports `stopped_by: graceful`

#### Scenario: Valheim saves on a signal stop from the service
- **WHEN** a client stops a running Valheim instance started by the installed service (server running as `yagura-srv`) whose strategy is `signal`
- **THEN** the server receives Ctrl+C, its world save file is written before the process exits, and the result reports `stopped_by: graceful`

#### Scenario: RCON unavailable during stop
- **WHEN** the stop strategy is `rcon` and the RCON session cannot authenticate
- **THEN** the daemon waits out the grace period, kills the process, and the result reports `stopped_by: kill` with reason `rcon_unavailable`

#### Scenario: Graceful RCON shutdown
- **WHEN** a client stops a running DayZ instance whose strategy is `rcon` with `#shutdown` and grace 60 s
- **THEN** the daemon sends `#shutdown` over RCON, the process exits within the grace period, and the operation result reports `stopped_by: graceful`

#### Scenario: Grace period exceeded
- **WHEN** the process is still alive when the grace period ends
- **THEN** the daemon kills the process, the instance becomes `stopped`, and the operation result reports `stopped_by: kill`
