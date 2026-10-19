# The data directory

Operator notes for the directory `yagurad` keeps its state in (`--data-dir`; the default is `%ProgramData%\Yagura` on Windows). One daemon holds it at a time through `yagurad.lock`.

| Item | Holds |
|---|---|
| `yagura.db` | The authoritative state (ADR 0008), including the `secrets` table |
| `yagura.db.bak-<N>` | Copy taken before a migration from schema version `N` |
| `plugins/` | Installed plugins |
| `instances/` | The default instance root |
| `snapshots/` | Snapshots taken before updates, restores and deletes |
| `steamcmd/` | SteamCMD installations |
| `logs/` | Daemon logs |

## Secret store

Secret values (the daemon's CA key, Steam passwords, RCON passwords, server passwords and tokens) are never written as text. The daemon protects each one with Windows DPAPI in user scope (ADR 0011) and keeps the blob in the `secrets` table of `yagura.db`. A client can set or delete a secret setting, and never reads one back.

Every row records the SID of the account whose DPAPI scope protected it (`scope_sid`). Only that account can open the blob, so a copy of the database or of a backup on another machine, or under another account, holds nothing readable.

### The scope rule

The service runs as LocalSystem (`S-1-5-18`); a `--dev` daemon runs as the logged-in user. Each has its own scope, so the two cannot read each other's secrets. The daemon checks this while it starts, after the database is migrated and before anything else uses a secret:

- **Service mode.** Rows protected for any other account are deleted in one transaction. The daemon then creates again what it owns (the identity, if the CA key was among them, and the service-account passwords). No instance is lost. A secret setting that was among the deleted rows reads `{"secret": true, "set": false}` and has to be set again. Startup notice `secrets_reset` names each instance affected. If the CA key was deleted, every paired device must pair again.
- **Dev mode.** The daemon changes nothing. It exits non-zero with reason `secret_store_unavailable` in the `secret_store` step, naming both SIDs. Give a dev daemon its own `--data-dir` on a host where the service runs.

### Recovering

| You see | What happened | What to do |
|---|---|---|
| Notice `secrets_reset` after the service starts | The data directory was last used by a `--dev` daemon, was restored from another account's backup, or the service now runs as another account | Set the secret settings named in the notice again; pair devices again if the notice says the identity was re-created |
| `secret_store_unavailable` naming two SIDs when a dev daemon starts | The data directory holds secrets of the service (or of another user) | Start the dev daemon with a different `--data-dir`; do not delete `yagura.db` |
| `secret_store_unavailable` naming one error | DPAPI failed for the current account, for example because its profile cannot be loaded | Fix the account and restart; nothing was deleted |

### Another machine, and Linux

LocalSystem has the same SID (`S-1-5-18`) on every machine, but its DPAPI key belongs to one machine. A data directory moved or restored to another host therefore keeps matching `scope_sid` values whose blobs cannot be opened. To catch this, the service test-decrypts every row of its own scope once while it starts (the plaintext is cleared at once) and treats a row as foreign only when DPAPI fails with a wrong-key error (`NTE_BAD_KEY_STATE`, `NTE_BAD_DATA` or `ERROR_INVALID_DATA`, the errors for a blob that this key can never open). Such a row is handled like a row of another account: it is deleted, and `secrets_reset` names the instances affected. Any other DPAPI error stops the start with `secret_store_unavailable` naming the error, and nothing is deleted, so a temporary fault cannot cost the daemon's CA key. The service starts, keeps every instance, and the secret settings and daemon-owned secrets are set or created again. A dev daemon does not test-decrypt; it only refuses rows of another SID.

Linux has no secret store until M5: the store opens empty and refuses to hold a secret (`secret_store_unavailable`).

## Service accounts

In service mode (the Windows service, ADR 0013 and ADR 0015) the daemon runs as LocalSystem and creates two local accounts at every start, repairing them when they exist:

| Account | Runs | Can use |
|---|---|---|
| `yagura-srv` | Game servers, through the launcher | Its instance directories (modify, but not delete the directory itself), read and execute of the content store (M3; none exists in M2) and of the game files SteamCMD installed, traverse of the instance root |
| `yagura-steam` | SteamCMD, and the unpacking of its first download | `steamcmd/` (modify), its instance directories (as above) and traverse of the instance root |

Both are members of Users only, have a random 64-character password that the daemon keeps in its secret store (`service-account:<name>`), are allowed to log on as a batch job and are denied interactive, remote interactive and network logon. They get their own window station and desktop, so a game server and SteamCMD do not share one. Neither account can read `yagura.db`, the secrets or the other account's files, and neither can reach the admin channel (it answers SYSTEM and Administrators only).

When an account cannot be set up the daemon reports `service_accounts` and runs degraded: it serves the API, but a game server or SteamCMD does not start. A start that cannot log an account on fails with `launch_logon_failed`, and the instance stays stopped.

### Protection of the data directory

Before the database opens, the service opens the data directory without following links, makes Administrators its owner and replaces its DACL: full control for SYSTEM and Administrators only, not inherited from the parent. Everything below inherits that, except `instances/` (traverse for the two accounts, entered only through the instance's own DACL), `steamcmd/` and `content/`, which carry their explicit entries. A `acl-layout` file records that this was done; it counts only when it is a plain file with one link, owned by SYSTEM or Administrators. A link anywhere in the walk stops the start with `data_dir_not_protected`, naming it, and nothing is written through it.

Older instance directories (made before the service existed) get their DACL once, at the first service start; a directory that cannot be updated is reported as `acl_migration_failed` on the instance and tried again at the next start.

**Shared hosts.** The first service start trusts a data directory that already exists: it cannot tell which files an earlier user put there. Create the data directory only as an administrator, or let the service create it. On a host where standard users can write to the chosen path, a user who planted files there before the first start keeps nothing they could change afterwards (the walk replaces their permissions and the owner), but the files themselves stay, so inspect a directory you did not create yourself.

## Admin commands

The commands that run on the host reach the running service over a local named pipe, the admin channel, and never open `yagura.db` themselves. Run them from an elevated prompt (Run as administrator). The service serves the pipe `\\.\pipe\yagurad-admin` with a descriptor that names only SYSTEM and Administrators, so no other account can open it. The pipe is created with `FILE_FLAG_FIRST_PIPE_INSTANCE`: if another process already serves the name, the service starts without the channel (startup notice and `GetHealth.admin_channel_ok` false, reason `admin_channel_squatted`) rather than share it. The CLI in turn checks, before it sends anything, that the pipe is served by a LocalSystem process, that the pipe object is owned by SYSTEM or Administrators (which a process id, reusable once the server is gone, cannot fake: only an administrator can make a pipe those own), and that the server process id read twice from the held handle is the same, so a squatter never sees a command. The service keeps one instance listening whatever clients do (a client that connects and hangs up at once costs nothing) and retries every second when it cannot make the next one; `GetHealth.admin_channel_ok` is false while no instance can take a client. The channel takes 4 clients at a time (a fifth waits), 64 KiB per message, and drops a client that sends nothing for 5 seconds. A dev daemon (`--dev`) has no admin channel.

What changes state is audited as the device `host-admin` (`System.ListAudit` shows it): `pair`, `devices revoke` and `roots add|remove`, including the reason when one is refused. Reading commands are not audited.

| Command | Does |
|---|---|
| `yagurad pair` | Issues a pairing code (valid 10 minutes; it replaces any earlier code) and prints the pairing string `yagura://<host>:<port>?code=<CODE>&ca=sha256:<64 hex>&name=<name>`. The host is the first non-loopback IPv4 address of the machine and the port is the API port |
| `yagurad pair --address <host>[:<port>]` | The same, with the host (and port) you give, for a machine reached by a name or through a gateway |
| `yagurad devices list` | One line per device: id, name, `active` or `revoked`, last seen, and who revoked it |
| `yagurad devices revoke <device>` | Revokes a device by id, or by name when one active device has it. The host may revoke the last device; the API refuses that (`last_device`) |
| `yagurad status` | The mode, data directory, API port, number of active devices and instances, and `admin_channel: ok` |
| `yagurad roots add <path>` | Makes an existing directory an instance root (see below) |
| `yagurad roots remove <path>` | Removes a root from the configuration while no instance lives in it |
| `yagurad roots list` | The default root (`<data>\instances`) and the roots added |

### Instance roots

Instances live under `<data>\instances` unless an administrator adds another root. `CreateInstance` with a `directory` accepts a path strictly below a root, never a root itself, and refuses anything else with `directory_not_allowed` without changing any ACL. Paths are compared by the name the file system gives the folder, not by their text: the case does not matter, an 8.3 short name is its long name, a junction or link in a folder above leads to its target, and a path with a component that ends in a dot or a space, contains one of `<>:"|?*`, or is a device path (`\\?\`) is refused with `directory_not_allowed`, because Windows would read it as another path (`<root>\...` is the root, `C:\...` is the drive). There is no API method to add or remove a root; only these commands do.

`roots add` first replaces the DACL of the directory (ADR 0015): protected, owner Administrators, full control (inherited) for SYSTEM and Administrators, and traverse only for `yagura-srv` and `yagura-steam` where those accounts exist. They cannot create, rename or delete anything directly in the root, and nobody else can write to it. The command opens the directory itself, by handle and without following a link, and refuses a link as the root or in a folder above it, and anything that is not a directory; it holds that handle without `FILE_SHARE_DELETE` (nobody can delete or rename the folder meanwhile) and writes the owner and the DACL through it, so the folder that was checked is the folder that is protected. The root is stored under its real name. When the descriptor cannot be written (a volume without ACLs, a link, a missing path, no right to change it), the command fails with `root_not_protected` and the path is not a root. A drive, the data directory, anything inside it, and any path that nests with another root are refused with `directory_not_allowed`. Adding a root again, in another case or by its short name, is the same root: the descriptor is written again and nothing else changes; `roots remove` finds it in any case. Removing a root takes no ACL back: entries are never withdrawn. `roots remove` fails `root_in_use` and names the instances while one lives in the root.

### Reasons

| Reason | Meaning and what to do |
|---|---|
| `daemon_not_running` | Nothing serves the pipe. Start the service |
| `elevation_required` | You are an administrator but this prompt is not elevated. Run as administrator |
| `access_denied` | Your account is not an administrator; the pipe's descriptor refused it |
| `admin_channel_untrusted` | The pipe is served by a process that is not LocalSystem. Nothing was sent. Do not use it; find the process holding `\\.\pipe\yagurad-admin` |
| `admin_channel_squatted` | (Service startup notice) another process served the name first, so the service has no admin channel. Stop that process and restart the service |
| `admin_channel_busy` | All 4 slots stayed busy for 5 seconds. Run the command again |
| `admin_connection_closed` | The service closed the channel before the exchange ended |
| `admin_request_timeout` | The service waited 5 seconds for a request and dropped the connection |
| `admin_request_invalid` | The request was not a command the service knows, or an argument was malformed (for example a bad `--address`) |
| `admin_api_unsupported` | The CLI and the service speak different versions of the channel (`admin_api`). Use the CLI that came with the service |
| `admin_reply_invalid` | The reply was not a valid result or reason |
| `message_too_large` | A message was over 64 KiB |
| `port_conflict` | (Asked by `yagurad service configure`, see [install.md](install.md)) an instance uses the port proposed for the API; the message names it |
| `address_required` | The machine has no non-loopback IPv4 address; pass `--address` |
| `device_not_found` | No active device has that name or id |
| `device_ambiguous` | Several devices have that name; the message lists their ids, pass one |
| `device_name_invalid` | A device name was refused |
| `root_not_protected` | The directory could not be given the protected descriptor, so it was not made a root: it is missing, not a directory, a link (or behind one), or its descriptor cannot be written |
| `root_in_use` | An instance lives in the root; the message names it |
| `root_not_found` | The path is not an added root |
| `directory_not_allowed` | The path cannot be a root, or an instance directory is outside every root, equals a root, overlaps an instance, or has a component Windows would rewrite (a trailing dot or space, `:`, a device path) |
| `internal_error` | The command failed inside the service; see the daemon log |
