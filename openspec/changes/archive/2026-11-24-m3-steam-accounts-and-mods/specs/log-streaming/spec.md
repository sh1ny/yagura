# Spec Delta

## ADDED Requirements

### Requirement: Secrets masked in log streams
The daemon SHALL replace an instance's secret values of 6 or more characters, current ones and ones replaced within the last 24 hours, with `***` in followed lines, backlog lines and crash notices. Shorter secrets SHALL be matched only as whole words.

#### Scenario: Password echoed by the server
- **WHEN** a server prints its RCON password at startup
- **THEN** streamed lines show `***` in its place

#### Scenario: Backlog and crash lines masked
- **WHEN** a crash notice and a backlog request include a line with the RCON password
- **THEN** both show `***` in its place

#### Scenario: Replaced secret still masked
- **WHEN** the RCON password was replaced 2 hours ago and a log line contains the old value
- **THEN** the line shows `***` in its place

#### Scenario: Short secret inside a word
- **WHEN** an instance's 4-character secret `ab12` appears inside the word `xab12y` and on its own
- **THEN** only the standalone occurrence is replaced with `***`

#### Scenario: No secrets set
- **WHEN** an instance has no secrets
- **THEN** lines are streamed unchanged
