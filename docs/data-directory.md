# The data directory

Operator notes for the directory `yagurad` keeps its state in (`--data-dir`; the default is `%ProgramData%\Yagura` on Windows). One daemon holds it at a time through `yagurad.lock`.

| Item | Holds |
|---|---|
| `yagura.db` | The authoritative state (ADR 0008), including the `secrets` table |
| `yagura.db.bak-<N>` | Copy taken before a migration from schema version `N` |
| `plugins/` | Installed plugins |
| `instances/` | The default instance root |
| `snapshots/` | Snapshots taken before updates, restores and deletes |
| `steamcmd/` | SteamCMD installations |
| `logs/` | Daemon logs |

## Secret store

Secret values (the daemon's CA key, Steam passwords, RCON passwords, server passwords and tokens) are never written as text. The daemon protects each one with Windows DPAPI in user scope (ADR 0011) and keeps the blob in the `secrets` table of `yagura.db`. A client can set or delete a secret setting, and never reads one back.

Every row records the SID of the account whose DPAPI scope protected it (`scope_sid`). Only that account can open the blob, so a copy of the database or of a backup on another machine, or under another account, holds nothing readable.

### The scope rule

The service runs as LocalSystem (`S-1-5-18`); a `--dev` daemon runs as the logged-in user. Each has its own scope, so the two cannot read each other's secrets. The daemon checks this while it starts, after the database is migrated and before anything else uses a secret:

- **Service mode.** Rows protected for any other account are deleted in one transaction. The daemon then creates again what it owns (the identity, if the CA key was among them, and the service-account passwords). No instance is lost. A secret setting that was among the deleted rows reads `{"secret": true, "set": false}` and has to be set again. Startup notice `secrets_reset` names each instance affected. If the CA key was deleted, every paired device must pair again.
- **Dev mode.** The daemon changes nothing. It exits non-zero with reason `secret_store_unavailable` in the `secret_store` step, naming both SIDs. Give a dev daemon its own `--data-dir` on a host where the service runs.

### Recovering

| You see | What happened | What to do |
|---|---|---|
| Notice `secrets_reset` after the service starts | The data directory was last used by a `--dev` daemon, was restored from another account's backup, or the service now runs as another account | Set the secret settings named in the notice again; pair devices again if the notice says the identity was re-created |
| `secret_store_unavailable` naming two SIDs when a dev daemon starts | The data directory holds secrets of the service (or of another user) | Start the dev daemon with a different `--data-dir`; do not delete `yagura.db` |
| `secret_store_unavailable` naming one error | DPAPI failed for the current account, for example because its profile cannot be loaded | Fix the account and restart; nothing was deleted |

### Another machine, and Linux

LocalSystem has the same SID (`S-1-5-18`) on every machine, but its DPAPI key belongs to one machine. A data directory moved or restored to another host therefore keeps matching `scope_sid` values whose blobs cannot be opened. To catch this, the service test-decrypts every row of its own scope once while it starts (the plaintext is cleared at once) and treats a row that fails like a row of another account: it is deleted, and `secrets_reset` names the instances affected. The service starts, keeps every instance, and the secret settings and daemon-owned secrets are set or created again. A dev daemon does not test-decrypt; it only refuses rows of another SID.

Linux has no secret store until M5: the store opens empty and refuses to hold a secret (`secret_store_unavailable`).
