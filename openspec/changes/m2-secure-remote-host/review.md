# Review

## Metadata

- **Round:** 2
- **Prior round:** 1 REVISE (C1 critical; M1-M9 moderate; S1-S11 suggestions)
- **Reviewer:** fresh-context subagent (Claude Code, specwright-reviewer). Project skills loaded as guidance: dart-use-ffigen, dart-build-cli-app, flutter-apply-architecture-best-practices.
- **Reviewed:** `proposal.md`, `design.md` (TIER: FULL), every delta spec under `specs/` (daemon-security, desktop-client, firewall-rules, host-service, instance-lifecycle, plugin-hooks, plugin-manifest, steam-content), compared with `openspec/specs/<capability>/spec.md` (every MODIFIED/REMOVED header exists in the main spec; `openspec validate --strict` passes); `openspec/architecture.md`; ADRs 0007, 0010, 0011, 0012, 0013; `openspec/roadmap.md` (M2 exit criteria); `docs/protocol.md` (revision and secret rules); `proto/yagura/v1/{instances,system}.proto`; `schemas/plugin-manifest.v1.json` (port-name pattern); source: `cli/run_command.dart`, `host/daemon.dart`, `steam/steamcmd_bootstrap.dart`, `steam/steamcmd_service.dart`, `packages/yagura_plugin/lib/src/settings.dart`; round 1 review.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

### Round 1 findings re-checked

- **C1: fixed.** Running SteamCMD as `yagura-steam` (D10) closes the round-1 hole. A junction planted by any `yagura-srv` server now leads only to places the attacker could already write or that `yagura-steam` may write. The withdrawal and the tree scan are gone, and the steam-content scenarios assert the account and an access-denied write into System32. The new account opens a different boundary, which N2 covers.
- **M1: fixed.** The D11 regex matches `inst-<12 hex>` (`instance_manager.dart` id format) and every port name the schema allows (`^[a-z][a-z0-9_]*$`, `plugin-manifest.v1.json:142`). A round-trip test is named.
- **M2: fixed as asked.** The LocalSystem daemon creates the accounts, and secret rows carry `scope_sid`. The fallback the design gives for a scope mismatch is new and is wrong (N3).
- **M3: fixed.** D12 checks RestoreSnapshot, and the scenario "Restore from a stale view" was added. A smaller hole remains (S1).
- **M4: fixed.** SetSecret is the only write path, matching `docs/protocol.md:93` and `instances.proto:143`. `secret_via_set_secret` has a scenario.
- **M5: fixed.** "Error reasons have defined exits" is MODIFIED, with Acknowledge and Start-refused scenarios.
- **M6: fixed in intent.** The root is opened with reparse refusal and a final-path compare, `roots add` sets a protected DACL or fails `root_not_protected`, and scenarios were added. The ACL wording that removes DELETE on the instance directory breaks installs as written (N1).
- **M7: fixed.** The gate checks `now > not_after`, and the renewal THEN covers both outcomes.
- **M8: fixed for the service.** The design now uses `FILE_FLAG_FIRST_PIPE_INSTANCE`, the `admin_channel_squatted` notice, and a LocalSystem check on the server's token, with a scenario. This check has a side effect on console mode (N3).
- **M9: fixed.** `service configure --bind` and install `--bind` were added, and `DaemonConfig.apiPort` comes from the bind (`run_command.dart`, `daemon.dart:198`).
- **S1-S11: addressed** as the author lists. S4 was dropped along with the scan. S11 is recorded in the Mechanism Ledger, which is acceptable because no SDK headers are vendored and the binding layer is already hand-written.

## Findings

### Critical (blocking)

None.

### Moderate

