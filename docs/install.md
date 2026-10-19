# Installing the daemon as a Windows service

`yagurad service` installs, changes, upgrades and removes the daemon as the Windows service `yagurad`. The service runs as LocalSystem, starts with the machine and is restarted by the service manager when it fails. Every command needs an elevated prompt (Run as administrator); without one it exits non-zero with `elevation_required` and changes nothing.

The service wrapper is [WinSW](../tool/winsw/README.md) (2.12.0, pinned by SHA-256). `service install` refuses a bundle whose WinSW is not that file (`bundle_invalid`).

## The bundle

Unpack the release to any folder. It holds `bin\yagurad.exe`, `lib\` (the native libraries the executable loads), `winsw\` (the wrapper and its configuration template) and, in a release, a `VERSION` file. Run `yagurad` from there:

```
cd <bundle>
.\bin\yagurad.exe service install
```

The command copies the bundle, so the unpacked folder can be deleted afterwards.

The install folder holds the files the service runs as LocalSystem, so the command protects it before it copies anything: SYSTEM and Administrators get full control, Users (and so the service accounts) read and execute only, the owner is Administrators, and the folder takes nothing from its parent. Each version folder gets the same protection, and the wrapper and the configuration are written as new files inside it. The folder is opened without following links, and a link in its place is refused (`install_dir_not_protected`).

A folder's creator owns it and can keep a handle that still changes its permissions, and protecting the folder afterwards does not revoke that handle. So the install never adopts a folder someone else made, empty or not. It creates the install folder itself, with its owner (Administrators) and its permissions set in the same call that creates it, so it is protected from the moment it exists. It refuses with `install_dir_not_protected`, changing and deleting nothing, when:

- a folder above the install folder, from the drive root down, is a link, is owned by anyone other than SYSTEM, Administrators or TrustedInstaller, or gives another principal the right to delete it, delete its children, change its permissions or take its ownership (or has an entry the check cannot read, such as a conditional one, which counts as giving everything). `%ProgramFiles%` and `%ProgramData%` pass; a folder that Users created (`D:\games`) or a path in a user profile does not. Rights to create new files and folders are not counted: Windows gives them to Users on a drive root and `%ProgramData%`, and they do not let a user replace a folder. On the drive root itself the right to delete is not counted either, because a volume root cannot be deleted or renamed; a default `D:\` (Authenticated Users with Modify) passes.
- the install folder is not on a local drive letter. A network path (`\\server\share\...`) or a `\\?\` path is refused, because the owner and permissions it shows are the server's, not this host's. Only local drives such as `C:\` and `D:\` are supported. A folder above with no permissions list at all (a NULL DACL) counts as open to everyone and is refused too.
- the install folder exists already, unless an earlier install of yagurad protected it (owner Administrators and exactly the permissions above), checked on the handle the install then works through. Move the files away or give `--install-dir` a folder that does not exist yet; the command deletes nothing of yours. This holds even when the folder is empty.
- someone creates the install folder between the check and its creation.

A folder that an earlier install protected is used again, so a reinstall after `uninstall` works. The guarantee for `--install-dir` is therefore: either the folder and everything above it can be changed only by administrators, or the command stops before it writes anything.

## Install

`yagurad service install` copies the bundle into `%ProgramFiles%\Yagura\<version>\`, writes the wrapper and its configuration beside it, registers the service, starts it and waits up to 60 seconds for the daemon to answer on the admin channel. When it returns the service is running.

| Option | Meaning |
|---|---|
| `--bind <address:port>` | Where the API listens. Default `0.0.0.0:7443` |
| `--data-dir <path>` | The data directory ([data-directory.md](data-directory.md)). Default `%ProgramData%\Yagura`. A relative path is made absolute from the current folder |

The paths and the bind go into the service's command line, where the wrapper expands `%NAME%`. A `%` or a `"` in `--install-dir` or `--data-dir` is refused with `path_invalid`, and a bind with whitespace, a quote or a `%` with `bind_invalid`.

```
yagurad service install
yagurad service install --bind 192.168.1.20:7443 --data-dir D:\yagura
```

The command ends by printing the next step: pairing a device.

```
yagurad pair
```

`yagurad pair` prints a pairing string, `yagura://<host>:<port>?code=<CODE>&ca=sha256:<64 hex>&name=<name>`. Enter it in the desktop client within 10 minutes; see [data-directory.md](data-directory.md) for the other admin commands.

The first start of the service trusts a data directory that already exists. On a host where a `--dev` daemon has run, give the service the data directory you want it to use with `--data-dir`, and read the secret-store notes in [data-directory.md](data-directory.md): secrets that the dev daemon protected for its own account are deleted at the first service start.

## Status

`yagurad service status` prints the service state, the version and bind it is configured with and, when it runs, what the daemon reports.

```
yagurad service status
```

## Configure

`yagurad service configure --bind <address:port>` changes the API bind for the next start of the service. It checks that the port is not used by one of the game servers (`port_conflict` names the instance), and it does not restart anything. Restart the service when you want the new bind to apply; running game servers keep running:

```
yagurad service configure --bind 0.0.0.0:7444
Restart-Service yagurad
```

## Upgrade

