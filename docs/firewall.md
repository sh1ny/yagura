# Firewall rules

In service mode the daemon opens the ports of its game servers and its own API port in Windows Firewall, and closes them again. It does this by reconciling the rules it owns with what the instances need (design D11). A development daemon (`--dev`) manages no rules and reports `firewall` in `GetHealth.not_built`.

## What the daemon owns

Every rule it makes is inbound, allow, and in the rule group `Yagura`. Its name says whose it is:

| Rule name | Opens |
|---|---|
| `Yagura/<instance-id>/<port-name>/<protocol>` | One port of an instance, for example `Yagura/inst-0123456789ab/game/udp`. `<instance-id>` is `inst-` and 12 hex digits, `<port-name>` is the name in the plugin manifest, `<protocol>` is `tcp` or `udp` |
| `Yagura/daemon/api/tcp` | The API port of the daemon (`--bind`) |

A rule is the daemon's only when its name matches that scheme exactly, case included, and it is in the group `Yagura`. The display name is for people and carries no meaning.

An instance gets one rule per port the plugin exposes. The rcon port is closed by default: it has a rule only when an administrator exposes it in the instance settings. While a server runs, its rules follow the ports it was launched with, not the saved settings, so a port change takes effect in the firewall when the server restarts.

## What is never touched

- Rules outside the group `Yagura`, whatever their name. A rule you made for a game server by hand stays as it is.
- Rules inside the group `Yagura` whose name is not in the scheme. They are reported (`Firewall.ListRules` shows them as not managed) and left alone.
- Rules whose name differs from the scheme only in case. Windows compares names without case; the daemon does not.
- The firewall profile, the default policy and the state of the firewall service.

If you open a port by hand and the daemon also owns a rule for it, both stay; deleting the daemon's rule is the daemon's business, yours is yours.

## When rules change

The daemon reconciles at startup, after an instance is installed, started, stopped or deleted, after a settings change or a crash, and when a client calls `Firewall.Reconcile`. `yagurad service install` makes the API port rule, and `yagurad service uninstall` removes it (the rules of instances stay while their data does). There is no periodic retry: a rule deleted by hand comes back at the next trigger, not before.

Reconciles run one at a time, each with one PowerShell run and a 30 second limit. The daemon hands the run its request in a file with a random name in `<data>	mp`, which only SYSTEM and Administrators can write (it is under the protected data directory), and deletes the file when the run ends; `yagurad service install` does the same in a `tmp` folder of the install folder and removes the folder again. A run that fails or times out deletes nothing. An operation waits for its reconcile for at most 60 seconds and then finishes anyway with the warning `firewall_unavailable`.

## When the firewall is unavailable

`firewall_unavailable` means the daemon could not read or change the rules: the Windows Firewall service is stopped, PowerShell did not answer in time, or a rule could not be set. Nothing was deleted. It appears as

- a warning on an operation (install, start, stop, delete) that finished without its rules in place,
- a startup notice with step `firewall`,
- a printed warning from `yagurad service install` or `uninstall` that names the rule, with the service installed and running regardless,
- the error of `Firewall.Reconcile` when it fails as a whole.

## Seeing the degraded state

| Where | What it says |
|---|---|
| `GetHealth.firewall_ok` | False when the last reconcile left a rule as it was not wanted |
| `Instance.firewall_status` | `ok`, `degraded` (a rule of this instance is not as wanted) or `disabled` (no firewall in this mode) |
| `yagurad status` | `api_port_rule: present` or `degraded` (`not_managed` in dev mode) |
| `Firewall.ListRules` | Every wanted and every existing rule of the group, with whether the daemon owns it and whether it is present |

To look at the rules yourself, in an elevated PowerShell: `Get-NetFirewallRule -Group Yagura`. To repair, fix the cause (start the Windows Firewall service, `mpssvc`) and call `Firewall.Reconcile` or restart the service.
