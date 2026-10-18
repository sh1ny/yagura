# Proposal

## Why

M1 proved the walking skeleton on one machine. The daemon still serves only an unauthenticated loopback connection, runs from a console, starts game servers as the logged-in user, and leaves firewall ports to the admin. The product needs a host you can install, pair with and manage remotely. This change carries milestone **M2 - Secure remote host** (`openspec/roadmap.md`) and serves all six of its exit criteria: every test-map row green on Windows, a fresh host installed and paired in under 5 minutes with no manual certificate or firewall work, service stop and upgrade leaving servers running, a revoked device's next call failing, servers running as `yagura-srv` with ports open only while their instance exists, and one desktop managing two daemons with concurrent edits detected.

The work comes from `platform-backlog` groups 10-13. That backlog was written before M1 was built, so this change restates those requirements against the code M1 shipped and gets its own design review. The moved material is deleted from the backlog.

## What Changes

- **Daemon identity and pairing**: on first start the daemon creates a CA and a server certificate. `yagurad pair` issues a one-time code over a local admin channel restricted to administrators. The client pins the CA fingerprint from the pairing string and enrolls with a CSR.
- **Mutual TLS on every call**: started without `--dev`, the daemon serves only mTLS, checked against the enrolled-device list on every call and failing closed. Devices can be listed, revoked and renewed. Without `--dev` the daemon runs only in service mode (`run --service` as LocalSystem); any other start exits `service_mode_required` (M1 exited `secure_mode_unavailable`). **BREAKING** for the development workflow only: the exit reason changes, and a `--dev` daemon's secrets are reset when the service later uses the same data directory.
- **Audit log**: an entry for every state-changing call, and authentication failures aggregated in a separate table so they cannot evict audit entries.
- **Secrets**: an OS-backed secret store (DPAPI). Secret settings are now accepted, stored and never returned. This replaces M1's "secret settings stay unset" rule.
- **Windows service**: `yagurad service install|uninstall|status` through WinSW. Game servers run as a low-privilege `yagura-srv` account with the directory ACLs that ADR 0015 records, and servers survive service stop, restart and upgrade.
- **Instance trust boundary**: daemon file operations in instance directories refuse links planted by the game-server account, including a replaced instance directory. Instance roots are writable only by administrators. The daemon terminates only verified server processes. SteamCMD runs as its own low-privilege account `yagura-steam`, so a link planted during an update gains nothing.
- **Firewall reconciler**: owned rules named `Yagura/<id>/<port>/<proto>` are derived from instance ports and the daemon API port, reconciled at startup, on port change, on delete and on request. Rules outside the naming scheme are never touched.
- **Instance revisions**: configuration calls carry the revision the caller read, and a stale revision fails with `revision_conflict`.
- **Remote desktop**: pairing from a pairing string, several daemons with connection states, certificate renewal, and conflict handling in the settings form. The single development connection is replaced.

## Capabilities

### New Capabilities
- `firewall-rules`: owned firewall rules for instance ports and the daemon API port: naming, desired-state reconcile, port changes, deletion and degraded reporting.

### Modified Capabilities
- `daemon-security`: adds identity, pairing, CA pinning, mTLS, renewal, device management, audit, secret handling and the local admin channel. Development mode stops being the only mode.
- `host-service`: adds the Windows service, the game-server account and service-survival requirements. Data directory layout gains locally managed instance roots. The startup sequence gains the secret store, identity and firewall steps.
- `instance-lifecycle`: adds revisions, the link-refusing file boundary and verified termination. The signal stop, creation ACLs, audited snapshot skip, firewall cleanup on delete, stored secrets in `instance.json` and the error-reason exits (`run_record_rejected`) change.
- `plugin-manifest`: replaces "Secret settings stay unset without a secret store" with write-only stored secrets set through `SetSecret`.
- `plugin-hooks`: the hook context shows a set secret as a placeholder.
- `steam-content`: SteamCMD runs as a dedicated low-privilege account instead of LocalSystem.
- `desktop-client`: adds multiple paired daemons, pairing and certificate renewal. Forms handle `revision_conflict`. Replaces "Connection to one daemon".

## Impact

- **Code**: `apps/yagurad` (security, service, launcher, instance file access, firewall, auth gate, admin channel, migrations), `apps/yagura_desktop` (daemon list, pairing, keychain, forms), `packages/yagura_proto` (the existing pairing, firewall, audit and revision fields get implementations; `DaemonHealth` gains `admin_channel_ok`, `service_accounts_ok` and `server_cert_not_after`), and `tool/winsw/`.
- **Architecture**: `openspec/architecture.md` changes its component diagram (SteamCMD as `yagura-steam`, the admin channel), the secrets row (account passwords), the ADR index (0014 and 0015 in, 0010 and 0013 out) and the error-reason table (`run_record_rejected`).
- **Dependencies**: `pointycastle` under a new workspace package `packages/yagura_pki` that builds and signs certificates and CSRs (the spike ruled out the `x509` package), Flutter secure storage for the client keychain, and bundled WinSW 2.x (MIT).
- **External systems**: Windows Service Control Manager, Windows Firewall (NetSecurity), DPAPI, local accounts (`yagura-srv`, `yagura-steam`) and logon rights.
- **ADRs**: records ADR 0014 (SteamCMD runs as a low-privilege account, superseding 0010) and ADR 0015 (game-server account and directory ACLs, superseding 0013).
- **Backlog**: groups 10-13, their requirements, decisions and rows are removed from `platform-backlog`.