Run `yagurad service install` from the newer bundle. It copies the new version beside the old one, stops the service, points it at the new version and starts it again. The bind and data directory stay as they are (change the bind with `service configure`); passing `--bind` or `--data-dir` to an upgrade is refused with `service_exists`.

Running game servers are not stopped: they run under their own relay processes, and the new daemon re-attaches to them. The previous version's folder stays until the relays that run from it are gone; the daemon deletes it at a later start.

```
yagurad service install
```

Run from a bundle of the same version, or an older one, `service install` changes nothing and exits with `service_exists`.

A version folder is never deleted by an install. When the folder of the version being installed is already there (an earlier `service uninstall` kept it because game servers still run from it, or an install stopped half way), the install reuses it: files that match the bundle are left alone, differing ones are replaced, and a differing file that is locked fails with `install_failed` naming it. Each folder an install makes holds a `.yagura-install` file with the service name; the service deletes only folders that carry its own name, and `install` refuses a folder with another name or with files and no marker.

## Uninstall

`yagurad service uninstall` stops and removes the service and its files. It leaves the data directory, the accounts the daemon made and running game servers alone. A file it cannot delete (the wrapper may still be exiting; it tries a few times) or a version folder that running servers execute from is reported as `kept` and left; the command still succeeds. Reinstalling the same version reuses a kept version folder.

```
yagurad service uninstall
```

`yagurad service uninstall --purge-accounts` also deletes the local accounts the daemon made for itself, their profiles and the stored passwords. It reads the data directory from the service's configuration before anything is removed, so the stored passwords go from the database the service used, wherever `--data-dir` put it. It refuses while a game server runs (`servers_running`, naming them) and changes nothing then; it looks again after the service has stopped, and when a server started meanwhile it starts the service again and refuses. An account whose profile is still in use, or whose stored password cannot be deleted, is kept, and the command fails with `profile_in_use`; run it again once that is resolved. If an earlier uninstall removed the service but left its configuration, `--purge-accounts` finishes the purge from that configuration. Only local user accounts named `yagura-srv` and `yagura-steam` are looked up; a domain account of that name is never touched.

```
yagurad service uninstall --purge-accounts
```

## Running a second service

Two options on every `service` command name a different service and install folder, for a test machine or a second daemon. Their defaults are the service `yagurad` and `%ProgramFiles%\Yagura`:

```
yagurad service install --service-name yagurad-test --install-dir D:\yagura-test
```

The two services share one install root unless `--install-dir` differs, and their version folders are told apart by the `.yagura-install` marker. Give each its own `--install-dir` anyway: the wrapper, the configuration and the logs are named after the service, but a second service of the same version cannot reuse a folder the first made.

The admin channel, and so `yagurad pair`, `yagurad status` and the readiness wait, has a fixed name: two services running at the same time cannot both serve it.

## Reasons

Failures print `yagurad: <reason>: <message>` and exit 1.

| Reason | Meaning |
|---|---|
| `elevation_required` | The prompt is not elevated |
| `bundle_invalid` | Not run from an unpacked bundle, or the bundle lacks the pinned WinSW or its template, or its `VERSION` is not a version |
| `service_exists` | The service is installed at this version or a newer one, or an upgrade was given `--bind` or `--data-dir` |
| `service_not_installed` | `configure`, `status` or `uninstall` with no service installed |
| `service_config_invalid` | The installed configuration is not one `yagurad` wrote (also for `uninstall --purge-accounts`, which needs it to know the data directory) |
| `bind_invalid` | The bind is not `address:port` with a port from 1 to 65535 |
| `port_conflict` | `configure` was given a port a game server uses |
| `install_dir_not_protected` | The install folder is not on a local drive letter, a folder above the install folder could be replaced by a user who is not an administrator, the install folder exists and no install of yagurad protected it (even if empty), someone created it first, or a link is in the way; nothing was changed |
| `install_failed` | The install folder could not be protected (a volume without ACLs, or a folder that cannot be created), copying the bundle failed (a differing file in a reused version folder is locked), or the version folder belongs to another service or to nothing of ours |
| `path_invalid` | `--install-dir` or `--data-dir` contains a `%` or a quote |
| `service_command_failed` | WinSW refused a command (a failed registration also removes the files the install copied); the message holds its output |
| `service_timeout` | The service did not reach the state in time |
| `service_not_ready` | The service runs but the daemon did not answer within 60 seconds; see the log under `%ProgramFiles%\Yagura\logs` and `yagurad service status` |
| `servers_running` | `--purge-accounts` while game servers run |
| `profile_in_use` | `--purge-accounts` kept an account because its profile is in use |
| `internal_error` | `--purge-accounts` could not read the database to tell whether game servers run (before the service was stopped nothing was changed; after it, the service is started again), or a file or Windows call failed in a way the other reasons do not name; the message holds the error |

The commands that ask the running daemon (`configure`, `status`, the readiness wait of `install` and the check of `--purge-accounts`) also pass on the reasons of the admin channel: `access_denied`, `admin_channel_untrusted`, `admin_channel_busy`, `admin_request_timeout`, `admin_connection_closed` and `admin_api_unsupported`. [data-directory.md](data-directory.md) explains each.
