# 0006. gRPC over HTTP/2; plugin-declared structures travel as JSON documents

- Status: accepted
- Date: 2026-10-16
- Supersedes: —

## Context
The client needs request/response calls (create instance, change settings), long-lived server streams (console and log lines, install progress, instance state) and a bidirectional RCON console. Plugin settings schemas and values are dynamic: their shape is known only at runtime.

## Decision
The daemon serves gRPC (`package:grpc`) defined in `proto/garrison/v1/*.proto`, shared by daemon and client through the `garrison_proto` package. Fixed concepts (instances, operations, logs, RCON, devices, accounts, firewall rules) are typed messages. Plugin-defined data (settings schema, setting values, hook outputs shown to the user) are carried as JSON documents in `string` fields with an explicit `schema_version`, validated by the daemon. The package version `v1` changes only with a breaking change; additive changes follow protobuf compatibility rules. Every long operation returns an operation id and progress is streamed by `WatchOperation`.

**Rejected: WebSocket JSON-RPC 2.0.** Easier to inspect and natively JSON, but no typed contract shared by both ends, and streaming, cancellation and backpressure must be hand-built.

**Reversal cost: high.** The protocol is the contract between two independently released apps.

## Consequences
- Typed code is generated for both ends; a mismatch is a compile error, not a runtime surprise.
- Debugging needs `grpcurl` with reflection (enabled only in dev mode).
- JSON fields need their own validation and versioning, documented next to the proto.
