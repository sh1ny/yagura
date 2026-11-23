# Spec Delta

## Purpose

Defines how a game is described to Yagura as data: plugin discovery, manifest validation and versioning, the settings schema the client renders, launch templates, ports, and stop and health declarations.

## MODIFIED Requirements

### Requirement: Stop and health declarations
The manifest SHALL declare a stop strategy (`rcon`, `signal` or `kill`, with command and grace seconds) and a health check (`process` alive, `port` listening, or `log_match` regex on a declared log source), with a start timeout. `log_match` matches only lines written after the current start. A plugin that declares health `query` is `rejected` at load with reason `unsupported_in_this_version` until a milestone builds it.

#### Scenario: Log-match health check
- **WHEN** a Valheim instance starts with health `log_match: "Game server connected"` on its log source `server`, whose file still holds that line from the previous run
- **THEN** the instance becomes `running` when the line is written during this run, not because of the old line

#### Scenario: Log file rewritten past its old size
- **WHEN** the previous run's log file is 40 KiB and still holds the match line, and the new run rewrites the file from the start past 40 KiB before the next poll
- **THEN** the instance becomes `running` on the new run's line

#### Scenario: Unsupported stop strategy
- **WHEN** a manifest declares `stop: {strategy: telnet}`
- **THEN** the plugin is `rejected` with an error naming `stop.strategy` and the supported strategies

#### Scenario: Bindings and mods sections accepted
- **WHEN** the DayZ manifest declares `bindings`, `mods` and `rcon` sections that satisfy the v1 manifest schema
- **THEN** the plugin is `loaded`

#### Scenario: Invalid health regex
- **WHEN** a manifest declares `log_match: "([unclosed"`
- **THEN** the plugin is `rejected` at load with an error naming `health.log_match` and the regex error
