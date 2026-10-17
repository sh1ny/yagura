# 0010. SteamCMD runs non-interactively; Steam Guard is relayed to the client

- Status: accepted
- Date: 2026-10-16
- Supersedes: —

## Context
Most target servers download anonymously (Valheim, Rust, ARK:SA, SCUM); DayZ's server and all DayZ workshop items need an account that owns the game. SteamCMD caches a successful login per installation; Steam Guard (email or mobile) may still ask for a code or an approval. SteamCMD's interactive prompts are unreliable through pipes on Windows.

## Decision
The daemon installs and owns SteamCMD (one installation per Steam account, so cached logins never collide) and runs it only with a full `+command` argument list ending in `+quit` (never a `+runscript` file, so the password never touches disk), stdin closed, inside a kill-on-close job object owned by the daemon so it dies with the daemon. One SteamCMD process runs per installation at a time; other requests queue. Before and after each `app_update` into an instance, the daemon checks the instance tree for reparse points not created by Yagura and fails with `sandbox_violation`; instances in `installing`/`updating` have no running server, so `yagura-srv` code is not running to race the check. At startup the daemon kills any process whose executable lies under its SteamCMD directories before accepting operations. A step fails after 15 minutes without download progress, with a 12-hour hard cap. A login that needs Steam Guard fails fast; the daemon recognises the failure from SteamCMD's output (patterns kept per SteamCMD version in a table, with unknown output reported verbatim), raises a `steam_guard_required` operation event to the client with the kind (email code, authenticator code, mobile approval), and retries once with the code the client returns (`+login user pass code`) or, for mobile approval, waits for SteamCMD to report approval within 2 minutes. The password is used only to establish the cached login; the admin chooses whether the daemon keeps it (encrypted, ADR 0011) to re-login unattended. SteamCMD's behaviour for each Guard kind with stdin closed (fails fast, waits, or loops) is recorded by an M3 spike before the timeouts are fixed; the password is scrubbed from captured output. SteamCMD's cached login token in its `config/config.vdf` is an accepted exception to "no plain-text secrets", protected by the data directory ACL (ADR 0013). Game Server Login Tokens (GSLT) are per-instance secrets the manifest injects into launch arguments; they are not Steam logins.

**Rejected: drive SteamCMD interactively over stdin/stdout.** Matches the human flow, but prompt timing and buffering differ by platform and SteamCMD version.

**Rejected: a native Steam client library (SteamKit-style) instead of SteamCMD.** Fine-grained control, but a large reimplementation of a protocol Valve changes without notice.

**Reversal cost: low.** Contained in the Steam component.

## Consequences
- The output-pattern table needs updating when SteamCMD's wording changes; an unrecognised failure is shown raw, never retried blindly.
- Unattended updates with a mobile-authenticator account may need the admin to approve; the client surfaces it as a pending action.
