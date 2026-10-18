# Yagura protocol (`yagura.v1`)

How the desktop client and `yagurad` talk, and how that channel is secured. The service definitions are in [`proto/yagura/v1/`](../proto/yagura/v1/); the behaviour contract is in the `daemon-protocol` and `daemon-security` specs; the decisions are ADR 0006 (gRPC) and ADR 0007 (mTLS and pairing).

## Transport

| Item | Value |
|---|---|
| RPC | gRPC over HTTP/2 (`package:grpc` on both ends) |
| Default port | 7443/tcp (configurable `--bind`) |
| TLS | TLS 1.3 only (1.2 refused) |
| Keys | ECDSA P-256 for CA, server and devices |
| Server auth | Server cert signed by the daemon CA, SAN `yagurad-<daemon-id>`; client uses the pinned CA as its only root and sets the TLS authority to that name |
| Client auth | Client cert signed by the daemon CA, required on every method except `Pairing.Info` / `Pairing.Enroll` |
| Dev mode | `yagurad run --dev [--bind host:port]`: plaintext, loopback bind only (default `127.0.0.1:7443`), server reflection on (`grpc.reflection.v1`, and `v1alpha` under its own name) |
| Keepalive | HTTP/2 ping every 30 s from the client; daemon closes connections idle 10 min without streams |
| Server keepalive policy | `minIntervalBetweenPingsWithoutData` 20 s, `maxBadPings` 2 (accepts the 30 s client ping); an idle stream must survive 10 minutes (test) |
| Max message | 4 MiB request, 16 MiB response; an oversized request is refused before it is read with `RESOURCE_EXHAUSTED` / `message_too_large` and changes nothing |

## Certificates

| Certificate | Subject | Validity | Key usage | Where the key lives |
|---|---|---|---|---|
| Daemon CA | `CN=Yagura CA <host>`; `basicConstraints CA:true, pathlen:0` | 20 years | keyCertSign, cRLSign | Daemon secret store (DPAPI), never exported |
| Server | `CN=yagurad-<daemon-id>`; SAN: `yagurad-<daemon-id>`, `localhost` | 2 years, renewed at startup when < 30 days left | digitalSignature; EKU serverAuth | Daemon secret store |
| Device | `CN=<device name>`, serial = random 128-bit | 1 year from enroll, `notBefore` 1 h in the past | digitalSignature; EKU clientAuth | Client OS keychain (generated there; only the CSR leaves) |

Device renewal: within 30 days of expiry the client calls `Pairing.RenewCertificate` over its existing mTLS connection with a CSR for a new key; the daemon signs it and adds the new certificate's SHA-256 to the same device; the old certificate keeps working until it expires, and revoking the device rejects both. An expired device must pair again.

Because the client connects by whatever address the admin typed, it never verifies the network address: it uses the pinned CA certificate as its only trusted root and sets the TLS authority (SNI and name check) to `yagurad-<daemon-id>`, which is the server certificate's SAN. The CA certificate itself is obtained from `Pairing.Info` at pairing and checked against the fingerprint in the pairing string. Device identity on the daemon side is the SHA-256 of the client certificate DER (`dart:io`'s `X509Certificate` exposes the DER, not the serial).

## Pairing

```
yagura://<host>:<port>?code=<CODE>&ca=sha256:<64 hex>&name=<daemon name>
```

