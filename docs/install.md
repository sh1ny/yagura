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

## Install

`yagurad service install` copies the bundle into `%ProgramFiles%\Yagura\<version>\`, writes the wrapper and its configuration beside it, registers the service, starts it and waits up to 60 seconds for the daemon to answer on the admin channel. When it returns the service is running.

| Option | Meaning |
|---|---|
| `--bind <address:port>` | Where the API listens. Default `0.0.0.0:7443` |
| `--data-dir <path>` | The data directory ([data-directory.md](data-directory.md)). Default `%ProgramData%\Yagura` |

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

## Uninstall

`yagurad service uninstall` stops and removes the service and its files. It leaves the data directory, the accounts the daemon made and running game servers alone.

```
yagurad service uninstall
```

`yagurad service uninstall --purge-accounts` also deletes the local accounts the daemon made for itself, their profiles and the stored passwords. It refuses while a game server runs (`servers_running`, naming them) and changes nothing then. An account whose profile is still in use is kept, and the command fails with `profile_in_use`; run it again once the processes using it have ended.

```
yagurad service uninstall --purge-accounts
```

## Running a second service

Two options on every `service` command name a different service and install folder, for a test machine or a second daemon. Their defaults are the service `yagurad` and `%ProgramFiles%\Yagura`:

```
yagurad service install --service-name yagurad-test --install-dir D:\yagura-test
```

The admin channel, and so `yagurad pair`, `yagurad status` and the readiness wait, has a fixed name: two services running at the same time cannot both serve it.

## Reasons

Failures print `yagurad: <reason>: <message>` and exit 1.

| Reason | Meaning |
|---|---|
| `elevation_required` | The prompt is not elevated |
| `bundle_invalid` | Not run from an unpacked bundle, or the bundle lacks the pinned WinSW or its template, or its `VERSION` is not a version |
| `service_exists` | The service is installed at this version or a newer one, or an upgrade was given `--bind` or `--data-dir` |
| `service_not_installed` | `configure`, `status` or `uninstall` with no service installed |
| `service_config_invalid` | The installed configuration is not one `yagurad` wrote |
| `bind_invalid` | The bind is not `address:port` with a port from 1 to 65535 |
| `port_conflict` | `configure` was given a port a game server uses |
| `install_failed` | Copying the bundle failed |
| `service_command_failed` | WinSW refused a command (a failed registration also removes the files the install copied); the message holds its output |
| `service_timeout` | The service did not reach the state in time |
| `service_not_ready` | The service runs but the daemon did not answer within 60 seconds; see the log under `%ProgramFiles%\Yagura\logs` and `yagurad service status` |
| `servers_running` | `--purge-accounts` while game servers run |
| `profile_in_use` | `--purge-accounts` kept an account because its profile is in use |
| `internal_error` | `--purge-accounts` could not read the database to tell whether game servers run; nothing was changed |
