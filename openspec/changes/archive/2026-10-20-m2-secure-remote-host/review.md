# Review

## Metadata

- **Round:** 3
- **Prior round:** 2 APPROVE_WITH_CHANGES (N1-N4 moderate, S1-S10 suggestions), CHANGES_APPLIED: yes after re-check. This round reviews the amendment in `7dc3785` (D1 and the S1 assumption in design.md, the Dependencies bullet in proposal.md, tasks 1.4 and 6.2) and re-reads the whole design for consistency with it.
- **Reviewer:** fresh-context subagent (Claude Code, specwright-reviewer). Project skills named for this review: none.
- **Reviewed:** `proposal.md`, `design.md` (TIER: FULL), `tasks.md`, every delta spec under `specs/` (daemon-security, desktop-client, firewall-rules, host-service, instance-lifecycle, plugin-hooks, plugin-manifest, steam-content); `git show 7dc3785`; round 2 review (`HEAD~1`); `docs/milestones/m2.md` (Spike S1); `docs/protocol.md` ("Per-call authorization", "Calls and streams", "Errors"); `docs/adr/0007-mtls-with-daemon-ca-and-pairing.md`; `openspec/architecture.md` and its ADR index; source: `apps/yagurad/lib/src/api/api_server.dart`, `api/pressure.dart`, `api/service_support.dart`, `apps/yagura_desktop/lib/src/{grpc_transport,connection,providers}.dart`, grpc 5.2.0 `lib/src/server/server.dart` and `lib/src/shared/security.dart` (pub cache), root `pubspec.yaml`, `tool/test.dart`, `.github/workflows/ci.yml`.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

### Round 2 findings re-checked

N1-N4 and S1-S10 were resolved in round 2. The amendment does not touch D2-D12 or the specs, and nothing in it reopens them.

### The amended D1

The amendment holds up against the evidence:
- **Spike evidence.** The S1 output in `docs/milestones/m2.md` supports both halves of the decision. Request mode lets a connection without a certificate through (row a). A server context that trusts the daemon CA refuses foreign-CA and expired certificates and accepts a valid device certificate (rows b-d). `x509` 0.2.4 cannot re-encode or sign.
- **grpc source.** `ServerTlsCredentials.securityContext` builds `SecurityContext()` through `createSecurityContext(true)` with no trusted roots (`security.dart:20-21`, `server.dart:68-80`), so the subclass D1 describes is needed. `serve` passes `requestClientCertificate` to `SecureServerSocket.bind` and drops non-`Error` stream errors (`server.dart:260-310`), so a refused handshake does not crash the daemon.
- **Consistency.** D1 matches ADR 0007, which names this fallback, and `docs/protocol.md:65-69`, which already assumes the CA is the listener's only trusted root. It also matches D2 (the gate still checks presence, device membership, revocation and expiry) and D13 (the desktop builds its CSR with `yagura_pki`).
- **Proposal and tasks.** The Dependencies bullet and tasks 1.4 and 6.2 match. `tool/test.dart` reads the workspace list from the root `pubspec.yaml`, so the new package's tests run in CI once task 1.4 adds it there.

The amendment does have consequences the design has not followed through. M1 and M2 below cover them.

## Findings

### Critical (blocking)

None.

### Moderate

**M1. With TLS refusing expired and foreign-CA certificates, D13's error-to-state mapping cannot produce `expired`, and the failure table states an outcome that cannot happen.**
- **Where the client sees the refusal.** D1 now has TLS refuse an expired client certificate at the handshake (spike S1 row c). So the gate's `certificate_expired` (D2) is reached only by a connection opened before expiry. Spike S1 also shows how a refused client experiences it: the call never completes and fails only at the deadline. In today's desktop, `getInfo` has a 30 s deadline (`grpc_transport.dart:41-43`), and any failure loops back into reconnect with backoff (`connection.dart:174-219`).
- **What D13 says.** D13's "Errors to states" maps "an expired certificate … → `expired`" as if a daemon error reports it. An implementation that follows D13 shows `connecting`/`offline` forever and keeps retrying. That contradicts desktop-client "Certificate already expired" ("listed `expired` … instead of retrying").
- **Why tests would not catch it.** The test map runs that row as a widget test against fake daemon connections (tasks.md test map, group 11). A fake that returns `certificate_expired` passes, while the real client hangs.
- **Failure table row "SecretStore scope mismatch".** It says "paired devices see `device_revoked` if the CA was reset". After a CA reset, the server certificate no longer chains to the CA the client pinned. The client fails its own server verification before any call, and the gate is never reached. Under D13 that client ends `offline` and retries indefinitely, with nothing telling the user to pair again.

