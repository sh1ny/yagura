# Spec Delta

## Purpose

Installs, orders, updates and removes an instance's game mods with the strategy its plugin declares. Downloaded content is shared between instances on the host.

## ADDED Requirements

### Requirement: Plugins declare mod support and strategy
A plugin SHALL declare `mods` with a source, a stage mode (`link`, `copy` or `none`), an optional link name template, copy fallback, key file rules, roles, and how each role's load order reaches the launch arguments. This version supports the sources `steam_workshop` and `server_managed`. A plugin without `mods` rejects mod operations.

#### Scenario: Plugin without mod support
- **WHEN** a client sets mods on an instance of a plugin that declares no `mods` section
- **THEN** the call fails with `FAILED_PRECONDITION` reason `mods_not_supported`

#### Scenario: Server-managed mods
- **WHEN** an instance of a plugin with source `server_managed`, stage `none` and a launch entry joining `mods.server` with `,` behind `-mods=` has mods `[928708, 929420]`
- **THEN** nothing is downloaded by the daemon and the launch arguments contain `-mods=928708,929420`

#### Scenario: Source of a later version
- **WHEN** a manifest declares `mods.source: url_archive`
- **THEN** the plugin is `rejected` at load with reason `unsupported_in_this_version` naming `mods.source`

### Requirement: Shared, versioned, immutable content store
Mod content SHALL be stored once per host per item version, published atomically and never modified afterwards. Each instance mod has a staged version (the one its link points at) and a desired version. Versions that no instance has as staged or desired SHALL be removed after 7 days. Requests for the same item version share one download, and cancelling one requester detaches only that requester.

#### Scenario: Two instances share one download
- **WHEN** two DayZ instances apply mod 1559212036 at the same time
- **THEN** one download runs, both instances' mods pin the same version, and one version directory exists in the content store

#### Scenario: Update while another instance runs
- **WHEN** instance A (stopped) updates mod 1559212036 to a newer version while instance B (running) uses the old version
- **THEN** the new version is published next to the old one, A is re-linked to it, and B's linked files are unchanged until B is stopped and updated

#### Scenario: Update requested for a running instance
- **WHEN** `UpdateMods` runs for a running instance
- **THEN** the new version is downloaded and set as desired, the staged version stays linked and kept, and re-linking happens at the next start

#### Scenario: One of two waiters cancels
- **WHEN** two operations wait on the same workshop download and one is cancelled
- **THEN** the cancelled operation ends `cancelled` and the download completes for the other

#### Scenario: Interrupted download
- **WHEN** the daemon dies while downloading a mod version
- **THEN** no partial version directory is published, and the staging leftovers are deleted at the next startup

#### Scenario: Removing a mod from one instance
- **WHEN** one of two instances that use the same version removes the mod
- **THEN** its staged link is removed, the content stays on disk, and the other instance's link still resolves

#### Scenario: Unreferenced version collected
- **WHEN** a version has been neither staged nor desired by any instance for more than 7 days
- **THEN** the next collection removes its directory, and a version unreferenced for less than 7 days is kept

#### Scenario: Not enough disk for a mod
- **WHEN** the content store volume has less free space than twice the item's reported size
- **THEN** that item fails with `insufficient_disk` naming the volume, free bytes and required bytes, before SteamCMD downloads it

### Requirement: Staging by link with copy fallback
For stage mode `link`, the daemon SHALL create a directory link (an NTFS junction on Windows) in the plugin's stage directory to the pinned version, named by the link template. The name is sanitised, unique in the directory, and fixed once when metadata is first read or found unavailable. A failed link is copied when `copy_fallback` is true. Staging SHALL never remove an entry Yagura did not create, except a link where Yagura recorded one, removed without following.

#### Scenario: DayZ mod linked
- **WHEN** mod "Community Framework" (id 1559212036) is staged with `stage_dir: server` and `link_name: "@{{mod.name_safe}}"`
- **THEN** `<instance>/server/@Community-Framework` is a directory link to `<data>/content/steam_workshop/221100/1559212036/<version>/`, and the launch arguments name it `@Community-Framework`

#### Scenario: Title unavailable when added
- **WHEN** a mod is added while the workshop metadata cannot be read
- **THEN** its staged name is fixed as `@1559212036`, and it keeps that name after the title becomes known

