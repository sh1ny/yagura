# Spec Delta

## Purpose

Opens and closes the host firewall ports each instance needs, touching only rules Yagura created.

## ADDED Requirements

### Requirement: Owned rules derived from instance ports
For every exposed port of each installed instance, the daemon SHALL maintain one inbound allow rule per protocol in group `Yagura`, named `Yagura/<instance-id>/<port-name>/<protocol>`: for the ports the process was launched with while running, the saved ports otherwise. Rules may be scoped to the server executable (`firewall.program_scope`).

#### Scenario: Rules created after install
- **WHEN** a Valheim instance with exposed ports `game` 2456/udp and `query` 2457/udp finishes installing
- **THEN** the firewall has rules `Yagura/<id>/game/udp` and `Yagura/<id>/query/udp` allowing inbound UDP on those ports

#### Scenario: Firewall service unavailable
- **WHEN** creating a rule fails because the Windows Firewall service is stopped
- **THEN** the start continues, the operation result carries a `firewall_unavailable` warning, and the instance shows `firewall: degraded` until a reconcile succeeds

### Requirement: Only owned rules are changed
The daemon SHALL create, change and delete only rules in the `Yagura` group whose names follow its naming scheme, and SHALL never modify other rules, even ones covering the same ports.

#### Scenario: Admin's own rule untouched
- **WHEN** the admin has a rule "DayZ manual" for 2302/udp outside the Yagura group and an instance on 2302 is deleted
- **THEN** "DayZ manual" still exists unchanged

#### Scenario: Foreign rule inside the group
- **WHEN** a rule in the `Yagura` group has a name not matching the naming scheme
- **THEN** reconcile leaves it unchanged and reports it as `unmanaged` in `Firewall.ListRules`

### Requirement: Reconcile desired and actual rules
The daemon SHALL reconcile owned rules at startup, after any port change, after instance deletion and on request: create missing rules, update rules whose port or protocol differ, and delete owned rules with no matching instance port.

#### Scenario: Port change on a stopped instance
- **WHEN** a stopped instance's game port changes from 2456 to 2466
- **THEN** after reconcile its `game` rule allows 2466 and no owned rule allows 2456

#### Scenario: Port change on a running instance
- **WHEN** a running instance's game port changes from 2456 to 2466
- **THEN** the rule keeps allowing 2456 while the server runs, the instance shows `restart_required`, and the rule allows 2466 after the next start

#### Scenario: Rule deleted by hand
- **WHEN** the admin deletes `Yagura/<id>/game/udp` in the firewall UI and the daemon restarts
- **THEN** the rule is recreated by the startup reconcile and the reconcile result lists it as `recreated`

### Requirement: RCON ports closed by default
Ports with purpose `rcon` SHALL NOT be exposed unless the instance explicitly sets them exposed, because the daemon reaches RCON locally.

#### Scenario: Default RCON not exposed
- **WHEN** a DayZ instance with an `rcon` port is started with default settings
- **THEN** no firewall rule exists for the RCON port

#### Scenario: Exposed RCON with the firewall unavailable
- **WHEN** an instance sets `ports.rcon.exposed: true` while the firewall service is stopped
- **THEN** the setting is saved, no rule exists, and the instance shows `firewall: degraded`

#### Scenario: Admin exposes RCON
- **WHEN** the instance sets `ports.rcon.exposed: true`
- **THEN** a rule for the RCON port is created and the settings view marks the port as exposed

### Requirement: Daemon API port rule
Service install SHALL create an owned rule `Yagura/daemon/api/tcp` for the daemon's API port, and the reconciler SHALL keep it while the service is installed.

#### Scenario: Fresh host reachable after install
- **WHEN** the service is installed on a fresh host with port 7443
- **THEN** an inbound TCP rule for 7443 exists in the `Yagura` group

#### Scenario: Firewall unavailable at service install
- **WHEN** the firewall service is stopped during `service install`
- **THEN** the service is installed, the command warns that the API port rule is missing, and the reconciler creates it once the firewall is available

#### Scenario: Port changed
- **WHEN** the daemon's API port is changed to 8443 and the service restarts
- **THEN** the rule allows 8443 and no owned rule allows 7443