**N1. The instance-directory ACL in D8/D10 and the planned ADR 0015 gives the accounts no access to the directory itself, and no instance created before the service gets the entries.** Three consequences:
- **Top-level writes are refused.** D8 and ADR 0015 say "modify is inherit-only, on its contents, with no `DELETE` on the directory itself". An inherit-only ACE does not apply to the object it sits on, and the root's ACE is "traverse only". So `yagura-steam` and `yagura-srv` get no `FILE_LIST_DIRECTORY`, `FILE_ADD_FILE` or `FILE_ADD_SUBDIRECTORY` on the instance directory. SteamCMD's first `app_update` must create `steamapps/` and the top-level files (Valheim's `valheim_server.exe` sits at the install root), and it fails with access denied. A server that lists or writes its install root also fails. Exit criterion 5 ("a game server runs as `yagura-srv`") cannot pass on an ACL built from this text.
  - Needed layout: one ACE on the directory itself granting read and execute, list, add file, add subdirectory and `FILE_DELETE_CHILD`, but not `DELETE`. Plus an `(OI)(CI)(IO)` modify ACE for the contents.
- **Instances created before the service get no entries.** D10 and the State table say the entries are "set at create, never withdrawn". Instances created by M1, or by M2 in console mode, live in the same default data directory (`run_command.dart:198-200`, `%ProgramData%\Yagura` in both modes) and get no account entries. After `service install`, their installs and starts as `yagura-steam`/`yagura-srv` fail. Nothing in D6's "repair at every service start" covers instance directories, only "the data-directory ACLs". The upgrade path from M1 (exit criterion 3, and 2 when the host already ran M1) is therefore broken.
- **The data-directory ACL walks the instance trees.** D6 sets the data-directory ACL at every service start through `SetNamedSecurityInfoW`. Unless each instance directory carries a protected DACL, that call propagates inherited entries through every instance tree under `<data>/instances`, whose contents `yagura-srv` controls. That is a SYSTEM tree walk outside InstanceFs on every start. Its cost grows with the tree size, and the design does not say how it treats planted reparse points.

**N2. The `yagura-steam` boundary has two gaps that let a `yagura-srv` server reach SYSTEM.** D10 rests on "SteamCMD only reaches places it may already write". Two gaps remain:
- **Shared desktop.** D7 has one logon path in the launcher that starts processes on window station and desktop `YaguraSrv\Default`. D10 sends SteamCMD through "the launcher's logon path (D7)", so by default SteamCMD and its console host share a desktop with every game server. Processes on one desktop at the same integrity level can inject into each other's GUI threads (global `SetWindowsHookEx` hooks, window messages to the console window). An account boundary that relies on the desktop being separate is then only as strong as `yagura-srv`, and `yagura-steam` holds SteamCMD's cached logins (ADR 0010: `config/config.vdf`; in M3, the account that owns DayZ).
- **SYSTEM writes in a directory `yagura-steam` can modify.** D10 gives `yagura-steam` modify on `<data>/steamcmd`, and the daemon (SYSTEM) does file work there without any link checks:
  - `steamcmd_bootstrap.dart:53-98` downloads `steamcmd.download`, runs `tar -xf` in the target and deletes the archive.
  - `steamcmd_service.dart:207,250` recursively deletes an installation directory.
  - The service writes the ready marker and `app_sizes.json` (`steamcmd_service.dart:60,202`).

  A junction or object-manager link planted there by `yagura-steam` turns those operations into SYSTEM writes or deletes anywhere. Combined with the shared desktop, this gives a path from `yagura-srv` to `yagura-steam` to SYSTEM: the host-takeover harm the ledger row for D10 names. InstanceFs (D8) covers only instance directories.

**N3. The `scope_sid` fallback destroys an admin's instances on a common path, and non-dev console mode cannot be paired.**
- **Console identity blocks the service.** D3 and the Startup sequence open the secret store and create the identity on every start, with no `--dev` exemption. Console mode runs as the logged-in user and uses the same default data directory as the service (`run_command.dart:198-200`). So anyone who runs the M2 daemon from a console once (the dev workflow, or an M1 user trying M2 before installing) stores the CA key under their own `scope_sid`. The service then exits `secret_store_unavailable` at every start.
- **The stated fix loses instances.** Flow & State Gaps says the fix is "a fresh data directory", which abandons every instance registration and snapshot. Its claim that this "needs a deliberate reuse" is false: the default directory is the same in both modes.
- **The mismatched rows are not worth keeping.** They cannot be decrypted by LocalSystem anyway. Account passwords are already re-created (D7), the CA can be re-issued at the cost of re-pairing, and secret settings can be re-entered. Refusing the whole directory is more destructive than necessary.
- **Non-dev console mode is a dead end.** With M8's fix, the CLI trusts the admin pipe only when the server's token user is LocalSystem (D5). A console daemon started without `--dev` therefore opens an mTLS listener that no device can ever enroll in: `yagurad pair` always fails `admin_channel_untrusted`. The proposal's BREAKING bullet ("without `--dev` the daemon now starts a secure listener") describes a mode that cannot be used, and that mode still writes user-scoped identity rows (the point above).

**N4. Spec and design disagree in four places, and one requirement cannot be asserted.**
- **Service install failure.** The Failure table row "Service install" says "a failed account creation leaves no service registered". D6 now creates accounts in the daemon after the service is registered and started, and treats a failure as a degraded step.
- **Firewall in console mode.** firewall-rules ("Owned rules derived from instance ports", "Reconcile desired and actual rules") and host-service "Startup sequence" ("reconcile the firewall") apply unconditionally. D11 runs the reconciler only with `--service` and says console mode reports the firewall "not managed". A console-mode run violates the spec as written. steam-content says "on a host where the service is installed", while D10 says "with `--service`".
- **Superseded ADR cited.** host-service "Game servers run under a low-privilege account" cites "the ADR 0013 directory permissions: instance directory read-write". This change supersedes 0013 with 0015, which takes `DELETE` away from the directory, so after archive the main spec would cite a superseded ADR. The instance-lifecycle scenario "Game-server account access set" also does not mention `yagura-steam`.
- **Unassertable requirement.** steam-content's requirement says the account "can write only to SteamCMD installations and instance directories". A standard local account can also write its own profile (the Risks list relies on it for SteamCMD's temp folder), `C:\Users\Public` and folders that Users may create in `%ProgramData%`. As written, the requirement is false and cannot be asserted. The System32 scenario itself is fine.