**M2. The mTLS scenario "Method added without an exemption" is not assertable for the certificates TLS now refuses.** The WHEN says "a certificate that is not an enrolled device's". That includes a certificate from another CA, and after D1 such a call never reaches a handler (spike S1 row b): the client sees a handshake failure or deadline, not `UNAUTHENTICATED`. The requirement's SHALL already says "signed by the daemon CA". As written, though, the test author of task 6.1 must pick which certificate to use, and a foreign-CA certificate makes the row fail for a reason the design intends. No scenario records the TLS-level refusal that D1 now relies on.

### Suggestions

- **S1. State the certificate profile and the CSR rules in D1.** Yagura now owns the builder, so nothing upstream enforces the profile. The design lists the structures `yagura_pki` covers (Risks) but not what each certificate carries. State:
  - **CA:** `CA:true`, `pathLen:0`, keyCertSign/cRLSign.
  - **Server certificate:** `CA:false`, serverAuth, the two DNS SANs.
  - **Client certificate:** `CA:false`, clientAuth. Only the subject public key comes from the CSR, and it must be P-256. The daemon sets the subject and extensions itself and never copies requested ones.

  For CSRs: a CSR with attributes, another key type or a bad signature fails `Enroll` with a defined reason (for example `INVALID_ARGUMENT`/`csr_invalid`) and leaves the code unused. `Enroll` parses the CSR only after the throttle and code checks (as T4's diagram already orders them), so the hand-written DER parser is not reachable without a valid code.

  Add a `yagura_pki` test that TLS refuses a chain through a client certificate used as an issuer. Today's tests (parse back, one handshake) would not notice a client certificate that can issue a server certificate for `yagurad-<daemon-id>`, which every other paired client would accept.
- **S2. Task order for test certificates.** Task 6.1 writes failing tests "with generated clients holding test certificates", but `yagura_pki` is an empty library until 6.2 (task 1.4). Those tests then fail to compile rather than "for the stated reason". Either split the `yagura_pki` work into its own task before 6.1 (with its own round-trip and handshake tests), or have 6.1 use committed fixture certificates.
- **S3. `docs/protocol.md` after the spike.** Task 6.4 updates `docs/protocol.md`. Name two edits there:
  - drop the conditional spike sentence and port + 1 fallback at `protocol.md:69`;
  - add `certificate_expired` (D2) to the Auth reasons at `protocol.md:103`, which lists `device_revoked` but not it.

## Verdict

The amended D1 rests on the spike evidence and agrees with ADR 0007, `docs/protocol.md`, D2, D13 and the tasks. Its side effect is that some failures now happen at the TLS layer, and the client mapping and one failure-table row do not reflect that yet. Both moderate findings are text-level fixes.

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **M1, design.md D13 and the Failure & Visibility table.**
   - In D13 "Errors to states", replace "an expired certificate or refused renewal → `expired`" with: "the stored client certificate's `not_after` is checked locally before every connect attempt; past it, the daemon is `expired` with no network call. A refused renewal → `expired`. `certificate_expired` from the gate (a connection opened before expiry) → `expired`. A TLS failure verifying the server against the pinned CA → `offline` with last error `server_ca_mismatch` and an offer to pair again."
   - In the Failure table row "SecretStore scope mismatch", replace "paired devices see `device_revoked` if the CA was reset" with "if the CA was reset, paired clients fail server verification against their pinned CA and show `server_ca_mismatch` until paired again".
   - In desktop-client "Certificate already expired", extend the THEN with "without contacting the daemon".
2. **M2, specs/daemon-security "Mutual TLS on every call".**
   - Reword the WHEN of "Method added without an exemption" to "is called with a certificate signed by the daemon CA that belongs to no enrolled device".
   - Add a scenario "Certificate from another CA": WHEN a client presents a certificate not signed by the daemon CA, THEN the TLS handshake is refused and no handler runs.
   - Add its row to the tasks.md test map (group 6).

CHANGES_APPLIED: yes

## Rebuttals

<!-- Author: fixed (cite) or rebutted (reason) per finding. A Critical/Moderate rebuttal counts only once marked "accepted by reviewer". -->

- **M1:** fixed. design.md D13 "Errors to states" now checks `not_after` locally before every connect, maps `certificate_expired` and refused renewal to `expired`, and maps a pinned-CA verification failure to `offline` / `server_ca_mismatch`. The Failure-table row "SecretStore scope mismatch" now names `server_ca_mismatch`. desktop-client "Certificate already expired" now ends "without contacting the daemon".
- **M2:** fixed. daemon-security "Method added without an exemption" now uses a daemon-CA certificate of no enrolled device. The new scenario "Certificate from another CA" is added, with its test-map row in group 6 (`certificate_from_another_ca`).
- **S1:** taken. D1 now has "Certificate profile" and "CSR rules" bullets (`csr_invalid`, parsing after the throttle and code checks, the issuer-misuse TLS test).
- **S2:** taken. yagura_pki is implemented test-first in task 6.1, before the group's red tests. Task 6.2 starts at the CA.
- **S3:** taken. Task 6.4's protocol.md work now adds `certificate_expired` and `csr_invalid`, and drops the spike sentence and the port + 1 fallback.
- **Later edits from the baseline review (architecture-review.md round 3), outside this review's Required Changes:**
  - D6: the data directory is protected before the database opens. That covers the owner, a protected DACL, the `<data>/acl-layout` walk and the fatal `data_dir_not_protected` reason, plus a Failure-table row. Owner Administrators is set on every DACL write.
  - D7: the logon rights are named. The password is set without a test logon. Desktops use account-SID ACLs. The logon module is shared.
  - D10: the daemon starts SteamCMD itself, suspended and in the job, with pipes. The redirect bound is accepted. The M3 workshop publish path and the Linux account are stated.
  - host-service "Startup sequence": a new step and two new scenarios, with test rows in group 9.
  - Tasks 9.2, 9.3 and 9.5 are updated.

### Re-check (reviewer)

**Required Changes: applied faithfully.**
- **M1.** D13 "Errors to states" carries the required text word for word: local `not_after` check with no network call, refused renewal and gate `certificate_expired` → `expired`, pinned-CA failure → `offline` / `server_ca_mismatch`. The Failure-table row "SecretStore scope mismatch" names `server_ca_mismatch`. desktop-client "Certificate already expired" ends "without contacting the daemon".
- **M2.** The WHEN of "Method added without an exemption" now uses a daemon-CA certificate of no enrolled device. "Certificate from another CA" is added. Its group-6 row `certificate_from_another_ca` is in the test map.
- **S1-S3** are taken as stated: D1 has "Certificate profile" and "CSR rules", task 6.1 builds `yagura_pki` test-first before the red tests, and task 6.4 names the protocol.md edits.

**Baseline-driven delta: three Moderate items are outstanding.**

The rest of the delta is consistent:
- D7: named logon rights, password set with no test logon, account-SID desktop ACLs.
- D10: workshop boundary and Linux.
- Failure-table row, the two new scenarios with their group-9 `elevated` rows, and tasks 9.2 and 9.5.
- Startup order against the lock, the secret-store recovery and the dev-first scenario.
- The WinSW restart loop on a fatal exit.
- D10's in-process start against ADR 0009 and the existing `steam_process.dart` suspended-create, job and resume pattern.

Outstanding:

- **R1 (Moderate). D8 still sends the `tar` extraction through the launcher.** design.md D8 "Same walk for `<data>/steamcmd`" says "the `tar -xf` extraction runs as `yagura-steam` through the launcher". D10, ADR 0014 and task 9.3 now say the daemon starts it itself, in the operation's kill-on-close job. `yagurad launch` breaks away from the job (ADR 0009), so following D8 would let an extraction outlive a cancelled or crashed operation.
  - **Fix:** in D8, replace "the `tar -xf` extraction runs as `yagura-steam` through the launcher" with "the `tar -xf` extraction runs as `yagura-steam`, started by the daemon in the operation's kill-on-close job like every SteamCMD run (D10)".
- **R2 (Moderate). A data directory that is itself a reparse point is not refused.** The new D6 paragraph sets the owner and the protected DACL on the data directory through a `FILE_OPEN_REPARSE_POINT` handle. It refuses reparse points only inside the walk. Any standard user can create `%ProgramData%\Yagura` before the first service start, because Users may create folders there. If that user makes it a junction to a folder they own, two things follow:
  - the DACL lands on the link, not on the target;
  - `DataDirectory.prepare` (`host/daemon.dart:148-150`), the lock and the database all follow the link as SYSTEM into a folder the user still controls, so the user can replace `yagura.db`.

  The walk never sees the root. Fix:
  - **D6 "Data directory first", first sentence after "So in service mode,":** insert "before `DataDirectory.prepare` creates anything, the daemon opens the data directory with `FILE_OPEN_REPARSE_POINT` and exits `data_dir_not_protected` if it is a reparse point or its final path (`GetFinalPathNameByHandleW`) differs from the configured one; then,".
  - **Failure-table row "Data-directory protection at service start":** in the second column, prefix "The data directory itself is a reparse point, or".
  - **host-service "Startup sequence":** add the scenario "Data directory is a link". WHEN the service first starts and `%ProgramData%\Yagura` is a junction. THEN the daemon exits non-zero with `data_dir_not_protected` naming that path, and creates nothing behind the junction.
  - **tasks.md test map:** add the row `| host-service → Startup sequence | Data directory is a link | apps/yagurad/integration_test/service/startup_sequence_service_test.dart (`elevated`) | data_directory_is_a_link | 9 | red |`. Add `data_directory_is_a_link` to task 9.2's Verify list.
- **R3 (Moderate). The new fatal step has no test seam, so the in-process service-mode rows cannot pass in CI.** `data_directory_used_by_a_dev_daemon_first` (group 2) and `firewall_unavailable_at_startup` (group 10) start an in-process daemon in service mode, from `apps/yagurad/test/host/startup_sequence_test.dart`, non-elevated, on Windows CI. Under the amended Startup sequence that start must first set owner Administrators on the data directory. A non-elevated token cannot set that owner, so the start exits `data_dir_not_protected` before the database opens. Both rows fail for a reason unrelated to what they test. Unlike account setup, this step is fatal, so it cannot be ignored as a degraded flag. The test-map preamble lists fakes for SteamCMD, the process host and the firewall, but none for ACL writes. Fix:
  - **D6, at the end of "Data directory first":** append "The step runs behind a `DataDirProtector` interface. In-process daemon tests inject a fake that records the calls and can be set to fail, and only `elevated` rows use the real Win32 one."
  - **tasks.md test-map preamble:** change "(fake SteamCMD, fake process host and fake firewall where the real one is not needed)" to "(fake SteamCMD, fake process host, fake firewall and fake data-directory protector where the real one is not needed)".
  - **Task 9.2 Verify:** append "`data_directory_used_by_a_dev_daemon_first` still passes with the fake protector".

Suggestions (non-blocking):
- **S4. Inherited handles cross a privilege boundary.** `steam_process.dart` calls `CreateProcess` with handle inheritance on and no `PROC_THREAD_ATTRIBUTE_HANDLE_LIST`. Under `CreateProcessAsUserW` as `yagura-steam`, every inheritable daemon handle that exists at that moment is passed to the low-privilege process. That includes pipe ends of a concurrent `yagurad launch` or of another SteamCMD run. In D10 "Account", add "with inheritance limited to its three pipe ends (`STARTUPINFOEX` + `PROC_THREAD_ATTRIBUTE_HANDLE_LIST`)", and add the same to task 9.3.
- **S5. "Skipping instance directories" before the database is open.** The walk runs before instance records can be read. State the rule: "skipping every direct child of `<data>/instances` (instance directories, handled by the instance ACL migration after recovery)".
- **Baseline note (not this change).** ADR 0015's Decision still says "The launcher … starts the process … `YaguraSteam\Default` for SteamCMD". ADR 0014 and D10 have the daemon start SteamCMD itself. That belongs to the architecture-review round, not to this change.

- **Re-check R1:** fixed. D8 now says the `tar -xf` extraction is started by the daemon in the operation's kill-on-close job (D10).
- **Re-check R2:** fixed.
  - D6 "Data directory first" now opens the data directory with `FILE_OPEN_REPARSE_POINT` before `DataDirectory.prepare` creates anything. It exits `data_dir_not_protected` on a reparse point or a final-path mismatch.
  - The Failure-table row is prefixed as given.
  - The new host-service scenario is "Data directory is a link", with its test row `data_directory_is_a_link` in group 9 and in the Verify of task 9.2.
  - ADR 0015 states the same root check.
- **Re-check R3:** fixed. D6 ends with the `DataDirProtector` interface and the fake. The test-map preamble names the fake data-directory protector. Task 9.2 Verify ends "`data_directory_used_by_a_dev_daemon_first` still passes with the fake protector".
- **Re-check S4:** taken. D10 "Account" limits inheritance to the three pipe ends (`STARTUPINFOEX` + `PROC_THREAD_ATTRIBUTE_HANDLE_LIST`), and task 9.3 says the same.
- **Re-check S5:** taken, through the baseline re-check. D6 and ADR 0015 now say the walk sets the DACL on `<data>/instances` but does not descend into it.
- **Baseline-driven, second round:**
  - The `acl-layout` marker counts only if it is a no-follow regular file with one link, owned by SYSTEM or Administrators. A new scenario covers this, "Layout marker planted by a standard user", with its row.
  - Entries inherited below `<data>/steamcmd` and the content store are written from the parent's new DACL.
  - Task 1.1 now carries the architecture.md annotations.
  - ADR 0015 now says the logon module serves the launcher (game servers) and the daemon (SteamCMD).

### Second re-check (reviewer)

**R1-R3, S4, S5: confirmed against `git diff -- openspec/changes/m2-secure-remote-host/`.**
- **R1.** D8 carries the prescribed text word for word.
- **R2.** The D6 insertion, the Failure-table prefix, the scenario "Data directory is a link", its group-9 `elevated` row and its place in task 9.2's Verify are all as prescribed.
- **R3.** The `DataDirProtector` sentence ends D6, the test-map preamble names the fake protector, and task 9.2's Verify ends with the dev-first row.
- **S4.** Taken in D10 "Account" and task 9.3.
- **S5.** Taken: D6 and ADR 0015 set the DACL on `<data>/instances` and do not descend into it.

**Second-round delta: consistent except R4.** The following hold:
- **Marker rule.** It is read only after the root DACL is set. A file a user planted keeps the user as owner until the walk runs, so the ownership test separates it. "Layout marker planted by a standard user" asserts the outcome.
- **Inherited entries.** The entries for `<data>/steamcmd` and the content store match ADR 0015's ACL list and D10 "What it can write".
- **`<data>/instances` not descended.** This agrees with the instance migration and with the spec text "outside instance directories".
- **Failure-table row.** It matches the four host-service scenarios.
- **Test rows and groups.** All four new rows are `elevated` in group 9, and the group-9 "Covers" line names Startup sequence. The two in-process service-mode rows (groups 2 and 10) are covered by the preamble's fake protector.
- **D8 and D10.** They agree with ADR 0014 on the in-process start, the job, the pipes and the handle list.
- **Tasks.** Task 9.3 matches D10. Task 9.5 adds `data_dir_not_protected`. Task 1.1's line numbers 74, 168 and 169 are the only places in `openspec/architecture.md` that cite 0010 or 0013 outside the index rows.

Outstanding:

- **R4 (Moderate). The root check and the DACL write are separate opens, so the R2 junction swap is still possible as a race.**
  - **Why it still works.** D6 opens the data directory no-follow and checks it before `DataDirectory.prepare`. It sets the owner and DACL only "right after taking the lock", and nothing says the checked handle stays open in between. `prepare` creates the folders and `.write-test` by path, following links (`host/data_directory.dart:25-38`), and so does the lock.
  - **The attack.** A standard user who created `%ProgramData%\Yagura` owns it (`CREATOR OWNER` full) and may create folders in `%ProgramData%`. After the check passes, that user can rename the folder away and put a junction to a folder they own in its place.
  - **The consequence.** The R2 consequence returns: the SYSTEM-side layout, the lock and `yagura.db` land in a user-controlled folder, and the owner/DACL write on a no-follow handle lands on the link. The scenario "Data directory is a link" would pass, because it plants the junction before the start, while the race stays open.
  - **Fix:**
    - **design.md D6 "Data directory first".** Replace "the daemon opens the data directory with `FILE_OPEN_REPARSE_POINT` and exits `data_dir_not_protected` if it is a reparse point or its final path (`GetFinalPathNameByHandleW`) differs from the configured one; then, right after taking the lock and before the database is opened, the daemon sets owner Administrators and the protected DACL on the data directory." with "the daemon creates the data directory if it is absent, opens it with `FILE_OPEN_REPARSE_POINT` and without `FILE_SHARE_DELETE`, and exits `data_dir_not_protected` if it is a reparse point or its final path (`GetFinalPathNameByHandleW`) differs from the configured one. It keeps that handle open, so the directory cannot be renamed or replaced, and right after taking the lock and before the database is opened it sets owner Administrators and the protected DACL through that handle, then closes it."
    - **ADR 0015, root-check paragraph.** Make the same edit to "opens it with `FILE_OPEN_REPARSE_POINT` … Then, before the database is opened, it sets the owner (Administrators) and the protected DACL on the data directory." This belongs to the baseline round.

Suggestions (non-blocking):
- **S6. Task 1.1's Verify contradicts the index's Supersedes column.** The in-force table in `openspec/architecture.md` has a "Supersedes" column, so the new 0014 and 0015 rows will cite 0010 and 0013. Replace "and no line outside the superseded rows cites 0010 or 0013" with "and no line other than the Supersedes cells of the 0014 and 0015 rows cites 0010 or 0013".
- **S7 (user decision, threat model). A data directory a standard user pre-created is trusted in content, not only in ACLs.** D6 and "Data directory created by an earlier daemon" adopt an existing `yagura.db`, `plugins/` and settings, and only re-ACL them. A standard user who pre-creates `%ProgramData%\Yagura` can therefore also plant a database. The service then acts on that database as SYSTEM. Two examples:
  - instance rows pointing outside administrator-intended roots, which the instance ACL migration then grants to `yagura-srv`;
  - plugin manifests that game servers later run.

  Options:
  - **(a) Accept it and state it.** Document that the first service start trusts an existing data directory and that the admin must check it on a shared host. This costs nothing.
  - **(b) Refuse a foreign owner.** At the first service start, record the data directory's original owner and refuse an owner other than SYSTEM, Administrators or the installing admin unless `service install --adopt-data-dir` is given.
  - **(c) Create it at install.** Have the elevated `service install` create the data directory before any user can.

  I recommend (c) plus (a) for a pre-existing directory.

The machine-readable line above stays `no` until R4 is applied.

- **Second re-check R4:** fixed. D6 now uses the prescribed text. It creates the directory if it is absent, opens it no-follow without `FILE_SHARE_DELETE`, keeps the handle open through the lock, sets owner and DACL through that handle, then closes it. ADR 0015 states the same.
- **Second re-check S6:** taken. Task 1.1's Verify now reads "no line other than the Supersedes cells of the 0014 and 0015 rows cites 0010 or 0013".
- **Second re-check S7:** the user chose (a), "accept and document". Yagura targets a dedicated host with one administrator. D6 says the first service start trusts an existing data directory's contents. The operator docs tell an admin on a shared host to check or remove an existing data directory first. ADR 0015 Consequences records the same. The user kept the low-privilege account design; the attacker it guards against is a compromised server or mod, not another user.
- **User decision, test location:** `elevated` rows never run on the developer's desktop, because they create accounts, profiles, a service and firewall rules. They run only in a manual `workflow_dispatch` workflow `.github/workflows/elevated.yml` on a GitHub Windows runner, which runs as administrator. This changes the test-map preamble, tasks 1.4, 7.x, 8.1, 9.x, 10.x and 12.3, and the D-risk line. Task 10.2's 300-rule timing also moves to that workflow. `valheim` rows stay with the user.

### Final re-check (reviewer)

**Confirmed against `git diff -- openspec/changes/m2-secure-remote-host/`, ADR 0015 and `.github/workflows/elevated.yml`:**
- **R4.** The D6 text matches what was prescribed. It creates the directory if absent, opens it no-follow without `FILE_SHARE_DELETE`, keeps the handle open, sets the owner and DACL through it after the lock, then closes it. ADR 0015's root-check paragraph makes the same edit. It omits "then closes it", which changes nothing. With the handle held and no delete sharing, the directory cannot be renamed, so the R2 swap race is closed.
- **S6.** Task 1.1's Verify reads as prescribed.
- **S7 (a).** D6 states the behaviour accurately. The first service start trusts the existing database, plugins and settings and only re-protects them. Planted secret rows cannot be LocalSystem-DPAPI blobs, so the D3 scope rule still deletes them. ADR 0015 Consequences says the same.
- **Elevated workflow, file.** The workflow runs `pwsh tool/ci/outside-job.ps1 -Run 'Set-Location apps/yagurad; mise exec -- dart test --run-skipped --tags elevated'`. That is the same outside-job pattern as ci.yml's `windows` step, with the same toolchain, cache and `flutter pub get` steps, and it has a `workflow_dispatch`-only trigger.
- **Elevated workflow, wording.** The test-map preamble, tasks 1.4, 7.2, 8.1, 8.2, 9.2, 9.3, 10.3 and 12.3, and the design risk line agree with it. Task 12.2 excludes `elevated`.

**Outstanding (Moderate). The machine-readable line stays `no`:**

- **F1. The workflow runs no `elevated` test.** Every `elevated` row in the test map lives under `apps/yagurad/integration_test/`. `dart test` with no path argument loads only `test/` (package:test `test_core` 0.6.8 `runner/configuration.dart:128`, default paths `{'test'}`), and `apps/yagurad/dart_test.yaml` sets no `paths`. So `dart test --run-skipped --tags elevated` finds nothing and exits 79, "No tests match the requested tag selectors" (`runner.dart:150-155`, `executable.dart:160-162`). As a result, no `elevated` row of groups 7-10 or task 12.3 can turn green. The same default also leaves the `windows`-tagged row `not_elevated` (`integration_test/service/windows_service_install_and_control_test.dart`) out of ci.yml, although task 12.2 requires it green.
  - **Fix, task 1.4:** replace "and an `elevated` tag in `apps/yagurad/dart_test.yaml` (skipped by default, like `valheim`)," with "an `elevated` tag in `apps/yagurad/dart_test.yaml` (skipped by default, like `valheim`) and `paths: [test, integration_test]` in the same file, so every `dart test` in `apps/yagurad` (ci.yml and the `elevated` workflow) also loads `integration_test/`,". Then append to its Verify: ", and `dart test` in `apps/yagurad` loads tests under `integration_test/`". With this fix the workflow command stays as it is.
- **F2. The workflow cannot be started from this branch.** GitHub dispatches `workflow_dispatch` only for workflows present on the default branch. ci.yml's own header says so ("On-demand runs need this workflow on the default branch") and works around it with `push: branches: ['ci/**']`. `elevated.yml` is new and not on `main`, so `gh workflow run elevated.yml --ref feat/m2-secure-remote-host` fails. That leaves every `elevated` Verify in groups 7-10 unrunnable until the change merges, which is after those groups are due. Pick one fix:
  - **(a), recommended because it keeps the user's "`workflow_dispatch` only" decision.** In task 1.4, after "outside the runner's job.", insert: "Land `.github/workflows/elevated.yml` on `main` in its own pull request before group 7 starts, because `workflow_dispatch` runs only workflows that exist on the default branch; after that, `gh workflow run elevated.yml --ref <branch>` runs the branch's tests." Append to its Verify: ", and `gh workflow list` on `main` shows `Elevated`".
  - **(b)** Add `push: branches: ['elevated/**']` to `elevated.yml`'s `on:`, as ci.yml does. Then, in the test-map preamble, the design risk line and task 1.4, replace "`workflow_dispatch` only" with "started by hand: `workflow_dispatch`, or a push to an `elevated/<name>` branch until the workflow is on `main`".
- **F3. Task 10.2 still verifies `elevated` rows "locally".** `admins_own_rule_untouched` and `foreign_rule_inside_the_group` are `elevated` rows (`integration_test/firewall/windows_firewall_test.dart`). In task 10.2's Verify, replace "`admins_own_rule_untouched` and `foreign_rule_inside_the_group` pass locally." with "`admins_own_rule_untouched` and `foreign_rule_inside_the_group` pass in the `elevated` workflow."

Suggestions (non-blocking):
- **S8. Task 12.3, "from the compiled bundle".** The workflow builds no bundle; it runs `dart test` from source. Either add a bundle-build step before the test step, or replace "Run the `elevated` rows from the compiled bundle in the `elevated` workflow" with "Run the `elevated` rows in the `elevated` workflow (the service rows install a bundle they build themselves)".
- **S9. Task 1.3 (spike S2) still runs "on a local elevated Windows machine".** It registers a service and creates a temporary account, which is the reason the user gave for keeping `elevated` rows off the desktop. The user decision covers test rows, not the spike, so this needs the user. Either run S2 in a throwaway VM, or run it in the `elevated` workflow and say so in task 1.3.
- **S10. `apps/yagurad/dart_test.yaml` (owned by task 1.4).** The tag comment still says "run it from an elevated shell with `dart test --run-skipped -t elevated`". Replace it with "run only in the `elevated` workflow (`.github/workflows/elevated.yml`), never on a developer's desktop".
- **S11. No task writes the S7 operator note.** D6 says "The operator docs state this", but neither task 8.3 nor task 9.5 names it. In task 8.3, after "the pairing command printed at the end", add: ", and the note that the first service start trusts an existing `%ProgramData%\Yagura`, so an admin on a shared host checks or removes it before `service install`". Add "the shared-host note" to its Verify.

- **Final re-check F1:** fixed.
  - Task 1.4 now adds `paths: [test, integration_test]` to `apps/yagurad/dart_test.yaml` with the prescribed wording.
  - The working tree already has it, plus `apps/yagurad/integration_test/README.md`, because `dart test` fails to load a missing directory listed in `paths`.
  - Checked: `dart test test/host` passes with the new `paths`.
- **Final re-check F2:** fixed. `elevated.yml` also triggers on `push` to `elevated/**` branches, as `ci.yml` does with `ci/**`. The preamble, task 1.4 and the D-risk line say: start it with `workflow_dispatch` once it is on `main`, or push an `elevated/<name>` branch until then. Each push is still an outward action the user approves.
- **Final re-check F3:** fixed. Task 10.2's Verify now says "pass in the `elevated` workflow".
- **S8:** taken. Task 12.3 no longer says "from the compiled bundle". The tests build what they need, as M1's `windows` tests do.
- **S10:** taken. The `elevated` comment in `dart_test.yaml` now names the workflow and says these tests never run on a developer's desktop.
- **S11:** taken. Task 9.5's operator docs now include the shared-host note (D6).
- **S9:** whether spike S2 moves to the `elevated` workflow is the user's call; I've asked. Task 1.3 stays as written until they answer.

### Closing re-check (reviewer)

**F1-F3 hold. Checked against `git diff -- openspec/changes/m2-secure-remote-host/`, `apps/yagurad/dart_test.yaml`, `.github/workflows/elevated.yml` and `apps/yagurad/integration_test/README.md`:**
- **F1.** `dart_test.yaml` has `paths: [test, integration_test]`. `integration_test/` exists and holds only the README for now, so a no-argument `dart test` loads both directories. Task 1.4 carries the prescribed wording. The ci.yml steps pass no path arguments: `tool/test.dart` forwards only runner options, and the `windows` step runs bare `dart test`. So they pick up `integration_test/` too, and `elevated` tests stay skipped there through the tag's `skip`.
- **F2.** Option (b) is applied. `elevated.yml`'s `on:` has `workflow_dispatch` and `push: branches: ['elevated/**']`, and its header comment says how to start it. The test-map preamble (tasks.md:5), task 1.4 and the design risk line (design.md:389) use the same wording. `concurrency` cancels a superseded run on the same ref.
- **F3.** Task 10.2's Verify reads "pass in the `elevated` workflow", and its 300-rule timing runs there ("never on the developer's desktop").
- **S8, S10, S11.** Taken as stated. S11 landed in task 9.5 rather than 8.3, which is fine because 9.5 owns the operator docs on accounts.
- **S9.** Pending the user's answer. Not blocking.

**Outstanding (Moderate). The machine-readable line stays `no`:**

- **F4. design.md still tells the implementer to run elevated rows on a local machine.** This text predates this round. The user decision on test location made it wrong, and no earlier re-check caught it. It contradicts the risk line (design.md:389), the test-map preamble and tasks 1.4 and 10.2. An implementer who follows the Context section would run the rows that create accounts, a service and firewall rules on the developer's desktop, which is what the user ruled out.
  - **design.md:32 ("CI" bullet).** Replace "CI minutes are limited, so the elevated and service-level rows run on a Windows machine locally (exit criterion 1 allows this) and only the cheap rows run in CI." with "CI minutes are limited, so the regular CI workflow runs only the unprivileged rows; the elevated and service-level rows run only in the manual `elevated` workflow (`.github/workflows/elevated.yml`, on a GitHub Windows runner, which runs as administrator), never on a developer's desktop."
  - **design.md:165 (D11 "Triggers").** Replace "The first firewall task measures one script run on CI and locally;" with "The first firewall task measures one script run with 300 rules in the `elevated` workflow (task 10.2);".

Once F4 is applied as given, nothing else is open, and the line can be set to `yes` without another review round.

- **Closing re-check F4:** fixed. design.md "CI" (line 32) and D11 "Triggers" (line 165) now carry the prescribed text.
- **One more author edit, from the user's question about leftover accounts:** D6 `--purge-accounts` now deletes the accounts' profiles too (`DeleteProfileW`, after the processes using them have exited). A profile still in use is reported, and its account is kept so a later purge can finish. Task 8.2 names this.

### Final close (reviewer)

F4 is applied as prescribed: design.md "CI" (line 32) and D11 "Triggers" (line 165) match the given replacement text word for word, and no text in design.md or tasks.md now says `elevated` rows run locally (the test-map preamble, task 1.4, tasks 8.2, 9.3 and 10.2 and the risk line at design.md:389 all name the `elevated` workflow; task 1.3's "local elevated Windows machine" is spike S2, not an `elevated` row, and stays tracked as S9 pending the user's answer). The extra author edit is consistent: D6's `--purge-accounts` now deletes both accounts' profiles with `DeleteProfileW` after their processes exit, keeping and reporting an account whose profile is still in use, which fits D7's logon module (`LoadUserProfileW` creates those profiles) and the `servers_running` refusal; task 8.2 names it ("accounts, their profiles and secret rows"); and the host-service spec's "Windows service install and control" requirement only says `service uninstall` removes the service, so nothing there contradicts it. Nothing is open, so the line is set to `yes`.
