# Yagura

Self-hosted game server manager: a headless Dart daemon (`yagurad`) that installs, configures and runs dedicated servers on Windows (Linux later, no Docker), and a Flutter desktop client that manages several daemons over mTLS gRPC. Every game is a plugin: a YAML manifest plus optional JavaScript hooks. "Yagura" is a working name.

Planning is done with [Specwright](https://github.com/sh1ny/specwright) on OpenSpec 1.14.1. No code exists yet.

## Read in this order

1. [docs/overview.md](docs/overview.md) — how it works, with flows and an example plugin
2. [openspec/strategy.md](openspec/strategy.md) — purpose, users, boundaries, success measures
3. [openspec/architecture.md](openspec/architecture.md) — components, state machine, state ownership, failure and recovery, bounds, ADR index
4. [docs/protocol.md](docs/protocol.md) + [proto/yagura/v1/](proto/yagura/v1/) — the desktop ↔ daemon protocol and its security
5. [openspec/roadmap.md](openspec/roadmap.md) — milestones M1-M5 with exit criteria
6. [openspec/changes/init-core-platform/](openspec/changes/init-core-platform/) — the umbrella change: proposal, 13 capability specs, design, review, phased tasks

Reviews: [openspec/architecture-review.md](openspec/architecture-review.md) (baseline, 2 rounds) and [review.md](openspec/changes/init-core-platform/review.md) (design, 2 rounds), both by a fresh-context reviewer subagent.

## Development setup

Prerequisites: [mise](https://mise.jdx.dev/) and Git. `mise install` installs the pinned Flutter SDK (with Dart) and git-cliff from `mise.toml`.

| Task | What it does |
|---|---|
| `mise run format` | Format Dart source |
| `mise run format:check` | Fail if any Dart file is not formatted |
| `mise run changelog` | Regenerate `CHANGELOG.md` from local history (`cliff.toml`, strict `vX.Y.Z` tags) |
| `mise run release-notes -- <range or --tag vX.Y.Z>` | Print release notes for a range or tag |

`analyze` and `test` arrive with the pub workspace (task 1.1).

Agent tooling: `.mcp.json` runs the official Dart MCP server from the mise-pinned SDK (read by Claude Code and OMP). Official Dart and Flutter skills are vendored in `.claude/skills/`, with their source commits and file hashes in `.claude/skills/UPSTREAM.json`.

## Next step

`/opsx:apply init-core-platform` starting with task group 1 (workspace and the two M1 spikes: quickjs-ng on MSVC, Ctrl+C through the relay).
