# 0011. Secrets are DPAPI-protected blobs in the daemon database

- Status: accepted
- Date: 2026-10-16
- Supersedes: —

## Context
The daemon holds the CA key, Steam passwords (optional), RCON passwords and GSLTs. The client holds its device key. A copied data directory or backup must not leak them.

## Decision
Secrets are stored through one `SecretStore` interface: on Windows, DPAPI user scope of the LocalSystem account (`CryptProtectData` without `CRYPTPROTECT_LOCAL_MACHINE`, so the game-server account cannot decrypt them) with the protected blobs in the SQLite `secrets` table; on Linux, a file readable only by the daemon user, encrypted with a key from systemd credentials when available. Rows elsewhere reference secrets by id; no API returns a secret's value to the client (it can set, replace or delete one). The client keeps its device key and certificates in the platform keychain (`flutter_secure_storage`).

**Rejected: an encrypted file with a key derived from a passphrase the admin types at start.** Portable, but an unattended service cannot start after a reboot.

**Reversal cost: low.** Behind one interface.

## Consequences
- A database copied to another Windows machine cannot decrypt its secrets; import asks for them again.
- A test scans the data directory for known secret values after a full workflow (strategy success measure).
