# 0001. The daemon owns the host; the client is a view

- Status: accepted
- Date: 2026-10-16
- Supersedes: —

## Context
Game servers run on a host the admin may not be sitting at. Several desktops may manage the same host, and one desktop may manage several hosts. Plugin logic, Steam credentials, files and processes all live on the host.

## Decision
`garrisond` is the only writer of anything on the host: instances, installed content, mods, configs, firewall rules, credentials, processes. The Flutter desktop client holds only its own pairing credentials and per-daemon UI preferences. It never runs plugin code and never edits host files directly; every change is a daemon call, and every view is built from daemon responses and streams. The client renders settings forms from the schema the daemon serves.

**Rejected: a desktop app that manages the local machine (WindowsGSM style) with an optional remote agent.** One process is simpler at first, but remote management would then be a second code path with its own plugin execution, and two writers of the same host state.

**Reversal cost: high.** It fixes where plugin code runs and which side owns state; reversing it rewrites the client and the protocol.

## Consequences
- Every feature needs a protocol surface; the client cannot "just read the file".
- Multiple clients can watch the same daemon; the daemon must serialise conflicting operations per instance.
- A daemon is useful headless (scripts, future web UI) because nothing lives in the client.
