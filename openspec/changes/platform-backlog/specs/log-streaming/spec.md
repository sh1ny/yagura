# Spec Delta

## Purpose

Makes every game server's logs readable live and with recent history from the desktop, whatever files and encodings the game uses.

## ADDED Requirements

### Requirement: Secrets masked in log streams
The daemon SHALL replace instance secret values of 6 or more characters, current and replaced within the last 24 hours, with `***` in followed lines, backlog lines and crash notices; shorter secrets are matched only as whole words.

#### Scenario: Password echoed by the server
- **WHEN** a server prints its RCON password at startup
- **THEN** streamed lines show `***` in its place

#### Scenario: Backlog and crash lines masked
- **WHEN** a crash notice and a backlog request include a line with the RCON password
- **THEN** both show `***` in its place

#### Scenario: No secrets set
- **WHEN** an instance has no secrets
- **THEN** lines are streamed unchanged