- `CODE`: 8 characters from `23456789ABCDEFGHJKMNPQRSTUVWXYZ` shown as `XXXX-XXXX` (~40 bits), single use, 10 minutes, at most one active code per daemon (issuing a new one invalidates the old).
- Throttle: 5 wrong attempts from one address in 10 minutes block that address (`pairing_throttled`); 50 wrong attempts in total in 10 minutes invalidate the active code.
- The pairing string travels out of band (the admin copies it from `yagurad pair`, which talks to the running service over the local admin pipe, ACL'd to SYSTEM and Administrators); that is what makes the CA fingerprint trustworthy.

```mermaid
sequenceDiagram
  participant C as Client
  participant D as Daemon
  C->>C: parse pairing string (fail: invalid_pairing_string)
  C->>D: TLS (no client cert, no verification yet) Pairing.Info
  D-->>C: CA cert DER, tls_authority
  C->>C: SHA-256(CA) == pin? (fail: fingerprint_mismatch, abort)
  C->>D: new TLS connection, CA as sole root, authority yagurad-<id>
  C->>C: generate P-256 key in keychain, build CSR (CN=device name)
  C->>D: Pairing.Enroll(code, device_name, csr)
  D->>D: code valid & unused & not throttled? (fail: pairing_code_invalid / RESOURCE_EXHAUSTED)
  D->>D: verify CSR signature, sign device cert (EKU clientAuth), store device row, burn code, audit
  D-->>C: device_id, client cert, CA cert
  C->>C: store CA + client cert in keychain
  C->>D: new mTLS connection; System.GetInfo
```

## Per-call authorization

An interceptor runs on every call:

1. Method in `{Pairing.Info, Pairing.Enroll}` → allowed without a client certificate.
2. Otherwise `call.clientCertificate` must be present → else `UNAUTHENTICATED`. (TLS has already verified any presented certificate's chain to the daemon CA; see the note below.)
3. SHA-256 of the certificate DER → device row; missing or `revoked` → `UNAUTHENTICATED` / `device_revoked`.
4. Update `last_seen_at` / `last_address` (at most once per minute per device), attach `device_id` to the call context for audit.

Note: the listener uses `requestClientCertificate: true` rather than `requireClientCertificate`, so the two pairing methods work on the same port; the interceptor enforces presence for every other method. A certificate that is presented is still chain-verified by TLS against the daemon CA (the CA is the listener's only trusted root), so an unknown certificate fails the handshake. Whether Dart's TLS stack rejects an untrusted client certificate in request (not require) mode is verified by the M2 spike; if it does not, pairing moves to a second listener on port+1 and the main listener uses `requireClientCertificate: true`.

Revocation closes the revoked device's open streams within 5 s (the daemon tracks open streams per device).

## Calls and streams

| Pattern | Methods |
|---|---|
| Unary | most CRUD (`CreateInstance`, `UpdateSettings`, `SetSecret`, `SetMods`, `ListDevices`...) |
| Unary returning an `Operation` | `DeleteInstance`, `RestoreSnapshot`, `Install`, `Update`, `Validate`, `Start`, `Stop`, `Restart`, `ApplyConfig`, `ApplyMods`, `CheckModUpdates`, `UpdateMods`, `Steam.AddAccount`, `Steam.ReauthAccount` |
| Server stream | `WatchInstances` (snapshot + slim deltas with `settings_omitted`; 1,000 events or 8 MiB per subscriber), `WatchOperation` (resumable by `after_sequence`; `events_dropped` + snapshot when the gap is no longer retained), `Logs.Backlog`, `Logs.Follow` |
| Bidirectional | `Rcon.Console` |

Every mutating instance call (`UpdateSettings`, `SetSecret`, `DeleteSecret`, `SetMods`, `DeleteInstance`, `RestoreSnapshot`) carries `expected_revision`, the `Instance.revision` the caller last read. A new instance is at revision 1. The revision is incremented only on configuration changes (settings, ports, secrets, mods, restart policy, autostart, Steam account, snapshot restore), never on state, health, pid or queue changes, so an instance that crashed and restarted still has the revision the client loaded. The daemon checks and increments it in the same database transaction as the write:

- A missing `expected_revision` (0, proto3's unset value) fails `INVALID_ARGUMENT` / `revision_required`.
- A stale one fails `FAILED_PRECONDITION` / `revision_conflict` with the current revision in the `revision` metadata entry of the `ErrorDetail`. Nothing is changed and no operation is created; the client reloads, and two admins never silently overwrite each other.
- `UpdateSettings`, `SetSecret` and `DeleteSecret` return the `Instance` with the incremented revision. `UpdateSettings` leaves `autostart` and `restart_policy` as they are when the request does not set them.
- `RestoreSnapshot` and `DeleteInstance` return an `Operation`. An accepted restore increments the revision in the same step that creates its operation, so a second restore sent with the same revision fails `revision_conflict` while the first is queued or running; the client reads the new revision from `GetInstance` or the instance stream.

Long work never blocks a unary call: it returns an `Operation` immediately. Interactive steps (Steam Guard) set the operation to `WAITING_FOR_INPUT` with a `Prompt` of kind `email`, `authenticator` or `mobile_approval`; any paired client may answer with `Operations.RespondToPrompt`, and the others see `PromptResolved`.

Client deadlines: unary 30 s; `Execute` 15 s; streams have no deadline and rely on keepalive.

## Plugin-shaped data

`JsonDocument { json, schema_version }` carries the settings schema (from `GetPlugin`) and settings values. Rules:

- `schema_version` is the plugin's settings-schema version; the daemon rejects writes for another version (`schema_version_mismatch`) so a form opened before a plugin reload cannot write stale fields.
- Secret settings never carry values out of the daemon: `{"secret": true, "set": true|false}`. Values go in only through `SetSecret`.
- **SetSecret flow.** `CreateInstance` and `UpdateSettings` take a secret setting only as that placeholder or as an omitted key, and either leaves the stored value unchanged. A plain value fails `INVALID_ARGUMENT` / `secret_via_set_secret` and nothing is saved or created. A client creates the instance first, then calls `SetSecret` (`key` is the setting name, `value` is write-only) for each secret the user entered. `DeleteSecret` clears the value, and the setting reads `set: false` again. Both return the updated `Instance`. If the secret store refuses the write, the call fails `FAILED_PRECONDITION` / `secret_store_unavailable` and the setting keeps its previous state. Deleting an instance deletes its secrets.
- An instance is created without its secrets, so a `required` secret setting is checked when the instance starts: `Start` fails `FAILED_PRECONDITION` / `secret_required` naming the setting, and the state is unchanged.
- The settings schema format is documented with the manifest JSON Schema (`schemas/plugin-manifest.v1.json`, `settings` section).

## Errors

Every non-OK status carries `ErrorDetail` (`reason`, `message`, `field_violations`, `incident_id`, `metadata`). Reasons are stable identifiers:

| Area | Reasons |
|---|---|
| General | `not_implemented`, `internal_error`, `instance_not_found`, `operation_not_found`, `invalid_json`, `schema_version_mismatch`, `revision_required`, `revision_conflict`, `operation_expired`, `resync_required`, `interrupted`, `events_dropped`, `queue_full`, `too_many_subscribers`, `message_too_large`, `prompt_resolved` |
| Auth | `pairing_code_invalid`, `pairing_throttled`, `device_revoked`, `last_device`, `unauthenticated`, `access_denied` (admin channel) |
| Instances | `confirmation_mismatch`, `not_installed`, `invalid_state`, `instance_running`, `instance_not_running`, `port_conflict`, `unsupported_platform`, `crash_loop`, `lost_while_daemon_down`, `update_interrupted`, `install_interrupted`, `restore_interrupted`, `settings_invalid`, `secret_via_set_secret`, `secret_required`, `plugin_missing`, `instance_directory_missing`, `launch_failed`, `launch_logon_failed`, `directory_not_allowed`, `run_record_rejected`, `sandbox_violation` (a symbolic link or junction in the instance directory refused a file operation: start, delete with files, restore), `instance_file_stale` (warning; also raised when a link stops the `instance.json` write), `autostarted` (notice), `stopped_by`, `pre_delete_snapshot`, `restored` (result reasons of a succeeded operation, followed by `:` and a detail: how the stop ended, or the snapshot id) |
| Plugins | `invalid_manifest`, `unsupported_manifest_version`, `file_too_large`, `hook_syntax_error`, `unsupported_in_this_version`, `mods_not_supported`, `rcon_not_supported` |
| Hooks | `hook_timeout`, `hook_out_of_memory`, `hook_result_invalid`, `hook_result_too_large`, `hook_error`, `sandbox_violation`, `host_limit_exceeded`, `hook_runtime_degraded`, `not_supported`, `unsupported_in_this_version` (file-edit format) |
| Config | `binding_file_missing`, `config_parse_error`, `file_locked`, `external_edit` (event/warning; values of secret-bound keys masked) |
| Steam | `steamcmd_unavailable`, `steam_account_required`, `disk_check_skipped` (warning), `steam_no_subscription`, `steam_unknown_error`, `steam_guard_invalid`, `steam_guard_timeout`, `steam_reauth_required`, `steam_stalled`, `gslt_required`, `insufficient_disk`, `workshop_item_unavailable` |
| Mods | `stage_link_failed`, `key_conflict` (warning) |
| Snapshots | `insufficient_disk` (snapshot), `snapshot_not_found`, `sandbox_violation` (a symbolic link or junction in the instance directory or its data paths; before M2 a link in a data path was `unsupported_in_this_version`) |
| RCON | `rcon_auth_failed`, `rcon_unavailable` (stop fell back to kill), `timeout` |
| Firewall | `firewall_unavailable` (warning) |
| Host | `data_dir_locked`, `data_dir_unwritable`, `migration_failed`, `secret_store_unavailable`, `secrets_reset` (startup notice: secrets of another Windows account deleted; see [`data-directory.md`](data-directory.md)), `dev_mode_requires_loopback`, `secure_mode_unavailable`, `elevation_required`, `systemd_required` (CLI/startup exit reasons) |

## Versioning

- Package `yagura.v1`; `System.GetInfo.api_versions` lists every `major.minor` served; the client uses the highest major it shares.
- Minor bumps add fields, methods or enum values only. Clients ignore unknown enum values (treated as `*_UNSPECIFIED`) and hide features above the daemon's minor.
- A breaking change creates `yagura.v2`; the daemon serves v1 and v2 side by side for at least one minor release.
- Field numbers are never reused; removed fields are `reserved`.

## Methods by daemon version

The whole `yagura.v1` contract is defined up front; each daemon version implements part of it. A method that a version does not implement fails `UNIMPLEMENTED` with reason `not_implemented`; services a version does not build are registered as stubs, so their methods fail the same way with an `ErrorDetail`. `GetHealth.not_built` names the components a version does not have.

| Version | Services served | Methods not implemented |
|---|---|---|
| M1 (walking skeleton, dev mode only) | `System`, `Plugins`, `Instances`, `Operations`, `Logs` (`Pairing`, `Steam`, `Mods`, `Rcon`, `Firewall` as stubs) | Every method of the stub services; `System.ListAudit`; `Instances.ImportInstance`, `ExportInstance`, `ApplyConfig`; `Operations.RespondToPrompt`. `Instances.SetSecret` and `DeleteSecret` fail `FAILED_PRECONDITION` / `secret_store_unavailable`. `not_built`: `secret_store`, `firewall`. |
