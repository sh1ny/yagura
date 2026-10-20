# 0015. Game servers run under a dedicated low-privilege account, with protected directory ACLs

- Status: accepted
- Date: 2026-10-18
- Supersedes: 0013

## Context
The daemon runs as LocalSystem to manage the firewall, services and secrets. Game servers are internet-facing and load third-party code (DayZ script mods, BepInEx, Oxide/Carbon). If they inherited LocalSystem, any server or mod exploit would own the host, including the daemon's secrets and CA key.

ADR 0013 fixed the account model but gave the instance directory a plain "`yagura-srv` modify" entry and left the ACL mechanism open. That lets a server rename its own instance directory away and plant a junction in its place, gives SteamCMD's account (ADR 0014) no access, and an ACL applied with a propagating call walks the server-controlled tree as SYSTEM.

It also replaces ADR 0012's statement that `service install` creates the game-server account and sets directory ACLs. Both are done by the service-mode daemon at every start, because only LocalSystem can keep the passwords in its own DPAPI scope (ADR 0011).

## Decision
The service-mode daemon (not the installer) creates two local accounts at every start, idempotently: `yagura-srv` for game servers and `yagura-steam` for SteamCMD (ADR 0014). Each has a random password from 32 CSPRNG bytes encoded to 64 characters that always include upper case, lower case, digits and symbols (to pass complexity policy), stored through the secret store (ADR 0011); `SeBatchLogonRight` granted; `SeDenyInteractiveLogonRight`, `SeDenyRemoteInteractiveLogonRight` and `SeDenyNetworkLogonRight` assigned; membership of Users only. At every start the daemon sets each account's password to the stored one (`NetUserSetInfo` level 1003) without a test logon, so a drifted password is repaired without a failed logon counting toward lockout; any other group membership is removed.

One logon module obtains a token with `LogonUserW(LOGON32_LOGON_BATCH)`, loads the account profile (`LoadUserProfileW`), builds its environment with `CreateEnvironmentBlock`, and starts the process with `CreateProcessAsUserW` on a dedicated window station and desktop whose ACLs grant the account SID (not the per-logon SID, so the ACL does not grow with each launch): `YaguraSrv\Default` for the relay and game server, `YaguraSteam\Default` for SteamCMD. Every profile load is balanced by `UnloadUserProfile`: the launcher unloads once the relay is started, before it exits, and the daemon after SteamCMD exits. A profile load is counted per `LoadUserProfileW` call and outlives its caller, so an unbalanced load keeps the hive loaded until reboot and the profile cannot be deleted (spike S2). The launcher (ADR 0009) uses it for game servers; the daemon uses it in-process for SteamCMD (ADR 0014). Logon failures surface as `launch_logon_failed`.

ACLs, all protected (no inheritance from above):
- Data directory (database, secrets, plugins, logs): SYSTEM and Administrators only. The accounts reach `<data>/steamcmd` and `<data>/instances` below it through the default "Bypass traverse checking" right, without listing or reading anything else.
- `<data>/steamcmd`: SYSTEM and Administrators full, `yagura-steam` modify.
- Instance roots (the default `<data>/instances` and roots added with `yagurad roots add`): SYSTEM and Administrators full, `yagura-srv` and `yagura-steam` traverse only. Only administrators can create or rename entries in a root.
- Each instance directory: SYSTEM and Administrators full; for each of `yagura-srv` and `yagura-steam`, one entry on the directory itself granting read and execute, list, add file, add subdirectory and `FILE_DELETE_CHILD`, but not `DELETE`, plus one `(OI)(CI)(IO)` modify entry for its contents. Neither account can rename or delete the instance directory.
- Content store: `yagura-srv` read and execute only.

In service mode, before anything is created in the data directory, the daemon creates it if it is absent, opens it with `FILE_OPEN_REPARSE_POINT` and without `FILE_SHARE_DELETE`, and exits `data_dir_not_protected` if it is a reparse point or its final path (`GetFinalPathNameByHandleW`) differs from the configured one. It keeps that handle open, so the directory cannot be renamed or replaced, and before the database is opened it sets the owner (Administrators) and the protected DACL through that handle. While its recorded data-directory layout version is below the current one (the version is read from `<data>/acl-layout`, and is taken as 0 unless that file is opened without following reparse points, is a regular file with one link, and is owned by SYSTEM or Administrators), it walks the data directory with the no-follow walk. The walk sets the DACL on `<data>/instances` itself but does not descend into it; instance directories get their own DACL and migration (below), once the database is open. For every other child it sets the owner to Administrators and writes the entries it inherits from its parent's new DACL (SYSTEM/Administrators; plus `yagura-steam` modify below `<data>/steamcmd` and `yagura-srv` read and execute below the content store), and sets the explicit DACLs of `<data>/steamcmd` and the content store on those directories themselves. A reparse point met there fails startup with `data_dir_not_protected` naming the path.

Every DACL is written, together with owner Administrators (`OWNER_SECURITY_INFORMATION`), with `SetKernelObjectSecurity` on a handle opened without following reparse points, which changes only that object. Inherited entries on existing children are written only by the daemon's no-follow walk, one handle at a time. The entries are set when an instance is created, or once at the first service start for an instance created earlier (M1 or a development daemon), tracked per instance as an ACL layout version; a reparse point met during that walk leaves the instance's layout unchanged and its launches failing until the admin removes it. Entries are never withdrawn.

Trust boundary: everything under an instance directory is writable by both accounts and untrusted to the daemon. Every daemon file operation there (binder, key copy, staging, snapshot, restore, delete, hook host reads, log tailing, `instance.json`) goes through a handle-relative walk that opens each component with `FILE_OPEN_REPARSE_POINT`, checks the root's final path against the stored directory, and fails with `sandbox_violation` on any reparse point other than the mod junctions recorded in instance-mod rows, which are re-verified against their expected target. Recursive delete and snapshot copy never descend into a reparse point. Before any signal, kill or re-attach, the daemon checks the target's token user and parentage; `relay.json` is not trusted on its own.

On Linux the daemon runs as root and servers run as the system user `yagura-srv` with the same directory rules.

Console (development) mode runs servers as the current user and manages no accounts or ACLs.

**Rejected: run servers as LocalSystem.** No account management, but every mod is host-root.

**Rejected: one account per instance.** Stronger isolation between instances, but account sprawl and ACL churn for a single-admin host; can be added later behind the same launcher.

**Rejected: apply ACLs with `SetNamedSecurityInfoW`/`SetSecurityInfo` or `icacls`.** They propagate inheritable entries through existing children, a SYSTEM tree walk that follows links in a server-controlled tree; `icacls` also adds localised output parsing.

**Reversal cost: high.** Directory ACLs, the content store and save-data paths all assume these accounts.

## Consequences
- Games that write to the user profile must be pointed into the instance (`data_paths`, ADR 0002); `yagura-srv` has a profile, but the daemon does not back it up.
- Instance directories can live only under administrator-configured roots.
- The first service start trusts the contents of an existing data directory and only re-protects them. Yagura targets a dedicated single-admin host; on a shared host the admin checks or removes an existing `%ProgramData%\Yagura` before the first service install.
- `yagurad service uninstall` keeps the accounts and their secret rows so a reinstall resumes; `--purge-accounts` removes them while no server runs.
