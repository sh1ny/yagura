# Spec Delta

## Purpose

Opens and closes the host firewall ports each instance and the daemon API need, touching only the rules Yagura created.

## ADDED Requirements

### Requirement: Owned rules derived from instance ports
In service mode, for every exposed port of each installed instance, the daemon SHALL maintain one inbound allow rule per protocol in group `Yagura`, named `Yagura/<instance-id>/<port-name>/<protocol>`. While the server runs, the rules follow the ports it was launched with; otherwise they follow the saved ports. An instance in `not_installed` has no rules.

#### Scenario: Rules created after install
- **WHEN** a Valheim instance with exposed ports `game` 2456/udp and `query` 2457/udp finishes installing
- **THEN** the firewall has rules `Yagura/<id>/game/udp` and `Yagura/<id>/query/udp` allowing inbound UDP on those ports

#### Scenario: Not installed has no rules
- **WHEN** an instance is created and has not been installed
- **THEN** no owned rule names that instance

#### Scenario: Firewall service unavailable
- **WHEN** creating a rule fails because the Windows Firewall service is stopped
- **THEN** the operation continues, its result carries a `firewall_unavailable` warning, and the instance shows `firewall: degraded` until a reconcile succeeds

### Requirement: Only owned rules are changed
The daemon SHALL create, change and delete only rules in the `Yagura` group whose names follow its naming scheme, and SHALL never modify other rules, even ones covering the same ports.

#### Scenario: Admin's own rule untouched
- **WHEN** the admin has a rule "Valheim manual" for 2456/udp outside the Yagura group and an instance on 2456 is deleted
- **THEN** "Valheim manual" still exists unchanged

#### Scenario: Foreign rule inside the group
- **WHEN** a rule in the `Yagura` group has a name not matching the naming scheme
- **THEN** reconcile leaves it unchanged and `Firewall.ListRules` reports it as `unmanaged`

### Requirement: Reconcile desired and actual rules
In service mode the daemon SHALL reconcile owned rules at startup, after any port change, after an install, start, stop or deletion, and on request. Reconcile creates missing rules, updates rules whose port or protocol differ, deletes owned rules with no matching port, and reports each rule it created, updated, recreated or deleted.

#### Scenario: Port change on a stopped instance
- **WHEN** a stopped instance's game port changes from 2456 to 2466
- **THEN** after reconcile its `game` rule allows 2466 and no owned rule allows 2456

#### Scenario: Port change on a running instance
- **WHEN** a running instance's game port changes from 2456 to 2466
- **THEN** the rule keeps allowing 2456 while the server runs, the instance shows `restart_required`, and the rule allows 2466 after the next start

#### Scenario: Rule deleted by hand
- **WHEN** the admin deletes `Yagura/<id>/game/udp` in the firewall UI and the daemon restarts
- **THEN** the startup reconcile recreates the rule and its result lists it as `recreated`

#### Scenario: Dev mode manages no rules
- **WHEN** a `--dev` daemon installs an instance with exposed ports
- **THEN** no owned rule is created, and `GetHealth` lists `firewall` in `not_built`

#### Scenario: Reconcile times out
- **WHEN** the firewall does not answer a reconcile within 30 s
- **THEN** the reconcile fails with `firewall_unavailable`, no owned rule that is still wanted is deleted (a run stopped at its limit may already have applied part of its changes, which the next reconcile completes), affected instances show `firewall: degraded`, and the next reconcile runs normally

### Requirement: RCON ports closed by default
Ports with purpose `rcon` SHALL get no rule unless the instance explicitly sets them exposed, because the daemon reaches RCON locally.

#### Scenario: Default RCON not exposed
- **WHEN** an instance whose plugin declares an `rcon` port is installed with default settings
- **THEN** no firewall rule exists for the RCON port

#### Scenario: Admin exposes RCON
- **WHEN** the instance sets `ports.rcon.exposed: true`
- **THEN** a rule for the RCON port is created and the settings view marks the port as exposed

#### Scenario: Exposed RCON with the firewall unavailable
- **WHEN** an instance sets `ports.rcon.exposed: true` while the firewall service is stopped
- **THEN** the setting is saved, no rule exists, and the instance shows `firewall: degraded`

### Requirement: Daemon API port rule
Service install SHALL create an owned rule `Yagura/daemon/api/tcp` for the daemon's API port, and the reconciler SHALL keep it while the service is installed and the daemon runs without `--dev`.

#### Scenario: Fresh host reachable after install
- **WHEN** the service is installed on a fresh host with port 7443
- **THEN** an inbound TCP rule for 7443 exists in the `Yagura` group

#### Scenario: Firewall unavailable at service install
- **WHEN** the firewall service is stopped during `service install`
- **THEN** the service is installed, the command warns that the API port rule is missing, and the reconciler creates it once the firewall is available

#### Scenario: Port changed
- **WHEN** an administrator runs `yagurad service configure --bind 0.0.0.0:8443` and the service restarts
- **THEN** the rule allows 8443 and no owned rule allows 7443
