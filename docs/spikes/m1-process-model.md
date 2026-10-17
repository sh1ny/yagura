# Spike: M1 process model on Windows

Task 1.3 of `init-core-platform` (ADR 0009, design D2), run on 2026-10-17 on a Windows 11 Pro machine (10.0.26200) and on the GitHub-hosted `windows-latest` runner.

## Setup

- **Prototype:** one throwaway Dart executable (`dart compile exe`, Dart 3.13.5) with the modes `parent`, `launch`, `relay`, `signal` and `stop`. It binds kernel32 with `dart:ffi` and uses no packages. It was not kept; the calls and flags that worked are listed below.
  - `parent` stands in for `yagurad run --console`: started in its own console window, it puts itself in a kill-on-close job, as the service wrapper will, then spawns `launch` and waits.
  - `stop` stands in for the daemon's stop: it spawns `signal` and waits for it.
- **Server:** Valheim dedicated server, app 896660, build 25909431, downloaded by hand with SteamCMD (`+login anonymous +app_update 896660 validate`).
- **Command line:** `valheim_server.exe -nographics -batchmode -name YaguraSpike -port 2456 -world YaguraSpike -public 0 -savedir <dir> -logFile <file>`. No `-password`.

## What worked

| Step | Call and flags |
|---|---|
| `launch` starts the relay | `CreateProcessW` with `CREATE_NEW_CONSOLE \| CREATE_BREAKAWAY_FROM_JOB \| CREATE_UNICODE_ENVIRONMENT`, `STARTF_USESHOWWINDOW` with `SW_HIDE`. No window appears; the console's `conhost.exe` is a child of the relay. `launch` writes `{relay_pid, relay_created}` (creation time from `GetProcessTimes`) and exits. |
| `relay` prepares its console | `SetConsoleCtrlHandler(NULL, FALSE)`, then a Ctrl+C handler that keeps the relay alive. `ProcessSignal.sigint.watch()` is enough: the relay saw every Ctrl+C sent to its console and stayed up. |
| `relay` starts the server | `CreateProcessW` with no console or group flags, so the server shares the relay's hidden console. Handles are inherited (`bInheritHandles`, `STARTF_USESTDHANDLES`). The spike sent the server's output to an inheritable file handle; the real relay uses pipes. |
| The daemon starts `signal` | `CreateProcessW` with `DETACHED_PROCESS`, then waits for it to exit. |
| `signal --console-of <pid>` | `FreeConsole`, `AttachConsole(pid)`, `SetConsoleCtrlHandler(NULL, TRUE)` (the helper only), `GenerateConsoleCtrlEvent(CTRL_C_EVENT, 0)`, exit 0. A Ctrl+C through the server's PID and one through the relay's PID behave the same once both share one console. |

## Verified on this machine

1. **Valheim starts with `-public 0` and no password.** It logs `Game server connected` 11 to 16 s after start.
2. **The world save's timestamps update before the process exits.**
   - Run 1: Ctrl+C at 09:47:26.03; save files written at 09:47:26.29; `exit.json` written at 09:47:28.82 with exit code 0.
   - Final run: Ctrl+C through the relay's PID at 09:58:49.35; save files written at 09:58:49.44 to 09:58:49.47; exit code 0 at 09:58:52.32.
3. **The server survives killing the prototype parent.** The parent was killed with `Stop-Process -Force`. Its kill-on-close job closed, and the relay and `valheim_server.exe` kept running outside it. After 20 s a Ctrl+C still stopped the server cleanly.
4. **Breakaway refused.** With the parent's job lacking `JOB_OBJECT_LIMIT_BREAKAWAY_OK`, `CreateProcessW` with `CREATE_BREAKAWAY_FROM_JOB` fails and no relay starts.
5. **Signal to a missing process.** `signal` against a PID that does not exist exits non-zero.

## Findings for group 5

