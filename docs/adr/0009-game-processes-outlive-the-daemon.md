# 0009. Game servers run under a relay, spawned outside the daemon's process tree

- Status: accepted
- Date: 2026-10-16
- Supersedes: —

## Context
Daemon upgrades, crashes and service restarts must not kick players. `dart:io` cannot do what this needs on Windows: `Process.start(mode: detached)` sets only `DETACHED_PROCESS` (no new process group, no job breakaway, stdio to NUL), and `detachedWithStdio` ties the pipes to the daemon. A service wrapper may stop the wrapped process's descendants, found by parent PID, when the service stops. Several target games have no RCON (Valheim, SCUM) and save only on a console Ctrl+C or on their autosave timer, so a stop that cannot deliver Ctrl+C loses progress. A re-attached process is not the daemon's child, so its exit code cannot be read through the usual handle.

## Decision
Game servers are started through a native spawn path (`CreateProcessW` / `CreateProcessAsUserW` through `dart:ffi` on Windows; on Linux, the relay starts in its own systemd transient scope (`StartTransientUnit`), so stopping `yagurad.service` does not kill it), never through `dart:io`:

1. The daemon runs `yagurad launch` (short-lived launcher) with `CREATE_BREAKAWAY_FROM_JOB` where allowed. The launcher starts the relay under the game-server account (ADR 0013) with `CREATE_NEW_CONSOLE` (hidden; session 0 has no visible desktop), reports the relay PID and creation time to the daemon on its stdout, and exits. This launcher report, not `relay.json`, is the source of the relay record. The relay's parent PID then points at a dead process, so tree-walking wrappers do not find it.
2. The relay (`yagurad relay`) starts the game server as its child sharing its console and process group, with stdout and stderr on pipes it owns. It writes them to rotating capture files, writes `relay.json` (relay PID, server PID, start times, executables) before anything else, and writes `exit.json` (exit code, time) when the server exits, then exits itself. The relay installs a console control handler that returns TRUE (never `SetConsoleCtrlHandler(NULL, TRUE)`, whose ignore flag the server would inherit) and starts the server without `CREATE_NEW_PROCESS_GROUP`.
3. Graceful stop without RCON: `yagurad signal --console-of <server pid>` (falling back to the relay pid) attaches to that console and calls `GenerateConsoleCtrlEvent(CTRL_C_EVENT, 0)`. The server receives Ctrl+C; the relay's handler swallows it.
4. Re-attach: on start the daemon matches recorded relay and server PIDs with their executables and start times; a mismatch is never treated as the server. The relay record comes from the launcher report. The server PID from `relay.json` is accepted only if its parent PID is the recorded relay and its token user is `yagura-srv`. Before any terminate, the daemon re-checks that the target's token user is `yagura-srv`. Exit is detected by a waiter per running instance (`WaitForSingleObject` on a handle opened with `SYNCHRONIZE`) and read from `exit.json`.

Games that write their own log files are configured to (Unity `-logFile`, DayZ profiles, ARK and SCUM `Saved/Logs`); stdout capture is the fallback, not the primary source. The manifest's executable must be the long-running server binary, not a bootstrapper that exits.

SteamCMD is the opposite case: it runs as a child in a kill-on-close job object owned by the daemon, so it dies with the daemon (ADR 0010).

**Rejected: `dart:io` detached processes.** No process group, no console, no stdio, no breakaway; graceful stop and log capture are impossible.

**Rejected: game servers as children killed with the daemon.** Simple cleanup, but every daemon restart is an outage.

**Rejected: redirect the server's stdout straight to a file handle.** No relay process, but the file cannot be rotated while the server holds it, and the exit code is lost after re-attach.

**Reversal cost: medium.** Contained in the process supervisor and two helper entry points of the same binary; the protocol is unaffected. Spikes: M1 proves Ctrl+C delivery to Valheim through the helper; M2 proves service stop and upgrade leave servers running under WinSW.

## Consequences
- One extra process (relay) per running server, a few MB each.
- `yagurad` has four entry modes: service/daemon, `launch`, `relay`, `signal`.
- Killing the relay by hand cuts the server's stdout pipe; the daemon reports the capture as broken, and file logs keep working.