#### Scenario: Admin folder with the staged name
- **WHEN** staging finds an entry at a mod's staged name that is neither a link nor a copy Yagura recorded
- **THEN** the step fails with `stage_name_conflict` naming the path, and the entry is left unchanged

#### Scenario: Mod renamed on the workshop
- **WHEN** the mod's workshop title changes after it was added
- **THEN** the staged name stays `@Community-Framework` and the launch arguments are unchanged

#### Scenario: Link not permitted
- **WHEN** link creation fails (for example the instance is on a network share) and `copy_fallback` is false
- **THEN** the step fails with `stage_link_failed` naming the cause, and no partial copy is left

#### Scenario: Staged link replaced by the server
- **WHEN** a process running as the game-server account replaces `server/@Community-Framework` with a junction to another directory
- **THEN** daemon file operations through it fail with `sandbox_violation`, and the next staging removes that link without following it and recreates the recorded one

### Requirement: Key files and post-processing
The daemon SHALL apply the plugin's key rules after staging (for example copying `**/*.bikey` into `server/keys/`), record which mods provide each placed key, remove a key only when no staged mod provides it, never overwrite a key file it did not place, and then call `onModsStaged`.

#### Scenario: Bikeys synced
- **WHEN** two DayZ mods each containing one `.bikey` are staged
- **THEN** `server/keys/` contains both key files plus any keys not placed by Yagura, unchanged

#### Scenario: Shared key kept
- **WHEN** mods X and Y both ship `CF.bikey` and mod X is removed
- **THEN** `CF.bikey` stays in `server/keys/` because Y still provides it

#### Scenario: Admin's own key with the same name
- **WHEN** `server/keys/` already holds an admin-placed `CF.bikey` with different content
- **THEN** it is not overwritten, and the mod shows a `key_conflict` warning

#### Scenario: Mod removed takes its key
- **WHEN** the only mod that provides `VPP.bikey` is removed and the mods are staged
- **THEN** `VPP.bikey` is removed from `server/keys/`, and keys Yagura did not place are not touched

### Requirement: Load order and roles
Each instance SHALL keep an ordered mod list in which each mod has one of the plugin's roles (for example `client` or `server`). The launch template SHALL receive one ordered list of staged names per role.

#### Scenario: Reorder changes launch order
- **WHEN** the client moves `@VPPAdminTools` before `@CF` in the client role
- **THEN** the next start's arguments contain `-mod=@VPPAdminTools;@CF`

#### Scenario: Unknown role
- **WHEN** a client assigns role `both` to a mod and the plugin declares roles `[client, server]`
- **THEN** the call fails with `INVALID_ARGUMENT` listing the allowed roles, and the mod list is unchanged

### Requirement: Mod changes require a stopped instance to apply
Adding, removing or reordering mods SHALL be recorded at any time and applied on the next start or on an explicit `ApplyMods`. Applying downloads missing versions, stages links and keys, and never runs while the instance's server is running.

#### Scenario: Mods applied by start
- **WHEN** a stopped DayZ instance has 12 newly added workshop mods and a client starts it
- **THEN** the start downloads the 12 items, stages their links and keys, and launches the server with them in `-mod=` order

#### Scenario: Add while running
- **WHEN** a mod is added to a running instance
- **THEN** the mod list shows it as `pending`, nothing in the instance directory changes, and it is staged on the next start

#### Scenario: ApplyMods while running
- **WHEN** a client calls `ApplyMods` on a running instance
- **THEN** the call fails with `FAILED_PRECONDITION` reason `instance_running`

### Requirement: Mod update detection and update
The daemon SHALL compare each workshop item's remote `time_updated` with its desired version on request and on a schedule (every 6 hours), mark items `update_available`, and update them when the instance's update operation runs or the client requests it. An update re-stages only changed mods.

#### Scenario: Update available flagged
- **WHEN** the workshop reports a newer `time_updated` for a staged mod
- **THEN** `ListMods` shows that mod with `update_available: true` and the remote and local timestamps

#### Scenario: Only changed mods re-staged
- **WHEN** an instance with 12 mods updates and one of them has a newer version
- **THEN** only that mod is downloaded and re-linked, and the other 11 links are unchanged

#### Scenario: Update check cannot reach Steam
- **WHEN** the metadata request fails
- **THEN** mods keep their previous flags, the check result is `unknown` with the error, and a retry is scheduled with backoff
