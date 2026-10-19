# Desktop client

The Yagura desktop app manages any number of paired daemons from one window. Each daemon has its own secure connection: mutual TLS, with the daemon's CA as the only trusted root.

## Pairing a daemon

1. On the host, run `yagurad pair` as an administrator. It prints a pairing string: `yagura://<host>:<port>?code=<CODE>&ca=sha256:<64 hex>&name=<name>`. The code works once and for 10 minutes.
2. In the app, press the pair button (link icon) in the top bar, paste the string and give this device a name (1 to 64 characters; the default is the computer name). Press **Pair**.

The app first asks the daemon for its CA and compares the CA's SHA-256 fingerprint with the one in the pairing string. If they differ, pairing stops and the code is not sent; the message shows both fingerprints. The private key is generated on this computer, kept in the OS keychain, and never sent: only a certificate request leaves the app. If pairing fails, the key is deleted again.

Pairing errors:

| Code | Meaning |
| --- | --- |
| `invalid_pairing_string` | The text is not a pairing string. Paste the whole line. |
| `fingerprint_mismatch` | The daemon presented another CA than the string names. Nothing was sent. |
| `pairing_code_invalid` | The code expired or was already used. Run `yagurad pair` again. |
| `pairing_throttled` | Too many wrong codes. Wait ten minutes. |
| `keychain_unavailable` | The OS keychain cannot be used, so no key can be kept. |
| `too_many_daemons` | The list holds 32 daemons. Remove one first. |

Pairing a daemon that is already listed replaces its entry and credentials.

## The daemon list

Each daemon shows a state, a sentence about it, and its instances.

| State | Meaning |
| --- | --- |
| `connecting` | Opening the connection, or it was lost and the app is reconnecting. Retries start after 1 s and double up to 30 s. |
| `connected` | The daemon answers. **Manage** opens its instances. |
| `offline` | The last attempt failed. The sentence gives the error and when the daemon was last seen (or that it was not reached since the app started). The app keeps retrying. |
| `incompatible` | Client and daemon share no API version. Upgrade the older one. |
| `revoked` | An administrator revoked this device. The app stops connecting. **Pair again** with a new code. |
| `expired` | The device certificate expired or its renewal was refused. The app stops connecting. **Pair again**. |

**Pair again** is also offered when an offline daemon presents a different CA than the pinned one (`server_ca_mismatch`) or when the keychain no longer holds the credentials (`credentials_missing`). **Remove** forgets a daemon and deletes its key and certificate from the keychain; the daemon keeps listing the device until an administrator revokes it.

In development builds a daemon on `127.0.0.1` without TLS is listed as `dev`. It cannot be removed.

## Certificate renewal

The device certificate is renewed by the app, with a new key, when it has less than 30 days left. The app checks on every connect and then every 24 hours while connected. A refused renewal marks the daemon `expired`; other renewal errors are retried at the next check.

## Creating an instance with a secret

Secret settings are never part of the instance settings. When a plugin has secret fields, the create dialog asks for them. The app creates the instance, then stores each secret. If a secret cannot be stored the instance still exists: a message names the secret, and it can be set from the instance's settings.

## Editing settings and conflicts

Settings carry a revision. If someone else saved first, your save is refused with `revision_conflict`. The app then loads the current settings, keeps your edits in the form, and lists every field where your value differs from the saved one (secrets are never compared). Saving again replaces the saved values with yours; **Discard my edits and reload** takes the saved values. There is no merge. If a change from elsewhere arrives while you edit, a banner offers **Reload**, and until you reload, your form keeps its own values and revision.
