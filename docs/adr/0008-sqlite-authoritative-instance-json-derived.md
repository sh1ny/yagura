# 0008. SQLite is authoritative; instance.json is a derived, portable copy

- Status: accepted
- Date: 2026-10-16
- Supersedes: —

## Context
The daemon keeps instances, settings values, installed content and mods, Steam account references, devices, firewall rules it owns, operation history and an audit log. Admins also want an instance folder they can back up or move to another host.

## Decision
One SQLite database (`package:sqlite3`, WAL mode) in the daemon data directory is the authoritative state, written only by the daemon process; each table has exactly one owning component (the State ownership table in `openspec/architecture.md`). CLI commands never open the database while the service runs; they go through the local admin channel (ADR 0012). After every committed change to an instance, the daemon writes `instance.json` into the instance directory (atomic replace) with the instance's plugin id and version, settings, mods (with pinned versions) and ports, never secrets. Every instance row carries a `revision` incremented only on configuration changes (settings, ports, secrets, mods, restart policy, Steam account, snapshot restore), never on state, health, pid or queue changes; mutating API calls must send the revision they read, so concurrent edits from two clients fail instead of overwriting each other. `instance.json` is read only by `ImportInstance`. Schema changes use numbered migrations run at startup inside a transaction, with a backup copy taken first.

**Rejected: flat files per instance as the only state.** Portable, but no transactions across instance, content store and firewall rows, and no history queries.

**Reversal cost: medium.** Moving off SQLite means a migration of every host's data.

## Consequences
- An instance directory copied to another host imports cleanly; secrets (RCON password, Steam account) must be re-entered or re-linked.
- `instance.json` can be stale only if the daemon died between commit and write; startup rewrites it for every instance.