- **Do not start the server with `dart:io` `Process.start`.** It gives the child its own console: the child gets its own `conhost.exe`. A Ctrl+C sent through the relay's PID then reaches only the relay, and the server keeps running. In the spike, two such Ctrl+Cs were ignored, 1 s and 20 s after the server was ready. The relay must call `CreateProcessW` itself, with pipes for stdout and stderr, as design D2 already says ("on the same console").
- **`GetLastError` is not reliable through plain `dart:ffi`.** It read 0 after the refused breakaway (expected `ERROR_ACCESS_DENIED`) and after a failed `AttachConsole`, because the VM can overwrite the thread's last error between the two calls.
  - **Breakaway:** `launch` cannot depend on the error code to report `launch_failed` naming breakaway. It reads its own job's limits instead: `IsProcessInJob`, then `QueryInformationJobObject(NULL, JobObjectExtendedLimitInformation)`. In a job without `JOB_OBJECT_LIMIT_BREAKAWAY_OK`, the failure names breakaway.
  - **`signal`:** it exits with a fixed non-zero code when the last error reads 0.
- **Set the server's working directory to its install directory.** Valheim finds its Steam app id in `steam_appid.txt` (892970) in the working directory, or in the `SteamAppId` environment variable. Without either it logs `Failed to find APPID`, `Steam is not initialized` and quits within 2 s with exit code **0**.
  - With the working directory set to the install directory, it logs `Using steam_appid.txt` and runs normally, so the manifest needs no environment variable.
  - The daemon starts every server with its install directory as the working directory; `docs/plugins/manifest.md` now says so.
- **Exit code 0 does not mean a clean stop.** Crash handling must keep keying on "exited without a stop request", as the spec does, not on the exit code.
- **Valheim spawns `UnityCrashHandler64.exe`** as a child of the server. It exited with the server in every run, and no process was left over.

## Valheim notes for task 9.1

- **Install (anonymous, app 896660):** build 25909431, `SizeOnDisk` 2,112,080,121 bytes. The first install took 72 s here.
- **Ready line:** `Game server connected`. `-logFile` with an absolute path inside the instance works.
- **Save layout under `-savedir`:**
  - `adminlist.txt`, `bannedlist.txt` and `permittedlist.txt`.
  - `worlds_local/<world>/`, holding `_main.<N>.chunks`, `_main.<N>.db2`, `_main.<N>.fwl2`, `_main.<N>.ok` and chunk files such as `00_00__0_<N>.chunk`. Each save writes generation N+1, then removes N.
  - So `data_paths` should name the save directory as a whole, not single files.
- **Graceful stop:** after Ctrl+C the save takes about 50 ms and the process exits within about 3 s.

## Windows CI runner

Three short runs (under 30 s each) on a throwaway branch with a Windows-only workflow; the branch was deleted afterwards.

- **Breakaway is not allowed from a step.** Each step runs inside a job with limit flags `0x0`: no `BREAKAWAY_OK`, no `SILENT_BREAKAWAY_OK`, no kill-on-close. `launch` straight from a step fails at `CreateProcessW`.
- **Task Scheduler does not escape either.** A task started with `schtasks /run` also runs in a job with flags `0x0`.
- **WMI does escape.** A process started with `Invoke-CimMethod Win32_Process -MethodName Create` is in no job. Started that way, the prototype parent passed the whole flow on the runner:
  - it created its own kill-on-close job with `BREAKAWAY_OK`;
  - the relay broke away;
  - the relay and server survived the parent being killed;
  - a Ctrl+C through the detached `signal` helper stopped the server (`ping`, exit `0xC000013A`, `STATUS_CONTROL_C_EXIT`).

### How the process tests run on CI

The daemon never drops `CREATE_BREAKAWAY_FROM_JOB`, and there is no test-only path that drops it.

- **On CI:** the Windows CI job starts the process tests in a `dart test` process created through WMI, which is outside the runner's job. That process writes the reporter output and the exit code to files. The step waits for the exit-code file, prints the output and fails with that code.
- **Locally:** the tests run directly.
- **Guard:** if the test process is in a job without `BREAKAWAY_OK`, the process tests fail at once with a message that says so, rather than with a bare `launch_failed`.