### Suggestions

- **S1. Restore revision timing.** D12 increments the revision "when it completes". Two restores sent with the same revision both pass the check while the first is still queued, which is the lost-update case M3 targets. Increment when the request is accepted, in the same transaction that creates the operation.
- **S2. Rotation when both binds fail.** If the port itself is taken between closing the listener and serving it again, the fallback with the old certificate fails too. The daemon then stays alive with no listener, and SCM never restarts it. Exit non-zero when both binds fail.
- **S3. `service configure --bind` validation.** Check the new port against instance ports over the admin pipe. Otherwise a server that survived the restart and holds that port makes the next service start fail to bind.
- **S4. Account lifecycle.**
  - Make the password encoding of the 32 random bytes cover all four character classes and stay under 127 characters. Windows Server and domain-joined hosts enforce complexity by default, and a hex or base64 string can be refused, which makes every launch fail `launch_logon_failed`.
  - On repair, also remove any group membership beyond Users.
  - State what `service uninstall` does with the accounts, their logon rights and their secret rows.
- **S5. Health fields.** "Account setup at service start" is reported through `GetHealth`, but `DaemonHealth` (`system.proto:31-43`) has no field for it. Add it (for example `service_accounts_ok`) to Impact. Say how console mode reports the firewall and `steam_account: not_managed` (the existing `not_built` list fits).
- **S6. Required secrets and the create flow.**
  - `settings.dart:83-84` validates secrets before the `required` check. With values arriving only through SetSecret after CreateInstance, a `required` secret needs a defined check, for example at Start with `secret_required`.
  - Add a CreateInstance-with-value scenario for `secret_via_set_secret`.
  - Add a desktop scenario for creating an instance with a secret, which calls SetSecret after CreateInstance.
