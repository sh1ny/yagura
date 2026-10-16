# Spec Delta

## Purpose

Ensures only devices the admin paired can control a daemon, over an encrypted and mutually authenticated channel, and that secrets held by the daemon never leave it.

## ADDED Requirements

### Requirement: Daemon identity created on first start
On first start the daemon SHALL create a CA key pair and certificate and a server certificate signed by it (covering the configured host names and addresses), store the CA key in the secret store, and print the CA fingerprint.

#### Scenario: First start
- **WHEN** the daemon starts with an empty data directory
- **THEN** a CA and server certificate exist, the console shows `CA fingerprint: sha256:<hex>`, and the CA private key is not present in any file in plain form

#### Scenario: Secret store unavailable
- **WHEN** the CA key cannot be written to the secret store
- **THEN** the daemon exits with a non-zero code and the error `secret_store_unavailable`, and no listener is opened

### Requirement: Pairing with a one-time code
`yagurad pair` SHALL obtain from the running daemon, over the local admin channel, a pairing string with the daemon address, a single-use code valid for 10 minutes, and the CA fingerprint. `Pairing.Enroll` SHALL accept the code with a device name and a certificate signing request, and return a client certificate signed by the daemon CA, valid for one year.

#### Scenario: Successful enrollment
- **WHEN** a client submits a valid, unused code with device name `desk-01` and a CSR within 10 minutes
- **THEN** it receives a signed client certificate, `desk-01` appears in `ListDevices`, and the code no longer works

#### Scenario: Expired or reused code
- **WHEN** a client submits a code older than 10 minutes, or one already used
- **THEN** the call fails with `PERMISSION_DENIED` reason `pairing_code_invalid` and no device is created

#### Scenario: Brute force from one address
- **WHEN** one remote address submits 5 wrong codes within 10 minutes
- **THEN** further enroll calls from that address fail with `RESOURCE_EXHAUSTED` reason `pairing_throttled` for 10 minutes, and the active code still works from other addresses

#### Scenario: Distributed guessing
- **WHEN** 50 wrong codes arrive from any addresses within 10 minutes
- **THEN** the active code is invalidated and the admin must issue a new one

### Requirement: Client pins the daemon CA
At pairing the client SHALL fetch the CA certificate with `Pairing.Info` and accept it only if its SHA-256 matches the pairing string; afterwards it SHALL trust only that CA, verifying the server against the daemon's fixed name so the address used does not matter.

#### Scenario: Fingerprint mismatch at pairing
- **WHEN** the daemon presents a CA whose fingerprint differs from the pairing string
- **THEN** the client aborts before sending the code and shows `fingerprint_mismatch` with both fingerprints

#### Scenario: Daemon CA matches stored CA
- **WHEN** a paired client reconnects and the presented CA matches the stored one
- **THEN** the connection proceeds without prompting the user

### Requirement: Mutual TLS on every call
Every call except `Pairing.Enroll` and `Pairing.Info` SHALL require a client certificate signed by the daemon CA whose SHA-256 fingerprint belongs to an enrolled device that is not revoked; the check happens on each call and fails closed for any method not explicitly exempt.

#### Scenario: Call without a client certificate
- **WHEN** a connection without a client certificate calls `ListInstances`
- **THEN** the call fails with `UNAUTHENTICATED` and the attempt is audited with the remote address

#### Scenario: Revoked device
- **WHEN** device `laptop` is revoked while it holds an open stream
- **THEN** its next call fails with `UNAUTHENTICATED` reason `device_revoked`, and its open streams are closed within 5 s

### Requirement: Device certificate renewal
A paired device SHALL be able to renew its certificate over its existing mTLS connection with a CSR for a new key; the daemon signs it for one year, keeps the device record, and accepts the old certificate until it expires.

#### Scenario: Renewal before expiry
- **WHEN** `desk-01` calls `RenewCertificate` 20 days before its certificate expires
- **THEN** it receives a new certificate valid for one year, `ListDevices` shows one `desk-01` device with the new expiry, and both certificates authenticate until the old one expires

