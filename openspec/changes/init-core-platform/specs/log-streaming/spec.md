# Spec Delta

## Purpose

Makes every game server's logs readable live and with recent history from the desktop, whatever files and encodings the game uses.

## ADDED Requirements

### Requirement: Declared log sources
A plugin SHALL declare log sources, each a `stdout` capture or a file path pattern (templated, with globs) with an encoding (`utf-8`, `utf-16le`, `latin-1`) and a rotation mode (`newest` picks the most recently created matching file; `fixed` follows one path across truncation).

#### Scenario: Newest file followed after rotation
- **WHEN** DayZ starts and creates a new `DayZServer_x64_2026-10-16_18-00-00.RPT` while the previous RPT exists
- **THEN** the `rpt` source switches to the new file and emits a `file_switched` event with the new name

#### Scenario: Pattern matches nothing
- **WHEN** the instance runs and no file matches a source pattern for 60 s
- **THEN** the source reports status `waiting` with the pattern, and no error stops the instance

### Requirement: Encoding-aware decoding
The daemon SHALL decode each source with its declared encoding and SHALL replace undecodable bytes with U+FFFD rather than dropping lines.

#### Scenario: SCUM UTF-16 log
- **WHEN** a SCUM log source declared `utf-16le` receives new lines
- **THEN** clients receive the lines as correct text, not with interleaved NUL characters

#### Scenario: Invalid bytes
- **WHEN** a UTF-8 source contains an invalid byte sequence
- **THEN** the line is delivered with U+FFFD in place of the invalid bytes

### Requirement: Stdout captured to a file
For `stdout` sources the daemon SHALL capture the server's standard output and error into rotating files in the instance's log directory (10 MiB per file, 5 files), so lines written while the daemon is down are still delivered after it restarts.

#### Scenario: Stdout survives daemon restart
- **WHEN** the daemon restarts while a server whose log source is `stdout` keeps writing to it
- **THEN** after re-attach, clients receive the lines written while the daemon was down from the capture file

#### Scenario: Capture file rotation
- **WHEN** the capture file reaches 10 MiB
- **THEN** it rotates, at most 5 files are kept, and no line is split across the rotation in the stream

### Requirement: Bounded buffer and backlog
Each source SHALL keep the last 10,000 lines (at most 4 MiB) in memory. `Logs.Backlog` SHALL return up to 5,000 recent lines, refilling from the file tail after a daemon restart. A line longer than 64 KiB SHALL be cut at 64 KiB and delivered with `truncated: true`, and the rest of it up to the next newline discarded.

#### Scenario: Backlog after restart
- **WHEN** a client requests 500 backlog lines of a source right after a daemon restart
- **THEN** it receives the last 500 lines from the file in order

#### Scenario: Request above the limit
- **WHEN** a client requests 50,000 backlog lines
- **THEN** it receives 5,000 lines and a `truncated: true` marker

#### Scenario: Line without a newline
- **WHEN** a source receives 1 MiB of output without a newline
- **THEN** clients receive one 64 KiB line marked `truncated: true`, and the source stays within its memory bounds

### Requirement: Live follow with backpressure
`Logs.Follow` SHALL stream new lines for selected sources with source name, timestamp and sequence. A subscriber that falls more than 1,000 lines or 4 MiB behind SHALL receive a `dropped` marker with the count and continue from the newest lines.

#### Scenario: Live lines delivered
- **WHEN** a client follows the `rpt` source and the server writes a line
- **THEN** the client receives it within 1 s with source `rpt`

#### Scenario: Slow subscriber
- **WHEN** a client stops reading while 3,000 lines arrive
- **THEN** on resuming it receives a `dropped: 2000` marker followed by the newest lines, and other subscribers are unaffected