- **S7. Scenario actor.** instance-lifecycle "Instance directory replaced by a junction" has "the game-server account renames an instance directory away". ADR 0015 and the admin-only roots make that impossible for the account. Reword it as "the instance directory is replaced by a junction (for example on a root created before M2)", so the WHEN can be set up.
- **S8. D8 caller list.** `steamcmd_service.dart:135` (create the install directory) and `_recordSize` (`:186-188`, list the instance tree) touch instance paths with `dart:io`. Add them to "Callers moved" so the enforcement test is not a surprise.
- **S9. architecture.md in Impact.** The component diagram (SteamCMD under LocalSystem), the secrets row (`yagura-steam` password), the ADR table (0014, 0015, superseded 0010 and 0013) and the error-reason table all change. Impact lists only the error table.
- **S10. Reconcile wait bound.** An operation queued behind a running reconcile can wait up to 60 s (30 s for the running reconcile plus 30 s for its own). State the bound, or the warning scenarios' timing is ambiguous.

## Verdict

C1 and M1-M9 are resolved, and no finding is blocking. The new findings are text-level corrections to the ACL layout, the SteamCMD account's isolation, the scope-mismatch recovery, and spec/design consistency. Each has a precise fix below.

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **N1, D8/D10/State table/ADR 0015 text.**
   - Define the instance-directory DACL as protected (SYSTEM and Administrators full), with two entries for each of `yagura-srv` and `yagura-steam`:
     - one on the directory itself granting read and execute, list, add file, add subdirectory and `FILE_DELETE_CHILD`, without `DELETE`;
     - one `(OI)(CI)(IO)` modify entry for the contents.
   - In D6, add that each service-mode start applies this DACL to every existing instance directory that lacks it, covering M1 and console-created instances. This uses no tree propagation: the instance DACL is protected, so data-directory propagation stops at it. State that ACL application never walks into instance contents.
   - Add an instance-lifecycle or host-service scenario: an instance created in console mode, then started after `service install`, runs as `yagura-srv`.
2. **N2, D7/D10 and the ledger.**
   - Run SteamCMD on its own window station and desktop (for example `YaguraSteam\Default`), not on `YaguraSrv\Default`.
   - Make SYSTEM-side file work in `<data>/steamcmd` safe:
     - the SteamCMD bootstrap (download, extract, cleanup of a failed installation) runs as `yagura-steam`, or its delete goes through a no-follow walk;
     - the ready marker and app sizes move to a SYSTEM-only location (the database or a SYSTEM-only folder).
   - Add a steam-content scenario that asserts SteamCMD's desktop is not the game servers' desktop.
