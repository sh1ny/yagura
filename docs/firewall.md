# Firewall rules

In service mode the daemon opens the ports of its game servers and its own API port in Windows Firewall, and closes them again. It does this by reconciling the rules it owns with what the instances need (design D11). A daemon that manages no rules (a development daemon, `--dev`, or a daemon that finds a trusted Yagura daemon on the admin channel) reports `firewall` in `GetHealth.not_built`.

## What the daemon owns

Every rule it makes is inbound, allow, and in the rule group `Yagura`. Its name says whose it is:

| Rule name | Opens |
|---|---|
| `Yagura/<instance-id>/<port-name>/<protocol>` | One port of an instance, for example `Yagura/inst-0123456789ab/game/udp`. `<instance-id>` is `inst-` and 12 hex digits, `<port-name>` is the name in the plugin manifest, `<protocol>` is `tcp` or `udp` |
| `Yagura/daemon/api/tcp` | The API port of the daemon (`--bind`) |

A rule is the daemon's only when its name matches that scheme exactly, case included, and it is in the group `Yagura`. The display name is for people and carries no meaning.

An instance gets one rule per port the plugin exposes. The rcon port is closed by default: it has a rule only when an administrator exposes it for that instance (`UpdateSettings`, the `exposed` flag of the `rcon` port). While a server runs, its rules follow the ports it was launched with, not the saved settings, so a port change takes effect in the firewall when the server restarts.

## One service per host

A host runs one Yagura service, and the service manages the group `Yagura`: `yagurad service install` under a second name is refused (`another_service_installed`). The daemon checks the admin channel (`\\.\pipe\yagurad-admin`, a fixed name) as a safety net. When it cannot open the channel and a trusted Yagura daemon (a LocalSystem server) answers on it, that daemon manages the group and this one runs no reconciler: it reports a startup notice with step `firewall`, `GetHealth.firewall_ok` false, `not_built: firewall` and `firewall_status: disabled` on its instances, and creates, changes and deletes no rule. `service install` and `uninstall` likewise leave the API port rule alone while such a daemon answers, and print a line saying so. Any other failure to open the channel (a process that is not a Yagura daemon holds the name, or the pipe cannot be created) keeps the admin channel notice (`admin_channel_squatted` or the error), and the daemon manages the group as usual.

The daemon opens the admin channel before its startup reconcile, so it knows who holds it, and answers requests on it only when startup has finished: `yagurad status` and the readiness wait of `service install` see the daemon's own `api_port_rule` after its first reconcile. A request that arrives earlier waits about 3 seconds and is then refused with `daemon_starting`, without running; the readiness wait tries again.

## What is never touched

- Rules outside the group `Yagura`, whatever their name. A rule you made for a game server by hand stays as it is.
- Rules inside the group `Yagura` whose name is not in the scheme. They are reported (`Firewall.ListRules` shows them as not managed) and left alone.
- Rules whose name differs from the scheme only in case. Windows compares names without case; the daemon does not.
- The firewall profile, the default policy and the state of the firewall service.

If you open a port by hand and the daemon also owns a rule for it, both stay; deleting the daemon's rule is the daemon's business, yours is yours.

## When rules change

The daemon reconciles at startup, after an instance is installed, started, stopped or deleted, after a settings change or a crash, and when a client calls `Firewall.Reconcile`. `yagurad service install` makes the API port rule, and `yagurad service uninstall` removes it (the rules of instances stay while their data does). There is no periodic retry: a rule deleted by hand comes back at the next trigger, not before.

Reconciles run one at a time, each with one PowerShell run and a 30 second limit. The daemon hands the run its request in a file with a random name in `<data>\tmp`, which only SYSTEM and Administrators can write (it is under the protected data directory), and deletes the file when the run ends; `yagurad service install` does the same in a `tmp` folder of the install folder and removes the folder again. A run that cannot read the rules, or finds the Windows Firewall service stopped, deletes nothing. A run in which some rule could not be set or deleted still deletes the owned rules nothing wants, and reports the failed ones. A run stopped at its limit may have applied part of its changes (the script sets and creates before it deletes); the daemon waits for the run to end before it starts another, so two runs never overlap, and the next reconcile completes the work. An operation waits for its reconcile for at most 60 seconds and then finishes anyway with the warning `firewall_unavailable`.

## When the firewall is unavailable

`firewall_unavailable` means the daemon could not read or change the rules: the Windows Firewall service is stopped, PowerShell did not answer in time, or a rule could not be set. A failure to read the rules, or a stopped firewall service, deleted nothing; a rule that failed to change was reported and the others went on. It appears as

- a warning on an operation (install, start, stop, delete) that finished without its rules in place,
- a startup notice with step `firewall`,
- a printed warning from `yagurad service install` or `uninstall` that names the rule, with the service installed and running regardless,
- the error of `Firewall.Reconcile` when it fails as a whole.

## Seeing the degraded state

| Where | What it says |
|---|---|
| `GetHealth.firewall_ok` | False when the last reconcile left a rule as it was not wanted |
| `Instance.firewall_status` | `ok`, `degraded` (a rule of this instance is not as wanted) or `disabled` (this daemon does not manage the firewall: dev mode, or a trusted daemon already holds the admin channel) |
| `yagurad status` | `api_port_rule: present` or `degraded` (`not_managed` in dev mode) |
| `Firewall.ListRules` | Every wanted and every existing rule of the group, with whether the daemon owns it, whether it is present, and `in_step` (present and allowing the wanted port and protocol; a rule changed by hand lists the port it actually allows) |

To look at the rules yourself, in an elevated PowerShell: `Get-NetFirewallRule -Group Yagura`. To repair, fix the cause (start the Windows Firewall service, `mpssvc`) and call `Firewall.Reconcile` or restart the service.
