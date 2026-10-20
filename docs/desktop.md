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
| `device_name_invalid` | The device name must be 1 to 64 characters. |
| `tls_authority_invalid` | The daemon names itself with something other than `yagurad-<id>`. Check the address. |
| `enroll_response_invalid` | The daemon returned a certificate for another key, or another CA than the one pinned. Nothing was stored. |
| `server_ca_mismatch` | The daemon stopped presenting the CA it showed a moment ago. |
| `daemon_unreachable` | The daemon could not be reached at the address in the string. The message gives the reason. |
| `daemon_list_unsaved` | The daemon was paired but the list of daemons could not be written (`daemons.json` in the app's data directory), so it was not added and its key was deleted again (when the daemon was already listed, its previous entry stays and the new credentials replace the old ones in the keychain). |
| `pairing_failed` | Anything else; the message shows the error. |

Errors the daemon itself reports while enrolling (for example `csr_invalid`) are shown under the daemon's own code, with its message.

Pairing a daemon that is already listed replaces its entry and credentials.

## The daemon list

Each daemon shows a state, a sentence about it, and its instances.

| State | Meaning |
| --- | --- |
| `connecting` | Opening the connection, or it was lost and the app is reconnecting. |
| `connected` | The daemon answers. **Manage** opens its instances. |
| `offline` | The app cannot reach the daemon. The sentence gives the last error and when the daemon was last seen (the app remembers this across restarts), or says "Not reached since the client started" when no earlier time is known. The app keeps retrying. |
| `incompatible` | Client and daemon share no API version. Upgrade the older one. |
| `revoked` | An administrator revoked this device. The app stops connecting. **Pair again** with a new code. |
| `expired` | The device certificate expired or its renewal was refused. The app stops connecting. **Pair again**. |

When `connecting` turns into `offline`: a daemon that was connected and dropped (a restart, a network blip) shows `connecting` while the app retries after 1 s, 2 s, 4 s, 8 s and 16 s. When the next wait would be the 30 s cap, it shows `offline`; it is still retried every 30 s and goes back to `connected` as soon as it answers. A daemon that has not answered since the app started shows `offline` after its first failed attempt.

**Pair again** is also offered when an offline daemon presents a different CA than the pinned one (`server_ca_mismatch`) or when the keychain no longer holds the credentials (`credentials_missing`). **Remove** forgets a daemon and deletes its key and certificate from the keychain; the daemon keeps listing the device until an administrator revokes it.

In development builds a daemon on `127.0.0.1:7443` without TLS is listed as "Development daemon". It cannot be removed.

If `daemons.json` has an entry the app cannot read, a notice above the list says how many; the readable daemons work, and the unreadable entries stay in the file. The notice has a **Discard unreadable entries** button. It asks first, and the question names the entries (and the valid ones that did not fit under the limit of 32 daemons) and says that their keys and certificates are deleted from the keychain with them. After that the entries are gone from the file and the app's cleanup of orphaned key material runs again. If the file cannot be read as a list at all, the app first keeps a copy next to it as `daemons.json.damaged` (or `.damaged.1`, ... if that name holds something else) and shows the notice. If no copy can be made, the notice says so and the app does not save the list, so the original is never overwritten. Daemons beyond the limit of 32 are not shown either, and are kept in their own `over_cap` array of the file (not among the unreadable entries); they are listed again at a later start if there is room. The notice says how many, and **Discard unreadable entries** lists them by name as over the limit. While saving is refused (the file could not be read, or a damaged file could not be copied aside) pairing is refused before anything else happens: the **Pair** action is disabled with the reason, and a pairing attempt fails with `daemon_list_unsaved`, so no one-time code is used up and no device or key is created. A file that cannot be read at all (another program holds it, no permission) is not treated as damaged: the notice says it could not be read, nothing is copied, deleted or saved, and the app tries again at the next start. While a `daemons.json.damaged` copy exists, the app's cleanup deletes no keys of unlisted daemons (only pending keys), because those daemons may be the ones in the copy; the notice offers **Discard the damaged copy** (it asks first) and after that the cleanup runs normally again, deleting the keys of daemons that are not listed.

The app deletes key material that belongs to no listed daemon (left behind by an interrupted pairing) when it starts. It does that only when the whole list was read.

## Certificate renewal

The device certificate is renewed by the app, with a new key, when it has less than 30 days left. The app checks on every connect and then every 24 hours while connected. The new key is kept in the keychain as a pending key while the request is in flight, and the stored key and certificate are replaced only once the new certificate has arrived. As soon as the new pair is stored the app reconnects with it, so the new certificate is used within seconds and the old one can no longer renew; the daemon is not shown as lost meanwhile, and the old connection is closed once the new one is up. If the answer is lost or the keychain cannot be written, the old pair stays and the next check renews with it: the daemon accepts a renewal from the previous certificate for 26 hours after it issued a newest certificate that nothing has used yet. After that window the old certificate cannot renew, and the daemon is `expired` when it has run out. (Within those 26 hours a leaked old key could renew too; see docs/protocol.md.) The app renews at most once every 24 hours per daemon, by its own clock, and keeps the time of the last renewal in `daemons.json`. A daemon whose clock is far behind issues certificates that look due again at once; the app then does not renew in a loop. It renews once, and its detail line says that the daemon's clock may be wrong until a certificate has more than 30 days left. A renewal the daemon refuses marks the daemon `expired` and the app stops connecting; **Pair again** with a new code is then the way out. A revoked device is `revoked`; any other renewal error is retried at the next check.

## Creating an instance with a secret

Secret settings are never part of the instance settings. When a plugin has secret fields, the create dialog asks for them. The app creates the instance, then stores each secret. If a secret cannot be stored the instance still exists: a message names the secret, and it can be set from the instance's settings. The same holds when you save settings together with secrets: the settings are saved first, and if a secret then fails the message says that the settings were saved and which secrets were not. The form moves to the new revision, so enter the secrets again and save.

## Editing settings and conflicts

Settings carry a revision. If someone else saved first, your save is refused with `revision_conflict`. The app then loads the current settings, keeps your edits in the form, and lists every field where your value differs from the saved one (secrets are never compared). Saving again replaces the saved values with yours; **Discard my edits and reload** takes the saved values. The same holds when a secret cannot be set because someone else changed the instance after your settings were saved: the app says the settings were saved, reloads, lists the fields that now differ, and keeps your edits; it does not move on to their revision silently. If no listed field differs (for example only a secret was edited), the app says that none of your changes were saved and that you can save again. There is no merge. If a change from elsewhere arrives while you edit, a banner offers **Reload**, and until you reload, your form keeps its own values and revision.