3. **N3, D3/D5/Flow & State Gaps/proposal.**
   - Replace "the fix is a fresh data directory" with a recovery that keeps instances. When the service finds rows with a foreign `scope_sid`, it:
     - deletes them in one transaction;
     - re-creates the identity (devices from the old CA are revoked, re-pair needed) and the account passwords;
     - marks affected secret settings unset;
     - raises a notice naming the instances.
   - A console daemon that finds LocalSystem-scoped rows still exits `secret_store_unavailable` and changes nothing.
   - Delete the "needs a deliberate reuse" sentence.
   - State what console mode without `--dev` does, and add a spec scenario for it. Either it refuses to start (for example `service_mode_required`, updating the proposal's BREAKING bullet), or name how it is paired despite D5's LocalSystem check.
   - Add a host-service scenario: a data directory used once by a console daemon, then by the service, starts the service with instances kept and the notice raised.
4. **N4, spec/design consistency.**
   - Fix the Failure table row "Service install" to match D6: accounts are created by the daemon after registration, and a failure is a degraded step.
   - Scope firewall-rules' instance-rule and reconcile requirements and host-service "Startup sequence" to service mode (or "where the service is installed"), matching D11.
   - Use the same qualifier in steam-content and D10.
   - In host-service "Game servers run under a low-privilege account", cite ADR 0015 and its layout instead of ADR 0013's "instance directory read-write".
   - In the scenario "Game-server account access set", also assert `yagura-steam` access.
   - Reword steam-content's requirement sentence to an assertable bound, for example "cannot write to system folders or to the data directory outside SteamCMD installations".

**Re-check of Required Changes (round 2 follow-up):** N2, N3 and N4 are applied correctly in proposal.md, design.md and the specs. N1 was open after the first re-check (below). On the second re-check it is resolved: D6 (`design.md:93`) and D10 (`design.md:141`) now write every DACL with `SetKernelObjectSecurity` on the no-follow handle, which does not propagate. Inherited entries on existing children are written only by the no-follow walk, one handle at a time.

- **N1, still missing.** D6 (`design.md:93`) and D10's "ACL mechanism" (`design.md:141`) say every DACL is set with `SetSecurityInfo` on a no-follow handle, "which does not propagate to existing children". That is false. Microsoft's `SetSecurityInfo` documentation says the system propagates inheritable ACEs to existing child objects (just as `SetNamedSecurityInfo` does), unless the handle was opened with `MAXIMUM_ALLOWED`. So two operations still walk a tree as SYSTEM through the ACL library, outside the InstanceFs/ConfinedFs walk:
  - applying the instance DACL to an older instance's directory, which walks its yagura-srv-controlled contents before the InstanceFs walk runs;
  - the data-directory and `<data>/instances` DACLs set at every service start.

  Required: set descriptors with a non-propagating call (`SetFileSecurityW`, or `SetKernelObjectSecurity`/`NtSetSecurityObject` on the no-follow handle), and compute inherited entries for existing children only through the InstanceFs/ConfinedFs no-follow walk. Then correct the sentence in D6 and D10 accordingly.

CHANGES_APPLIED: yes

## Rebuttals

<!-- Author: fixed (cite) or rebutted (reason) per finding. -->

- **N1 fixed.** Instance DACL defined in D10 (protected; per account a directory-itself entry without `DELETE` plus `(OI)(CI)(IO)` modify). D6 applies DACLs with `SetSecurityInfo` on no-follow handles (no propagation), and migrates older instances once via `instances.acl_layout` and the InstanceFs walk (`acl_migration_failed`). host-service scenario "Instance created before the service"; instance-lifecycle "Game-server account access set" updated; ADR 0015 summary in ADRs updated.
- **N2 fixed.** D7: `YaguraSteam\Default` for SteamCMD. D8: `ConfinedFs` walk rooted at `<data>/steamcmd` for download, cleanup and delete; `tar` runs as `yagura-steam`; ready marker and app sizes move to the database. steam-content scenario "SteamCMD separated from game servers".
- **N3 fixed.** D3: service mode deletes foreign-scope rows, re-creates identity (devices revoked) and passwords, unsets secret settings, notice `secrets_reset`; dev mode exits unchanged. "Deliberate reuse" removed. Console without `--dev` exits `service_mode_required` (D5, daemon-security MODIFIED "Development mode is localhost only", proposal BREAKING bullet). host-service scenario "Data directory used by a dev daemon first".
- **N4 fixed.** Failure row "Service install" matches D6; firewall-rules, host-service Startup sequence, steam-content and D10/D11 all use "service mode"; host-service cites ADR 0015; scenario asserts `yagura-steam`; steam-content requirement reworded to an assertable bound.
- **Suggestions applied:** S1 (D12), S2 (D4, failure table), S3 (D6 `port_conflict`), S4 (D6 uninstall, D7 password encoding and groups), S5 (`service_accounts_ok` in Impact, `not_built` in D7/D11), S6 (plugin-manifest "Required secrets are checked at start", create-with-value and desktop create scenarios, D3), S7 (scenario reworded), S8 (D8 callers), S9 (proposal Impact: Architecture), S10 (D11, resource bounds).
- **N1 re-check fixed.** D6 and D10 now write every DACL with `SetKernelObjectSecurity` on the no-follow handle (no propagation), and inherited entries on existing children are written only by the no-follow walk (`design.md:93`, D10 ACL mechanism).
