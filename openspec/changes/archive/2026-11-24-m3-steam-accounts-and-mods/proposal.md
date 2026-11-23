# Proposal

## Why

M2 left a secure remote host that can run only anonymous-login games with no mods, so the plugin's settings reach game files only through hooks. DayZ, the first target that needs a Steam account, workshop mods and real config files, cannot be hosted. This change carries milestone **M3 - Steam accounts and mods** (`openspec/roadmap.md`) and serves all six of its exit criteria:

- every test-map row green on Windows CI, or on a Windows runner where a row needs administrator rights, the service or a real Steam account;
- a Steam Guard account added from the desktop with the password in no file or log;
- DayZ going from 10+ workshop mod IDs to a running server with linked mods and keys in one action, and staying correct across a mod update;
- two instances sharing one content-store copy of a mod version;
- `ini`, `json`, `dayz-cfg` and `kv` corpus files round-tripping byte for byte, with a manual edit to a bound file detected and not overwritten;
- a plugin version change re-validating its instances and migrating their settings, or reporting `settings_invalid`.

The work comes from `platform-backlog` groups 14-17. That backlog was written before M1 and M2 were built, so this change restates those requirements against the code they shipped and gets its own design review. The moved material is deleted from the backlog.

## What Changes

- **Steam accounts**: `AddAccount`/`ReauthAccount`/`RemoveAccount` with one SteamCMD installation per account. Steam Guard (email code, authenticator code, mobile approval) is relayed to the client as an operation prompt answered with `RespondToPrompt`. The password is kept, DPAPI-encrypted, only with `remember_password`, and is scrubbed from SteamCMD output, operation events and daemon logs. `account` plugins install with the linked account; `account_optional` plugins use it when one is linked. M2 always refused `account` and installed `account_optional` anonymously.
- **Secret launch arguments**: `{{secrets.<name>}}` in launch templates, used for the Game Server Login Token (`steam.gslt`). Secret arguments reach the relay over its standard input, never through the run files. Secret values are masked in log streams, backlog and crash notices.
- **Workshop downloads**: metadata from the Steam Web API, downloads through SteamCMD as `yagura-steam`, published into a versioned, immutable content store under `<data>/content/` by a no-follow copy (ADR 0005, ADR 0014).
- **Mod pipeline**: a `mods` manifest section with the sources `steam_workshop` and `server_managed`; `url_archive` stays refused with `unsupported_in_this_version`. Also: per-instance ordered mod lists with roles, junction staging with copy fallback, key files owned per mod, a `mods` launch-template namespace, a scheduled update check, and the `ApplyMods`, `UpdateMods` and `CheckModUpdates` operations. Mod junctions recorded by the daemon become the one kind of link that instance file access accepts (ADR 0015).
- **Config bindings**: a `bindings` manifest section with round-tripping parsers for `ini`, `json`, `dayz-cfg` and `kv`. Bindings apply on every start before launch, in one pass with the start's hook edits (bindings first). `ApplyConfig` (a bindings-only pass on a stopped instance) stays unimplemented in M3 and moves to M4 with the complex-config work. The binder records file hashes, emits `external_edit` events with secret values masked, writes atomically and retries a locked file for 5 s. Hook file edits gain the same four formats. `ue-ini`, `xml` and `vdf` stay `unsupported_in_this_version` until M4.
- **Plugin migrations**: a `migrateSettings` hook and `onModsStaged`. A plugin version change re-validates every instance, which then keeps its state, or moves to `settings_invalid` or `plugin_missing`.
- **DayZ plugin**: `plugins/dayz/` with account login, workshop app 221100, Yagura-owned `serverDZ.cfg` and BattlEye config templates, client and server mod roles, bikey rules, data paths, log sources, and stop strategy `signal`. It declares no `rcon` section; that arrives in M4.
- **Desktop**: a Steam accounts view with add, re-login and remove; the Steam Guard prompt dialog; a mods view per instance (add by workshop ID, order, role, update flags, apply, update); the account picker on create and settings; `external_edit` and `settings_invalid` notices.

## Capabilities

### New Capabilities
- `config-bindings`: binding settings to file keys, the supported formats, round-trip preservation, manual-edit detection, and atomic writes.
- `mod-management`: mod sources and stage modes, the shared versioned content store, junction staging, key files, load order and roles, mod changes while running, and update detection.

### Modified Capabilities
- `steam-content`: adds Steam accounts with Steam Guard, credential retention, GSLT, workshop downloads, and keeping passwords out of disk and logs. Login mode per plugin now installs `account` plugins with the linked account, and SteamCMD keeps one installation per account.
- `plugin-manifest`: adds re-validation and migration on plugin version changes. Launch templates gain the `mods` and `secrets` namespaces. The manifest accepts the `bindings` and `mods` sections (`rcon` stays refused).
- `plugin-hooks`: adds the `onModsStaged` and `migrateSettings` hook points. The hook context gains staged mods. File edits gain `ini`, `dayz-cfg` and `kv`, and are refused inside staged mod folders.
- `instance-lifecycle`: the heavy-operation limit counts `apply_mods` and `update_mods`; an update gains the `update_mods` step and re-applies bindings; `instance.json` gains the mod list.
- `daemon-protocol`: an operation snapshot carries its pending prompt; instance deltas carry mod update counts.
- `host-service`: the data directory gains `content/`.
- `log-streaming`: adds masking of secret values in log streams.
- `desktop-client`: adds operation prompts (Steam Guard), the Steam accounts view and the mods view.

## Impact

- **Code**: `apps/yagurad` (Steam accounts and prompts, SteamCMD per account, workshop and Web API client, content store, mod pipeline, junction FFI and the ConfinedFs carve-out for recorded junctions, config binder, the `Steam` and `Mods` services that replace the M1 stubs, plugin migration, log masking, migration 7), `packages/yagura_formats` (the `ini`, `dayz-cfg` and `kv` parsers next to `json`), `packages/yagura_plugin` (the `bindings`, `mods`, `steam.gslt` schema, and the `mods`/`secrets` template namespaces), `apps/yagura_desktop` (accounts, prompts, mods), and `plugins/dayz/`.
- **Protocol**: no breaking change. `steam.proto`, `mods.proto` and the operation prompt messages already exist in `proto/yagura/v1` and get implementations. The additive changes are an `Operations.WatchPrompts` stream (pending prompts across all operations, including account operations that belong to no instance), `Mod.warnings`, `Instance.mod_updates_available`, and the `external_edit` and `settings_invalid` notices.
- **Architecture**: `openspec/architecture.md` gains the content-store, binder and mod-pipeline rows that the baseline lacks (Resource Bounds, State ownership, Failure and recovery).
- **Dependencies**: none new. The Steam Web API is called with `dart:io` `HttpClient`.
- **External systems**: Steam accounts and Steam Guard, the Steam Web API (`ISteamRemoteStorage/GetPublishedFileDetails`), the DayZ server and BattlEye, NTFS junctions.
- **ADRs**: none new. This change builds what ADRs 0004, 0005, 0014 and 0015 already decided.
- **Backlog**: groups 14-17, their requirements, decisions and rows are removed from `platform-backlog`.
