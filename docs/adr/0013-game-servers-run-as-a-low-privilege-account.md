# 0013. Game servers run under a dedicated low-privilege account

- Status: accepted
- Date: 2026-10-16
- Supersedes: —

## Context
The daemon runs as LocalSystem to manage the firewall, services and secrets. Game servers are internet-facing and load third-party code (DayZ script mods, BepInEx, Oxide/Carbon). If they inherited LocalSystem, any server or mod exploit would own the host, including the daemon's secrets and CA key.

## Decision
`yagurad service install` creates a local account `yagura-srv` with a random 32-byte password (stored through the secret store, ADR 0011), denied interactive and remote logon, not a member of any admin group, and grants it "Log on as a batch job". The launcher (ADR 0009) obtains a token with `LogonUserW(LOGON32_LOGON_BATCH)` and starts the relay with `CreateProcessAsUserW`, so relay and server run as `yagura-srv`. The launcher loads the account profile (`LoadUserProfileW`), builds its environment with `CreateEnvironmentBlock`, and starts the relay on a dedicated window station and desktop `YaguraSrv\Default`, whose ACLs grant the account's logon SID, passed in `STARTUPINFO.lpDesktop`. ACLs:
- Instance directories: `yagura-srv` modify, SYSTEM and Administrators full.
- Content store: `yagura-srv` read and execute only.
- Data directory (database, secrets, SteamCMD, plugins, logs): SYSTEM and Administrators only.
Trust boundary: everything under an instance directory is writable by `yagura-srv` and untrusted to the daemon. Every daemon file operation there (binder, key copy, staging, snapshot, restore, delete, hook host reads, log tailing) opens paths without following reparse points (`FILE_FLAG_OPEN_REPARSE_POINT`, per-component check) and fails with `sandbox_violation` on any reparse point other than the mod junctions recorded in instance-mod rows, which are re-verified against their expected target. Recursive delete and snapshot copy never descend into a reparse point.

On Linux the daemon runs as root and servers run as the system user `yagura-srv` with the same directory rules.

Console mode (development, M1) runs servers as the current user.

**Rejected: run servers as LocalSystem.** No account management, but every mod is host-root.

**Rejected: one account per instance.** Stronger isolation between instances, but account sprawl and ACL churn for a single-admin host; can be added later behind the same launcher.

**Reversal cost: high.** Directory ACLs, the content store and save-data paths all assume this account.

## Consequences
- Games that write to the user profile must be pointed into the instance (`data_paths`, ADR 0002); `yagura-srv` has a profile, but the daemon does not back it up.
- Rotating the account password is a daemon command; LogonUser failures surface as `launch_logon_failed`.
