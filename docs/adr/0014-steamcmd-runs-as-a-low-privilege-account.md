# 0014. SteamCMD runs non-interactively as a low-privilege account; Steam Guard is relayed to the client

- Status: accepted
- Date: 2026-10-18
- Supersedes: 0010

## Context
Most target servers download anonymously (Valheim, Rust, ARK:SA, SCUM); DayZ's server and all DayZ workshop items need an account that owns the game. SteamCMD caches a successful login per installation; Steam Guard (email or mobile) may still ask for a code or an approval. SteamCMD's interactive prompts are unreliable through pipes on Windows.

ADR 0010 ran SteamCMD as the daemon's account (LocalSystem in service mode) and guarded `app_update` with a reparse-point scan of the instance tree before and after each run. That scan cannot close the race: every game server runs as the shared `yagura-srv` account (ADR 0015), so a server of another instance can plant a junction in an instance being updated while SteamCMD writes. SteamCMD then follows it as SYSTEM into system folders. SteamCMD has no no-follow mode.

## Decision
The daemon installs and owns SteamCMD (one installation per Steam account, so cached logins never collide) and runs it only with a full `+command` argument list ending in `+quit` (never a `+runscript` file, so the password never touches disk), stdin closed, inside a kill-on-close job object owned by the daemon so it dies with the daemon. One SteamCMD process runs per installation at a time; other requests queue.

In service mode every SteamCMD run (install, update, validate, and the `tar` extraction of the bootstrap archive) starts as a dedicated local account `yagura-steam`. The daemon itself calls `LogonUserW(LOGON32_LOGON_BATCH)` and `CreateProcessAsUserW`, with the profile, environment and desktop setup of ADR 0015, `CREATE_SUSPENDED`, and assignment to the operation's kill-on-close job before the process resumes; stdout and stderr go to pipes the daemon reads. It does not go through `yagurad launch`, whose job breakaway and early exit serve game servers (ADR 0009). SteamCMD runs on its own window station and desktop `YaguraSteam\Default`, ACL'd to the `yagura-steam` account SID, so no game server can hook or message SteamCMD's windows. `yagura-steam` can write `<data>/steamcmd`, instance directories through the entries ADR 0015 grants it, and what any standard account can write (its own profile, `C:\Users\Public`); it has nothing on system folders or the rest of the data directory, whose existing contents the daemon's data-directory walk (ADR 0015) strips of inherited `Users` entries. A link planted by a `yagura-srv` process can redirect SteamCMD's writes and deletes only to places `yagura-steam` may write. Writes into system folders and the rest of the data directory fail with access denied. SteamCMD installations and `yagura-steam`'s profile can still be reached. No tree scan runs before or after an update, and no ACL entry is withdrawn while SteamCMD writes.

The daemon's own file work in `<data>/steamcmd` (bootstrap download, archive cleanup, deleting an installation) goes through a no-follow walk rooted there (the same `ConfinedFs` that guards instance directories), because `yagura-steam` can plant links in it. The ready marker and recorded app sizes live in the database, not in `<data>/steamcmd`. At startup the daemon kills any process whose executable lies under its SteamCMD directories before accepting operations.

Workshop items are downloaded by SteamCMD as `yagura-steam` into a tree it can write. The daemon publishes them into the content store (ADR 0005) by a no-follow copy into `content/.staging/<op-id>/` that refuses any reparse point, then renames the copy into place. It never renames a tree `yagura-steam` can still write. `yagura-steam` has no entry on the content store.

Console (development) mode keeps running SteamCMD as the logged-in user. On Linux, SteamCMD runs as the system user `yagura-steam` with the same directory rules as ADR 0015, never as the daemon's root user.

A step fails after 15 minutes without download progress, with a 12-hour hard cap. A login that needs Steam Guard fails fast; the daemon recognises the failure from SteamCMD's output (patterns kept per SteamCMD version in a table, with unknown output reported verbatim), raises a `steam_guard_required` operation event to the client with the kind (email code, authenticator code, mobile approval), and retries once with the code the client returns (`+login user pass code`) or, for mobile approval, waits for SteamCMD to report approval within 2 minutes. The password is used only to establish the cached login; the admin chooses whether the daemon keeps it (encrypted, ADR 0011) to re-login unattended. SteamCMD's behaviour for each Guard kind with stdin closed (fails fast, waits, or loops) is recorded by an M3 spike before the timeouts are fixed; the password is scrubbed from captured output. SteamCMD's cached login token in its `config/config.vdf` is an accepted exception to "no plain-text secrets", readable only by `yagura-steam`, SYSTEM and Administrators. Game Server Login Tokens (GSLT) are per-instance secrets the manifest injects into launch arguments; they are not Steam logins.

**Rejected: run SteamCMD as SYSTEM and scan the tree for reparse points.** The scan races any `yagura-srv` process, including other instances' servers.

**Rejected: withdraw `yagura-srv`'s ACL entry while SteamCMD writes.** Handles opened before the withdrawal keep their access, and owner rights on files the server created survive it.

**Rejected: stage updates in a SYSTEM-only tree and copy them in.** A full copy of a multi-GB tree per update.

**Rejected: drive SteamCMD interactively over stdin/stdout.** Matches the human flow, but prompt timing and buffering differ by platform and SteamCMD version.

**Rejected: a native Steam client library (SteamKit-style) instead of SteamCMD.** Fine-grained control, but a large reimplementation of a protocol Valve changes without notice.

**Reversal cost: medium.** The account lifecycle and the ACL layout are part of the service install.

## Consequences
- The service manages a second local account (`yagura-steam`), created and repaired at every service start with `yagura-srv` (ADR 0015).
- SteamCMD's temp files live in `yagura-steam`'s profile; SteamCMD's self-update writes only `<data>/steamcmd`.
- A game server can corrupt a SteamCMD installation or delete a cached login through a planted link during an update. The installation is bootstrapped again and the admin logs in again (Steam Guard included). The token stays unreadable to `yagura-srv`.
- The output-pattern table needs updating when SteamCMD's wording changes; an unrecognised failure is shown raw, never retried blindly.
- Unattended updates with a mobile-authenticator account may need the admin to approve; the client surfaces it as a pending action.