#### Scenario: Revoking a renewed device
- **WHEN** a device that renewed its certificate is revoked
- **THEN** both its old and new certificates are rejected on the next call

#### Scenario: Renewal without a valid certificate
- **WHEN** a connection whose certificate has expired calls `RenewCertificate`
- **THEN** the call fails with `UNAUTHENTICATED` and the client must pair again

### Requirement: Device management
Paired devices SHALL be listable with name, enrollment date, last seen time and address, and revocable; a device cannot revoke itself unless another device remains.

#### Scenario: Revoke another device
- **WHEN** `desk-01` revokes `laptop`
- **THEN** `laptop` is listed as revoked with the time and the revoking device

#### Scenario: Revoking the last device
- **WHEN** the only remaining device tries to revoke itself
- **THEN** the call fails with `FAILED_PRECONDITION` reason `last_device`

### Requirement: Audit log
The daemon SHALL record an audit entry for every state-changing call (time, device, method, target, result, no secret values), and SHALL record authentication failures separately, aggregated per remote address per 10 minutes with a count, so failures cannot evict audit entries.

#### Scenario: Instance deletion audited
- **WHEN** `desk-01` deletes instance `B`
- **THEN** the audit log has an entry with `desk-01`, `DeleteInstance`, instance `B` and `ok`

#### Scenario: Scanner flood
- **WHEN** 100,000 unauthenticated calls arrive from 3 addresses
- **THEN** the audit entry for an earlier `DeleteInstance` is still present, and the failures appear as aggregated rows per address with counts

#### Scenario: Secret set without value in audit
- **WHEN** a device sets an RCON password
- **THEN** the audit entry records `SetSecret` and the setting name, and the password does not appear in the audit log or daemon log

### Requirement: Secrets never leave the daemon
The API SHALL allow setting, replacing and deleting secrets (Steam passwords, RCON passwords, GSLTs) but SHALL never return a secret value. Secrets SHALL be stored only through the OS-backed secret store.

#### Scenario: No read path for secrets
- **WHEN** a client calls every read method for an instance with secrets set
- **THEN** no response contains a secret value; secrets are reported as `{"secret": true, "set": true}`

#### Scenario: Data directory scan
- **WHEN** a test sets known secret values, runs a full install-start-stop workflow, and scans every file under the daemon data directory and instance directories
- **THEN** no file contains any of the secret values in plain text, except game config files the plugin binds a secret into

### Requirement: Local admin channel is restricted to administrators
Host-local CLI commands (`pair`, `devices`, `status`, `roots`) SHALL reach the running daemon only through a local channel restricted to SYSTEM and Administrators (root on Linux); the CLI SHALL NOT open the database while the daemon runs.

#### Scenario: Administrator requests a pairing code
- **WHEN** an administrator runs `yagurad pair` on the host while the service runs
- **THEN** the command prints a pairing string issued by the running daemon

#### Scenario: Non-administrator
- **WHEN** a standard user runs `yagurad pair`
- **THEN** the command fails with `access_denied` and no pairing code is issued

## MODIFIED Requirements

### Requirement: Development mode is localhost only
The daemon SHALL serve plaintext gRPC only when started with `--dev` and SHALL bind it only to loopback addresses (`127.0.0.1`, `::1`, or `localhost` when every address it resolves to is loopback), by default `127.0.0.1:7443`; starting dev mode with any other bind address fails.

#### Scenario: Dev mode on loopback
- **WHEN** the daemon starts with `--dev --bind 127.0.0.1:7443`
- **THEN** a plaintext listener is open on 127.0.0.1 and the console warns `DEV MODE: unauthenticated, localhost only`

#### Scenario: Dev mode on a public address
- **WHEN** the daemon starts with `--dev --bind 0.0.0.0:7443`
- **THEN** it exits with a non-zero code and the error `dev_mode_requires_loopback`

#### Scenario: Dev mode default bind
- **WHEN** the daemon starts with `--dev` and no `--bind`
- **THEN** it listens on `127.0.0.1:7443` only

