# Spike: SteamCMD and Steam Guard with stdin closed

Task 1.1 of `m3-steam-accounts-and-mods` (design A1, D2, D3), run by the user on 2026-10-20 (the two install runs by the agent the same day, in `F:\spike\dl\steamcmd`, after the design review asked whether download output is held back too) on their Windows 11 Pro machine (10.0.26200) with two Steam accounts they control. SteamCMD build 1791918946, in fresh installations under `F:\spike\<kind>\steamcmd`, as the logged-in user.

## Setup

- **Script:** `tool/spikes/m3_steam_guard/steam_guard_spike.dart` (throwaway, no packages). It starts `steamcmd.exe` with stdin closed at once (end-of-file, as the daemon runs it) and records each output line with its offset from the start. A second watcher reads `logs/connection_log.txt` and `logs/console_log.txt` every 250 ms and records each new line when it first appears on disk (`log` lines). Runs are killed after 3 minutes; none was.
- **Secrets:** the password and code were typed with echo off and kept in memory only. Every recorded line has them and the username replaced. After each run every file under the installation (`logs/`, `config/` including `config.vdf`, everything else) was scanned for the password and the code in UTF-8 and UTF-16LE.
- **Accounts:** one with email Steam Guard; one with the Steam Mobile Authenticator. The authenticator account offered phone approval only, so the authenticator code kind was not run.

## Results

| Run | Command | Exit | Time | Outcome |
|---|---|---|---|---|
| bootstrap (both) | `+quit` | 7 | 10-12 s | SteamCMD updates itself and exits 7. Not a failure. |
| email, first login | `+login <user> <pass> +quit` | 5 | 4-5 s | Prompt printed, then `Steam Guard code:ERROR (Account Logon Denied)`. Ends at once; no wait on stdin. |
| email, with code | `+login <user> <pass> <code> +quit` | 0 | 7.9 s | `Steam Guard code provided.`, then `...to Steam Public...OK`. |
| mobile approval, approved | `+login <user> <pass> +quit` | 0 | 17-24 s | Completes in the same run once approved on the phone. |
| cached login | `+login <user> +quit` | 0 | 4.2 s | `Logging in using cached credentials.` ... `OK`. |
| cached login missing (expired, or never logged in) | `+login <user> +quit` | 5 | 1.3-1.5 s | `Cached credentials not found.`, `password:`, then `ERROR (Invalid Password)`. Ends at once; no loop. |
| install, first (agent, anonymous) | `+force_install_dir <dir>\app +login anonymous +app_update 896660 +quit` | 8 | 8.8 s | `ERROR! Failed to install app '896660' (Missing configuration)`, the known first-run failure (`missing_configuration`, retried once). |
| install, again (agent, anonymous) | the same | 0 | 65.3 s | Valheim dedicated server, 2,112,080,121 bytes: 30 progress lines, then `Success! App '896660' fully installed.` |

**Password and code in SteamCMD's files:** none, in all 10 runs (252 to 266 files each). D3's file scrub is not needed. The daemon's data-directory secret scan (task 11.1) still covers the installations.

## Output that tells the kinds apart

All lines are from stdout unless marked; `<user>` stands for the username.

