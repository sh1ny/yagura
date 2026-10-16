# Spec Delta

## Purpose

Lets admins send commands to running game servers and watch their console through the game's remote console protocol, chosen by the plugin.

## ADDED Requirements

### Requirement: Plugin-declared RCON protocol
A plugin SHALL declare `rcon.protocol` as `battleye`, `source`, `webrcon` or `none`, with the port name and the setting holding the password. The daemon connects to the server locally on that port.

#### Scenario: Protocol selected from manifest
- **WHEN** a client opens the console of a running ARK:SA instance declaring `rcon.protocol: source`
- **THEN** the daemon connects with the Source RCON protocol to `127.0.0.1:<rcon port>` and authenticates with the instance's RCON password

#### Scenario: Plugin without RCON
- **WHEN** a client opens the console of an instance whose plugin declares `rcon.protocol: none`
- **THEN** the call fails with `FAILED_PRECONDITION` reason `rcon_not_supported`

### Requirement: One-shot commands
`Rcon.Execute` SHALL send one command to a running instance and return the server's response text, or fail with `timeout` after 10 s.

#### Scenario: Command answered
- **WHEN** a client executes `players` on a running DayZ instance
- **THEN** the response contains the BattlEye player list text

#### Scenario: Instance not running
- **WHEN** a client executes a command on a stopped instance
- **THEN** the call fails with `FAILED_PRECONDITION` reason `instance_not_running`

#### Scenario: Wrong password
- **WHEN** the server rejects the RCON password
- **THEN** the call fails with `PERMISSION_DENIED` reason `rcon_auth_failed`, and the daemon does not retry until the password setting changes

### Requirement: Shared session and console stream
The daemon SHALL keep at most one RCON session per instance, shared by all subscribers, and SHALL stream server-pushed messages (BattlEye server messages, WebRCON broadcasts) to every console subscriber with the sending device tagged on echoed commands.

#### Scenario: Two consoles share a session
- **WHEN** two clients open the console of the same instance
- **THEN** the daemon holds one RCON connection, and a command sent by one client appears in the other client's stream tagged with the sending device name

#### Scenario: Session drops
- **WHEN** the RCON connection drops while consoles are open
- **THEN** subscribers receive a `disconnected` event, the daemon reconnects with backoff from 1 s up to 30 s, and a `reconnected` event follows on success

### Requirement: Protocol keep-alives
Adapters SHALL send the protocol's keep-alive (BattlEye: an empty command packet at least every 40 s) so idle sessions are not dropped by the server.

#### Scenario: Idle BattlEye session kept
- **WHEN** a BattlEye console is open for 5 minutes with no commands
- **THEN** the session stays connected and no `disconnected` event is emitted

#### Scenario: Keep-alive unanswered
- **WHEN** three consecutive keep-alives get no acknowledgement
- **THEN** the session is treated as dropped and reconnected
