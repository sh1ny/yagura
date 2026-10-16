# 0012. Windows host integration: WinSW service and group-owned firewall rules

- Status: accepted
- Date: 2026-10-16
- Supersedes: —

## Context
On Windows the daemon must start at boot without a logged-in user, run elevated enough to create symbolic links and firewall rules, and open the ports each instance declares. Dart cannot easily implement a Windows service entry point (`StartServiceCtrlDispatcher` blocks a native thread and calls back into the VM).

## Decision
The installer registers `garrisond.exe` as a service through a bundled WinSW 2.x wrapper (MIT) running as LocalSystem, with restart-on-failure. `garrisond service install|uninstall|status` drive it; install also creates the game-server account (ADR 0013), sets directory ACLs and adds a `Garrison/daemon/api/tcp` firewall rule for the daemon's own port. Other CLI verbs (`pair`, `devices`, `status`) talk to the running service over a local admin channel: a named pipe `\\.\pipe\garrisond-admin` whose ACL allows only SYSTEM and Administrators (a Unix socket, mode 0600, owned by root on Linux). WinSW must not stop game servers on service stop: servers are launched outside the service's process tree (ADR 0009), and an M2 exit criterion proves a service stop and an upgrade leave them running. Firewall rules are created through PowerShell's NetSecurity cmdlets (`New-NetFirewallRule`, `Remove-NetFirewallRule`, `Get-NetFirewallRule`) with every rule in the group `Garrison` and named `Garrison/<instance-id>/<port-name>/<proto>`, so the daemon only ever touches rules it created. Desired rules are derived from instance ports; a reconcile at startup and after every port change creates missing rules and removes owned rules with no instance.

**Rejected: implement the service entry point through `dart:ffi` and win32 (`NativeCallable.listener` for the control handler).** Feasible and no extra binary, but more native code to own for little gain while WinSW works; it is the fallback if the M2 spike shows WinSW stopping servers.

**Rejected: COM `INetFwPolicy2` through FFI for firewall rules.** Faster than spawning PowerShell, but much more FFI code for an operation that runs a few times a day.

**Reversal cost: low.** Both sit behind host-integration interfaces.

## Consequences
- The install bundle carries WinSW and needs .NET Framework 4.x, present on supported Windows versions.
- Rules are visible and removable in Windows Defender Firewall under the Garrison group; a rule the admin deletes by hand is recreated at the next reconcile.
- Linux gets a systemd unit and a firewalld/ufw adapter behind the same interface later.
