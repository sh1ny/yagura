# 0004. Settings reach files through declarative bindings and round-tripping parsers

- Status: accepted
- Date: 2026-10-16
- Supersedes: —

## Context
Game configs are multi-file and messy: ARK:SA's `GameUserSettings.ini` and `Game.ini` repeat keys (`ConfigOverrideItemMaxQuantity=...` many times) and mix structured values; DayZ uses `serverDZ.cfg` (a C-like class format), `cfggameplay.json` and XML economy files; others use VDF or plain INI. Admins also edit these files by hand, and a manager that rewrites a file and drops their comments or unknown keys loses trust fast.

## Decision
The manifest declares bindings: each maps a setting (or a structured group) to a file, a format and a key path. The daemon ships parsers for `ini`, `ue-ini` (Unreal: repeated keys, `+`/`-` prefixes, struct values), `json`, `xml`, `vdf`, `dayz-cfg` and `kv` (one `key value` or `key=value` pair per line, as in BattlEye configs). Every parser round-trips: an unchanged document serialises byte-identical, and a patch touches only the bound keys, keeping comments, order and unknown keys. Bindings apply before `onPreStart`; the same parsers are exposed to hooks as host functions for cases bindings cannot express. The binder is the only writer of bound files and of files hooks ask to change. A file changed since the last apply (by the admin or the game) is detected by content hash: the binder re-reads it, patches only the bound keys, emits an `external_edit` event naming bound keys whose values it overwrote, and never blocks the start. A binding may declare `game_writes: true` (the game rewrites the file itself, e.g. ARK on shutdown) to suppress the event. Where a game accepts a config path, plugins point it at a Yagura-owned copy (DayZ `-config=yagura/serverDZ.cfg`) so a Steam `validate` cannot overwrite it.

**Rejected: hooks write configs with regex.** Each plugin re-solves parsing, and regexes on messy files corrupt them silently.

**Rejected: render whole files from templates.** Simple, but every apply erases manual edits and unknown keys.

**Reversal cost: medium.** The binding syntax is part of the manifest (ADR 0002); parsers are internal.

## Consequences
- The settings schema supports nested objects and repeatable groups so ARK's override lists are editable as tables.
- Each parser needs a corpus of real files and a byte-identical round-trip test.
