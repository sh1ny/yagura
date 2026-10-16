# Spec Delta

## Purpose

Installs, orders, updates and removes game mods for an instance using the strategy its plugin declares, sharing downloaded content between instances.

## ADDED Requirements

### Requirement: Plugins declare mod support and strategy
A plugin SHALL declare `mods` with a source (`steam_workshop`, `url_archive` or `server_managed`), a stage mode (`link`, `copy` or `none`), an optional link name template, copy fallback, key file rules, roles and how the load order reaches the launch arguments. A plugin without `mods` rejects mod operations.

#### Scenario: Plugin without mod support
- **WHEN** a client adds a mod to an instance of a plugin that declares no `mods` section
- **THEN** the call fails with `FAILED_PRECONDITION` reason `mods_not_supported`

#### Scenario: Server-managed mods
- **WHEN** an ARK:SA instance (source `server_managed`, stage `none`) has mods `[928708, 929420]`
- **THEN** nothing is downloaded by the daemon and the launch arguments contain `-mods=928708,929420`

### Requirement: Shared, versioned, immutable content store
Mod content SHALL live once per host per item version in the content store, published atomically and never modified afterwards. Each instance mod has a staged version (what its link points at) and a desired version; versions that no instance has as staged or desired are removed after 7 days. Requests for the same item version share one download; cancelling one requester detaches only it.

#### Scenario: Two instances share one download
- **WHEN** two DayZ instances add mod 1559212036 at the same time
- **THEN** one download runs, both instances pin the same version, and the content store lists 2 references

#### Scenario: Update while another instance runs
- **WHEN** instance A (stopped) updates mod 1559212036 to a newer version while instance B (running) uses the old version
- **THEN** the new version is published next to the old one, A is re-linked to it, and B's linked files are unchanged until B is stopped and updated

#### Scenario: Update requested for a running instance
- **WHEN** `UpdateMods` runs for a running instance
- **THEN** the new version is downloaded and set as desired, the staged version stays linked and counted as referenced, and re-linking happens at the next start

#### Scenario: One of two waiters cancels
- **WHEN** two operations wait on the same workshop download and one is cancelled
- **THEN** the cancelled operation ends `cancelled` and the download completes for the other

#### Scenario: Interrupted download
- **WHEN** the daemon dies while downloading a mod version
- **THEN** no partial version directory is published, and the staging leftovers are deleted at the next startup

#### Scenario: Removing a mod from one instance
- **WHEN** one of those instances removes the mod
- **THEN** its staged link is removed, the content remains on disk, and the store shows 1 reference

### Requirement: Staging by link with copy fallback
For stage mode `link`, the daemon SHALL create a directory link (NTFS junction on Windows, symlink on Linux) in the instance directory pointing at the pinned version, named by the link template with a sanitised, de-duplicated name fixed when the mod is added. If linking fails, it SHALL copy when `copy_fallback` is true and fail the step otherwise.

#### Scenario: DayZ mod linked
- **WHEN** mod "Community Framework" (id 1559212036) is staged with `link_name: "@{{mod.name_safe}}"`
- **THEN** `instances/<id>/@Community-Framework` is a directory link to `content/steam_workshop/221100/1559212036/<version>/`

#### Scenario: Mod renamed on the workshop
- **WHEN** the mod's workshop title changes after it was added
- **THEN** the staged name stays `@Community-Framework` and the launch arguments are unchanged

#### Scenario: Link not permitted
- **WHEN** link creation fails (for example the instance is on a network share) and `copy_fallback` is false
- **THEN** the step fails with `stage_link_failed` naming the cause, and no partial copy is left

### Requirement: Key files and post-processing
The daemon SHALL apply the plugin's key rules after staging (for example copying `**/*.bikey` into `keys/`), record which mods provide each placed key, remove a key only when no staged mod provides it, never overwrite a key file it did not place, and then call `onModsStaged`.

#### Scenario: Bikeys synced
- **WHEN** two DayZ mods each containing one `.bikey` are staged
- **THEN** `keys/` contains both key files plus any keys not placed by Yagura, unchanged

#### Scenario: Shared key kept
- **WHEN** mods X and Y both ship `CF.bikey` and mod X is removed
- **THEN** `CF.bikey` stays in `keys/` because Y still provides it

#### Scenario: Admin's own key with the same name
- **WHEN** `keys/` already holds an admin-placed `CF.bikey` with different content
- **THEN** it is not overwritten, and the mod shows a `key_conflict` warning

#### Scenario: Mod removed takes its key
- **WHEN** one of those mods is removed
- **THEN** its key file is removed from `keys/`, and keys Yagura did not place are not touched

### Requirement: Load order and roles
Each instance SHALL keep an ordered mod list with each mod's role from the plugin's roles (for example `client` or `server`). The launch template receives one ordered list per role.

#### Scenario: Reorder changes launch order
- **WHEN** the client moves `@VPPAdminTools` before `@CF` in the client role
- **THEN** the next start's arguments contain `-mod=@VPPAdminTools;@CF`

#### Scenario: Unknown role
- **WHEN** a client assigns role `both` to a mod and the plugin declares roles `[client, server]`
- **THEN** the call fails with `INVALID_ARGUMENT` listing the allowed roles

### Requirement: Mod changes require a stopped instance to apply
Adding, removing or reordering mods SHALL be recorded at any time, and staged on the next start or on an explicit `ApplyMods`; staging never runs while the instance's server is running.

#### Scenario: Add while running
- **WHEN** a mod is added to a running instance
- **THEN** the mod list shows it as `pending`, nothing in the instance directory changes, and it is staged on the next start

#### Scenario: ApplyMods while running
- **WHEN** a client calls `ApplyMods` on a running instance
- **THEN** the call fails with `FAILED_PRECONDITION` reason `instance_running`

### Requirement: Mod update detection and update
The daemon SHALL compare each workshop item's remote `time_updated` with the downloaded version on request and on a schedule (default every 6 hours), mark items `update_available`, and update them when the instance's update operation runs or the client requests it. An update re-stages only changed mods.

#### Scenario: Update available flagged
- **WHEN** the workshop reports a newer `time_updated` for a staged mod
- **THEN** `ListMods` shows that mod with `update_available: true` and the remote and local timestamps

#### Scenario: Update check cannot reach Steam
- **WHEN** the metadata request fails
- **THEN** mods keep their previous flags, the check result is `unknown` with the error, and a retry is scheduled with backoff