- **Email code:** `This computer has not been authenticated for your account using Steam Guard.`, `Please check your email for the message from Steam, and enter the Steam Guard`, `Steam Guard code:ERROR (Account Logon Denied)`. `logs/connection_log.txt` adds `cannot call UpdateAuthSessionWithSteamGuardCode because we do not have a code available` and `'Account Logon Denied'`.
- **Mobile approval:** `This account is protected by a Steam Guard mobile authenticator.`, `Please confirm the login in the Steam Mobile app on your phone.`, `Waiting for confirmation...`. `logs/connection_log.txt` adds `Waiting for confirmation` every 5 s while it waits, then `PollAuthSessionStatus succeeded and has refresh token`.
- **Authenticator code:** not observed. With a mobile authenticator, SteamCMD asked for the phone approval, not for a code. The `guard_authenticator` pattern keeps SteamCMD's documented `Two-factor code:` prompt, unverified here.
- **Code accepted:** `Steam Guard code provided.` and `Logging in user '<user>' [U:1:0] to Steam Public...OK`.
- **Success:** `Logging in user '<user>' ... to Steam Public...OK` and `Waiting for user info...OK`.
- **Cached login missing:** `Cached credentials not found.` followed by `password:` (no password was passed). This is `reauth_needed` (`steam_reauth_required`), not a wrong password, although the line after it says `ERROR (Invalid Password)`.
- **Wrong password, rate limit, wrong code, denied approval:** not observed. Their patterns keep SteamCMD's documented wording (`Invalid Password` when a password was passed, `Rate Limit Exceeded`, `Invalid Login Auth Code` / `Two-factor code mismatch`), marked unverified in `steam/patterns.yaml`.

## Findings that change the design

1. **stdout is held back until exit.** Piped to the daemon, SteamCMD's console output arrives in one block when the process exits: every login line of a mobile approval carries the offset of the exit (17.1 s in the last run, the approval having come at about 16 s). A run waiting for a phone approval therefore shows nothing on stdout. `logs/console_log.txt` and `logs/connection_log.txt` are written live (the watcher saw each line within a second of SteamCMD writing it), and only `connection_log.txt` shows the wait (`Waiting for confirmation`). Design D2 "Mobile approval" is amended to raise the prompt from that log. The code kinds are unaffected: SteamCMD exits at once and the daemon classifies its stdout after exit.
2. **Email delivery can be slow.** The first email arrived more than 10 minutes after the first attempt. A code from an earlier attempt's email still completed a later login (entered 4 s after that attempt's prompt). The code wait in D2 and the steam-content spec is raised from 5 to 15 minutes.
3. **Download progress is held back too.** In the second install run, stdout gave the two banner lines at 1.4 s and all 41 other lines, the 30 progress lines and `Success!` included, at the exit (65.3 s). `logs/console_log.txt` is a live copy of stdout with a `[YYYY-MM-DD hh:mm:ss] ` prefix on each line: it had every progress line within a second of its timestamp, one every 2 s, and the `Success!` line. `content_log.txt` and `workshop_log.txt` have no progress lines. The daemon's 15-minute stall timer reads stdout only, so any SteamCMD download longer than 15 minutes is killed as `steam_stalled` today (M2 installs never ran that long). Design D15 (with D5 "Progress") is added: progress and the stall timer follow `console_log.txt`; the outcome still comes from stdout at exit.
4. **A killed run leaves no harm.** A run stopped with Ctrl+C left no SteamCMD process behind; the next run printed `Looks like steam didn't shutdown cleanly, scheduling immediate update check` and logged in normally.

## Timeouts in D2

- **Code kinds:** 15 minutes (corrected from 5, finding 2). The wait sits between runs, outside the login step's 10-minute cap.
- **Mobile approval:** 2 minutes, confirmed. The approvals came 16-21 s after the login started; SteamCMD polls every 5 s and did not give up on its own within the observed waits (up to 21 s). The 2-minute kill stays the daemon's bound.
- **Login step cap:** 10 minutes, unchanged. The longest login run was 24 s.

## Not covered

- An authenticator code, a wrong password, a wrong code, a rate limit and a denied or never-answered phone approval. The fake SteamCMD (task 1.2) models them from SteamCMD's documented wording, and `steam/patterns.yaml` marks those patterns unverified. Output that matches no pattern fails verbatim as `steam_unknown_error`, never retried.
- Workshop downloads (`+workshop_download_item`, optional scenario): not run. The fake SteamCMD's workshop wording stays modelled.

The raw reports are on the user's machine (`F:\spike\out-*`), not in the repository.
