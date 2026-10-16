# 0005. Mods are a daemon capability with a versioned, immutable content store

- Status: accepted
- Date: 2026-10-16
- Supersedes: —

## Context
Mods differ by game: DayZ workshop items are linked into the server folder as `@name` directories, their `.bikey` files copied into `keys/`, and their order passed as `-mod=`/`-serverMod=`; ARK:SA mods are CurseForge IDs the server downloads itself (`-mods=`); Valheim and Rust use loader frameworks plus plugin files. Mod trees can be gigabytes. Several instances on one host often use the same mods, and one may be running while another updates.

## Decision
The daemon owns a mod pipeline: resolve (source, version), acquire, stage, post-process (key files), expose (ordered lists per role for the launch template). The manifest's `mods` section picks a strategy per step from a fixed vocabulary and may call `onModsStaged`. Sources: `steam_workshop`, `url_archive`, `server_managed` (the game downloads; the daemon only passes IDs — no CurseForge API calls).

The content store is versioned and immutable: `content/<source>/<app>/<item>/<version>/`, where the version is the workshop `time_updated` (or archive hash). Acquisition downloads into `content/.staging/<op-id>/` and renames into place atomically; a published version is never written again. Acquisition is single-flight per `(source, app, item, version)`. Each instance-mod row carries `staged_version` (the current junction target) and `desired_version`; references are derived from both (GC treats both as references), re-staging while stopped sets `staged_version := desired_version`, and versions nothing references are garbage-collected after 7 days. An update acquires the new version alongside the old one and re-stages an instance only while that instance is stopped, so a running instance keeps its files.

Staging links each pinned version into the instance as a directory link (NTFS junction on Windows, which needs no privilege; symlink on Linux), named by a sanitised, de-duplicated name fixed when the mod is added (`@<sanitised title>` or `@<id>` per manifest). Instances and the content store must be on local volumes; if a link cannot be made, the daemon copies when the manifest allows `copy_fallback`, else the step fails. Hooks and game servers get read-only access to the content store.

**Rejected: mods handled entirely by plugin hooks.** Each plugin re-implements download and staging, and heavy file work runs inside the hook deadline.

**Rejected: one mutable directory per item, updated in place.** Simpler layout, but an update rewrites files a running instance has open and leaves key files out of sync.

**Reversal cost: high.** The store layout is on-disk state on every host; the strategy vocabulary is part of the manifest format.

## Consequences
- Disk use grows by one version per update until GC; the disk check before acquisition counts it.
- "Update available" compares the pinned version with the workshop's `time_updated`.
