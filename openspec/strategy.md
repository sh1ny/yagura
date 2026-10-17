# Yagura Strategy

## Purpose
Yagura manages dedicated game servers on machines you own. A headless daemon (`yagurad`) on each host installs, configures, runs and watches servers; a Flutter desktop client manages one or more daemons over an authenticated channel. Every game is a plugin that is data plus small scripts, so supporting a new game or a game update never needs a rebuild of Yagura.

## Users
- **Primary: a solo admin running community servers** (DayZ, ARK:SA, SCUM, Valheim, Rust) on one or a few Windows boxes, editing configs, updating mods and watching logs from a desktop elsewhere. Needs: reliable start/stop/update, mods that just work, config editing without breaking files, live logs and RCON, no exposed admin surface.
- **Secondary: plugin authors** (often the same admin) adapting to a game patch. Needs: edit a manifest or a `hooks.js` with a text editor on the box, reload, and see a clear error when it is wrong.

## Boundaries
- No Docker, no containers. Native Windows agent first; Linux (systemd) after.
- No hosting-panel features: billing, multi-tenant customers, web UI, user accounts beyond paired devices.
- Yagura never runs plugin code on the desktop client; the client renders what the daemon declares.
- Plugins cannot touch the filesystem outside the instance and the shared content store, start processes or open sockets directly; every privileged action is a daemon host function.
- Steam passwords never leave the daemon host after the client sends them once, and are never written in plain text. Accepted exception: SteamCMD's own cached login token (`config/config.vdf`), protected by directory ACLs.
- Game servers and their mods run under a dedicated low-privilege account, never as the daemon's LocalSystem identity.
- The daemon never exposes a listener without mTLS except a localhost-only development mode.
- Game servers keep running when the daemon restarts or is upgraded.

## Success measures
- A new game that follows the SteamCMD → config → launch pattern is supported by a manifest alone (no `hooks.js`), shown by the Valheim plugin.
- DayZ with 10+ workshop mods goes from "add mod IDs" to a running server with linked mods and keys in one action, and stays correct across mod updates.
- A daemon on a fresh Windows host is installed as a service and paired with the desktop in under 5 minutes, with no manual certificate or firewall work.
- Zero plain-text secrets on disk on the daemon host apart from the accepted SteamCMD token and secrets a game's own config needs (checked by a test that scans the data and instance directories).
- Stopping Valheim or SCUM through Yagura never loses progress made before the stop.

## Tracks
- **Daemon core:** instances, process control, state, protocol.
- **Plugin platform:** manifest, settings schema, config bindings, JS hooks, mod strategies.
- **Steam & content:** SteamCMD, accounts, workshop.
- **Operations:** logs, RCON, firewall, service install.
- **Desktop client:** multi-daemon, schema-driven UI.

## Assumptions
- Working name "Yagura"; rename is a search-replace.
- One daemon per host; a host runs up to ~20 instances.
- The desktop client is used by one admin (or a few trusted ones); all paired devices have full rights in v1 (no roles).
- Windows Server 2019+ / Windows 10+ hosts with PowerShell 5.1+ and the NetSecurity module.
- Network path between client and daemon is the admin's concern (LAN, VPN, Tailscale or port forward); Yagura secures the channel, not the route.
- No scheduler in v1 (timed restarts or updates); mod update checks run on an internal timer.
- Plugins are trusted-ish: installed by the admin, sandboxed against mistakes and path escapes, not against a determined attacker with admin on the box.
