# Review

## Metadata

- **Round:** 3
- **Prior round:** Round 2: APPROVE_WITH_CHANGES, all 11 Required Changes applied and re-checked (M1 baseline).
- **Reviewer:** fresh-context subagent (Claude Code, specwright-reviewer). Project skills named: none.
- **Reviewed:**
  - Subject: `docs/adr/0014-steamcmd-runs-as-a-low-privilege-account.md` (proposed, supersedes 0010) and `docs/adr/0015-game-server-account-and-directory-acls.md` (proposed, supersedes 0013), compared with `docs/adr/0010-steamcmd-non-interactive.md` and `docs/adr/0013-game-servers-run-as-a-low-privilege-account.md`.
  - The decisions they record: `openspec/changes/m2-secure-remote-host/design.md` (D5, D6, D7, D8, D10), its `review.md` (round 2), and the delta specs `specs/host-service/spec.md`, `specs/steam-content/spec.md`, `specs/instance-lifecycle/spec.md`.
  - Baseline: `openspec/architecture.md`, `openspec/strategy.md`, in-force ADRs 0005, 0009, 0011, 0012 (others skimmed for references), the round 1-2 baseline review (`git show HEAD:openspec/architecture-review.md`).
  - Source used as evidence: `apps/yagurad/lib/src/host/data_directory.dart` (`prepare`), `host/daemon.dart:147-165` (startup order), `process/launcher_modes.dart:20-60` (`yagurad launch`), `steam/steam_process.dart:280-330` (SteamCMD spawn), `steam/steamcmd_service.dart:355-370`.
  - Host check: `icacls C:\ProgramData` (read-only) on this Windows 11 machine.
  - Review rules: `openspec/schemas/specwright/schema.yaml` (`review` instruction) and `templates/review.md`.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes) voids it. -->

## Findings

The two ADRs record the round-2 design-review outcome faithfully. SteamCMD now runs under its own account on its own desktop, the instance-directory DACL omits `DELETE`, ACLs are written without propagation, and the no-follow walk covers `<data>/steamcmd`. The tree-scan race that ADR 0010 left open is closed. The account model itself is sound. The findings below cover what the new text claims but does not deliver, and where it conflicts with in-force ADRs.

### Critical (blocking)

**C1. The data-directory DACL never reaches the directory's existing contents, which keep the `Users` entries inherited from `%ProgramData%`. Both accounts are members of `Users`.** (ADR 0015 "ACLs" and the `SetKernelObjectSecurity` paragraph; ADR 0014 "it has nothing on ... the rest of the data directory")

- **What the ADR says.** Every DACL is written with `SetKernelObjectSecurity`, "which changes only that object", and "inherited entries on existing children are written only by the daemon's no-follow walk". That walk is defined only for instance directories ("set when an instance is created, or once at the first service start for an instance created earlier"). Nothing rewrites the inherited entries on the rest of the data directory.
- **What exists when the DACL is applied.** `DataDirectory.prepare` (`host/data_directory.dart`) creates `steamcmd/`, `plugins/`, `instances/`, `snapshots/` and `logs/`, and `Daemon.start` (`host/daemon.dart:147-165`) creates the lock file and `yagura.db`. Both run before any ACL step, and the Startup-sequence spec puts "set up the service accounts and directory permissions" after recovery. This is true on a fresh install as well as on an M1 or `--dev` upgrade.
- **What those children inherit.** `icacls C:\ProgramData` on this host shows `BUILTIN\Users:(OI)(CI)(RX)`, `BUILTIN\Users:(CI)(WD,AD,WEA,WA)` and `CREATOR OWNER:(OI)(CI)(IO)(F)`. Because the protected DACL on `<data>` is never propagated, these entries stay on every child.
- **Consequences** for `yagura-srv` and `yagura-steam` (Users-only membership, ADR 0015):
  - **Reads.** They can read `yagura.db`, every instance's snapshots, the daemon logs and the plugins. The host-service scenario "Server process identity ... cannot open `yagura.db`" fails on every host.
  - **Planted links outside any confined walk.** They can create subdirectories in `snapshots/`, `logs/`, `plugins/` and each existing SteamCMD installation, and, as `CREATOR OWNER`, turn them into junctions. Example: a server pre-creates `snapshots/<its instance id>` as a junction to `C:\Windows\System32`. The next `pre_update` snapshot, written by SYSTEM, copies files the server controls to the junction's target. That is a SYSTEM file write with chosen content, the escalation ADR 0013 and 0015 exist to prevent. ConfinedFs covers only instance directories and `<data>/steamcmd`.
  - **Code as `yagura-steam`.** A `yagura-srv` server can plant DLLs in an existing SteamCMD installation and get code running as `yagura-steam`.
- **Owners keep control of the DACL.** An object's owner keeps implicit `WRITE_DAC`, and the ADR never sets the owner. `yagurad roots add D:\servers` on a folder a standard user created leaves that user as owner, and the user can restore their own write access afterwards. ADR 0015's "Only administrators can create or rename entries in a root" then does not hold.

### Moderate

**M1. ADR 0014 starts SteamCMD "through the launcher's logon path", but that launcher is built to escape the daemon's job, so SteamCMD would not die with the daemon. This also contradicts ADR 0009.**
- **The launcher's design.** ADR 0009 step 1 and `process/launcher_modes.dart:36-40` start the launched process with `CREATE_BREAKAWAY_FROM_JOB`, and the launcher exits after printing the PID.
- **What SteamCMD needs.** ADR 0014's own first paragraph keeps SteamCMD "inside a kill-on-close job object owned by the daemon". The daemon also needs SteamCMD's stdout and stderr on its own pipes, and its exit code, for progress, Guard detection and the stall timer. Today `steam/steam_process.dart:300-327` does this in-process: `CREATE_SUSPENDED`, assignment to the job, resume.
- **ADR 0009 says otherwise.** It states that SteamCMD "runs as a child in a kill-on-close job object owned by the daemon".
- **Consequence.** Taken literally, ADR 0014 puts SteamCMD outside the job, so it survives a daemon crash and leaves only the startup sweep to clean up. The daemon also loses the output stream it parses.
- **Fix.** The daemon calls `LogonUserW` and `CreateProcessAsUserW` itself; LocalSystem holds the privileges this needs. Only the profile, environment and desktop setup is shared with the launcher.

**M2. ADR 0014 says a planted junction "gains nothing". That is true for system folders, but not for what `yagura-steam` itself can write.**
- **What a server can redirect.** A `yagura-srv` server can plant a junction, or an object-manager symlink through a `\RPC Control` mount point, in any instance directory. It can point it at `<data>/steamcmd/<installation>` or at `yagura-steam`'s profile. Junction creation needs no access to the target.
- **What SteamCMD then does.** SteamCMD's writes and deletes during that instance's update land there: SteamCMD binaries, `appcache`, `config/config.vdf`.
- **Consequence.** A game server can corrupt every SteamCMD installation or destroy cached logins. The admin then has to log in again, Steam Guard included, for the DayZ-owning account. The steam-content spec already carves out "SteamCMD installations" from its guarantee, so the ADR's wording claims more than the spec does.
- **Fix.** State the real bound and accept it explicitly.

**M3. Neither ADR says how workshop content moves from a `yagura-steam`-writable tree into the immutable content store (ADR 0005).**
- **The gap.** ADR 0015 gives `yagura-steam` no entry on the content store. ADR 0005 acquires into `content/.staging/<op-id>/` and publishes by renaming. `workshop_download_item` writes under `steamapps/workshop` of its install directory.
- **Consequence, either way it is built:**
  - SteamCMD downloads straight into `content/.staging`, and every M3 workshop acquisition fails with access denied;
  - or the daemon (SYSTEM) moves the tree out of `<data>/steamcmd`, which ADR 0014's list of no-follow work does not include. A junction left in that tree is then published into "immutable" content, pointing back at space `yagura-steam` writes. The DayZ key copy into `keys/` (SYSTEM) later reads through it.
- **Why decide now.** ADR 0005's reversal cost is high, and this is the moment the account boundary is fixed.

**M4. ADR 0015 contradicts ADR 0012, which stays in force, and leaves stale references in ADR 0009.**
- **ADR 0012.** It says "install also creates the game-server account (ADR 0013), sets directory ACLs". ADR 0015 moves both to the service-mode daemon "(not the installer)", for a concrete reason: an installer running as the admin user stores the password in the admin's DPAPI scope, which LocalSystem cannot read, so every launch would fail `launch_logon_failed`. An implementer who reads ADR 0012 rebuilds exactly that failure.
- **ADR 0009.** It cites ADR 0013 for the account and ADR 0010 for SteamCMD. Once those are superseded, both citations point at superseded ADRs.

**M5. ADR 0014 leaves SteamCMD's account on Linux unspecified, while ADR 0015 runs Linux servers as `yagura-srv` "with the same directory rules".**
- **The gap.** ADR 0014 covers service mode (Windows) and console mode only.
- **Consequence.** An M5 implementation that follows the ADRs as written runs SteamCMD as the root daemon into trees `yagura-srv` can write. On Linux any user can create symlinks, so the round-2 C1 hole comes back in its easiest form.

### Suggestions

**S1. Window-station and desktop ACLs per logon SID.** ADR 0015 grants "the account's logon SID", but each `LogonUserW` call creates a new logon SID.
- With several servers, or crash restarts, the launcher either replaces the DACL (an earlier server loses access to objects it opens later) or appends entries (an ACL is capped at 64 KiB, so after a few thousand launches `launch_failed` appears).
- Fix: state that the launcher adds the new logon SID at launch and removes it when that process exits, or grant the account SID instead.

**S2. Name the logon rights.** "Interactive and remote logon denied" is ambiguous: "remote" can mean RDP or network logon. List the rights: `SeDenyInteractiveLogonRight`, `SeDenyRemoteInteractiveLogonRight`, `SeDenyNetworkLogonRight`, plus `SeBatchLogonRight`.

**S3. Password repair without a failed logon.** "A stored password that no longer matches is reset" implies a test logon. On a mismatch that test is a failed logon (event 4625) and counts toward the lockout threshold. Setting the stored password unconditionally at every service start (`NetUserSetInfo` level 1003) needs no test and gives the same result.

## Verdict

C1 is a defect in ADR 0015's ACL mechanism with a precise text fix, and M1-M5 are text corrections. All six are listed below as exact edits.

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **C1. ADR 0015, Decision.**
   - **Add after the ACL list:** "In service mode, before the database is opened, the daemon sets the owner (Administrators) and the protected DACL on the data directory. While its recorded data-directory layout version is below the current one, it walks the data directory with the no-follow walk. The walk skips instance directories, which get their own DACL below. For every other child it sets the owner to Administrators and writes the inherited SYSTEM/Administrators entries plus the explicit `<data>/steamcmd` and content-store entries. A reparse point met there fails startup with `data_dir_not_protected` naming the path."
   - **Owner, every DACL write.** Change "Every DACL is written with `SetKernelObjectSecurity` ..." to "Every DACL is written, together with owner Administrators (`OWNER_SECURITY_INFORMATION`), with `SetKernelObjectSecurity` ...". This covers roots added with `roots add`, `<data>/steamcmd` and instance directories.
   - **ADR 0014, matching sentence.** Make "it has nothing on system folders or the rest of the data directory" rely on the walk above.
   - **Author follow-up, outside this review's files:** move the data-directory protection before the database open in design D6, the host-service Startup-sequence requirement and task 9.2.
2. **M1. ADR 0014, second Decision paragraph.**
   - **Replace** "starts as a dedicated local account `yagura-steam` through the launcher's logon path (`LogonUserW(LOGON32_LOGON_BATCH)` + `CreateProcessAsUserW`, ADR 0015)" **with** "starts as a dedicated local account `yagura-steam`. The daemon itself calls `LogonUserW(LOGON32_LOGON_BATCH)` and `CreateProcessAsUserW`, with the profile, environment and desktop setup of ADR 0015, `CREATE_SUSPENDED`, and assignment to the operation's kill-on-close job before the process resumes; stdout and stderr go to pipes the daemon reads. It does not go through `yagurad launch`, whose job breakaway and early exit serve game servers (ADR 0009)."
   - **Follow-up:** align design D10 and task 9.3.
3. **M2. ADR 0014.**
   - **Replace** "A junction planted by any `yagura-srv` server therefore gains nothing: a write through it into a system folder fails with access denied." **with** "A link planted by a `yagura-srv` process can redirect SteamCMD's writes and deletes only to places `yagura-steam` may write. Writes into system folders and the rest of the data directory fail with access denied. SteamCMD installations and `yagura-steam`'s profile can still be reached."
   - **Add a Consequences bullet:** "A game server can corrupt a SteamCMD installation or delete a cached login through a planted link during an update. The installation is bootstrapped again and the admin logs in again (Steam Guard included). The token stays unreadable to `yagura-srv`."
4. **M3. ADR 0014, third Decision paragraph.** Add: "Workshop items are downloaded by SteamCMD as `yagura-steam` into a tree it can write. The daemon publishes them into the content store (ADR 0005) by a no-follow copy into `content/.staging/<op-id>/` that refuses any reparse point, then renames the copy into place. It never renames a tree `yagura-steam` can still write. `yagura-steam` has no entry on the content store."
5. **M4. ADR 0015, Context.**
   - **Add:** "It also replaces ADR 0012's statement that `service install` creates the game-server account and sets directory ACLs. Both are done by the service-mode daemon at every start, because only LocalSystem can keep the passwords in its own DPAPI scope (ADR 0011)."
   - **In `openspec/architecture.md`'s in-force ADR table** (task 1.1), annotate the 0012 row with "account and ACL setup: see 0015", and the 0009 row with "account: 0015; SteamCMD: 0014".
6. **M5. ADR 0014, after the console-mode sentence.** Add: "On Linux, SteamCMD runs as the system user `yagura-steam` with the same directory rules as ADR 0015, never as the daemon's root user."

<!-- yes (applied, and re-checked by the reviewer - only the reviewer sets it) | no (outstanding) | n/a (any other verdict) -->
CHANGES_APPLIED: yes

## Rebuttals

<!-- Author: fixed (cite) or rebutted (reason) per finding. A Critical/Moderate rebuttal counts only once marked "accepted by reviewer". -->

- **C1:** fixed. ADR 0015 adds a paragraph: before the database opens, the daemon sets the owner and protected DACL on the data directory, then runs a one-time no-follow walk skipping instance directories. A reparse point fails startup with `data_dir_not_protected`. Every DACL write now also sets owner Administrators. ADR 0014's "nothing on ... the rest of the data directory" sentence now cites that walk. The author follow-up is done in the change:
  - design D6 has a "Data directory first" paragraph and a Failure-table row;
  - host-service "Startup sequence" gains the step and the scenarios "Data directory created by an earlier daemon" and "Link in the data directory at first service start";
  - task 9.2 is updated.
- **M1:** fixed. ADR 0014's second paragraph has the replacement text. Design D10 and task 9.3 are aligned: the daemon starts SteamCMD itself, suspended, in the job, with pipes.
- **M2:** fixed. The replacement sentence and the Consequences bullet are in ADR 0014. D10 states the same bound.
- **M3:** fixed. The workshop publish paragraph is in ADR 0014, with a matching D10 bullet ("Workshop content (M3)").
- **M4:** fixed. The ADR 0012 replacement paragraph is in ADR 0015's Context. The 0012 and 0009 row annotations go into `openspec/architecture.md` when task 1.1 accepts the ADRs.
- **M5:** fixed. The Linux sentence follows the console-mode sentence in ADR 0014. D10 has a Linux (M5) bullet.
- **S1:** taken. Window stations and desktops are ACL'd to the account SID, not the per-logon SID, in ADR 0014, ADR 0015 and D7. Spike S2 does the same.
- **S2:** taken. ADR 0015 and D7 name `SeBatchLogonRight`, `SeDenyInteractiveLogonRight`, `SeDenyRemoteInteractiveLogonRight` and `SeDenyNetworkLogonRight`.
- **S3:** taken. The password is set with `NetUserSetInfo` level 1003 at every start, without a test logon (ADR 0015, D7).

### Re-check (reviewer)

Verified as applied and consistent with ADRs 0005, 0009, 0011 and 0012 and with the change:

- **M1.** ADR 0014 paragraph 2 has the replacement text. D10 "Account" and task 9.3 match it: the daemon starts SteamCMD itself, `CREATE_SUSPENDED`, in the job, with pipes. That agrees with ADR 0009's "child in a kill-on-close job object owned by the daemon".
- **M2.** The replacement sentence and the Consequences bullet are in ADR 0014. D10 "What it can write" states the same accepted bound.
- **M3.** ADR 0014 paragraph 4 and the D10 "Workshop content (M3)" bullet match ADR 0005's staging-and-rename.
- **M5.** The Linux sentence and the D10 "Linux (M5)" bullet are present.
- **C1, the parts that are applied.** The ADR 0015 paragraph, owner Administrators on every DACL write (ADR 0015 and D6), and the ADR 0014 sentence citing the walk are in place. The D6 "Data directory first" paragraph, the Failure-table row, the Startup-sequence step and its two scenarios, the test rows, and tasks 9.2 and 9.5 (`data_dir_not_protected`) are in place too. The order (lock, protect, then open the database) fits `daemon.dart:147-165`. A fresh install and an M1 upgrade both run the walk, which catches what `prepare`, the lock file and `yagura.db` inherited.
- **S1-S3** are taken in ADR 0015 and D7.

Still outstanding (CHANGES_APPLIED stays `no`):

1. **C1, the walk is gated on a marker that any local user may have planted.** Before the first service start, `<data>` still carries `BUILTIN\Users:(CI)(WD,AD,WEA,WA)` from `%ProgramData%`, so any `Users` process can create `<data>/acl-layout`. That includes an M1 or `--dev` game server, which runs as the logged-in user. If the planted file holds the current version, the daemon protects `<data>` itself but skips the walk. `yagura.db`, `snapshots/`, `logs/`, `plugins/` and `steamcmd/` then keep their `Users` entries, and that user owns the marker. This is the original C1 again. D6's "the directory is SYSTEM/Administrators-only by then" covers only markers written later, not one that already exists.
   - **Fix, ADR 0015 paragraph "In service mode, before the database is opened ...":** after "While its recorded data-directory layout version is below the current one", insert: "(the version is read from `<data>/acl-layout`, and is taken as 0 unless that file is opened without following reparse points, is a regular file with one link, and is owned by SYSTEM or Administrators)".
   - **Fix, design D6 "Data directory first":** after "(a one-line file written atomically after a successful walk; ...)", add the same rule. Then add a host-service scenario: "**WHEN** the service first starts on a data directory where a standard user created `acl-layout` with the current version **THEN** the walk still runs and `yagura.db` grants nothing to `Users`". Add its test row to group 9.
2. **C1, "skips instance directories" cannot be done before the database opens.** The walk runs before `yagura.db` is opened, so it cannot know which children of `<data>/instances` are instances. If it descends into them, it overwrites their protected per-instance DACL with inherited-only entries. It also turns a junction in an M1 instance, which should give the per-instance `acl_migration_failed`, into a fatal `data_dir_not_protected` for the whole service.
   - **Fix, ADR 0015 and D6:** replace "The walk skips instance directories, which get their own DACL below." (D6: "skipping instance directories (their own DACL, above)") with "The walk sets the DACL on `<data>/instances` itself but does not descend into it; instance directories get their own DACL and migration (above), once the database is open."
3. **C1, the walk's inherited entries under `<data>/steamcmd` and the content store.** "writes the inherited SYSTEM/Administrators entries plus the explicit `<data>/steamcmd` and content-store entries" puts only SYSTEM/Administrators on descendants. An existing M1 SteamCMD installation then gives `yagura-steam` no write access, and its first update after the upgrade fails with access denied. The same applies to `yagura-srv` reading existing content. The ambiguity is in this review's own prescribed text.
   - **Fix, ADR 0015 and D6:** replace that clause with "writes the entries it inherits from its parent's new DACL (SYSTEM/Administrators; plus `yagura-steam` modify below `<data>/steamcmd` and `yagura-srv` read and execute below the content store), and sets the explicit DACLs of `<data>/steamcmd` and the content store on those directories themselves".
4. **M4, the deferral to task 1.1 is acceptable only if task 1.1 records it.** The architecture table lists accepted ADRs, and 0014/0015 are only proposed until this review passes, so making the annotation at acceptance is right. Task 1.1 (tasks.md:156), however, only adds the 0014/0015 rows and removes 0010/0013. It does not mention the 0012 and 0009 annotations. `openspec/architecture.md:74`, `:168` and `:169` also still cite ADR 0010 and 0013.
   - **Fix, task 1.1:** after "remove the rows for 0010 and 0013 (their files stay unchanged)", insert: "annotate the 0012 row with \"account and ACL setup: see 0015\" and the 0009 row with \"account: 0015; SteamCMD: 0014\", and repoint the ADR 0010 and 0013 citations in the component table and contracts list (`architecture.md` lines 74, 168, 169) to 0014 and 0015". Extend its Verify with "and no line outside the superseded rows cites 0010 or 0013".

- **Re-check 1 (marker):** fixed.
  - ADR 0015 inserts the given parenthesis: the version is 0 unless `acl-layout` is a no-follow regular file with one link, owned by SYSTEM or Administrators.
  - D6 states the same rule.
  - host-service has the new scenario "Layout marker planted by a standard user", with its row `layout_marker_planted_by_a_standard_user` in group 9 and in the Verify of task 9.2.
- **Re-check 2 (instances):** fixed. ADR 0015 and D6 now say "The walk sets the DACL on `<data>/instances` itself but does not descend into it; instance directories get their own DACL and migration ..., once the database is open."
- **Re-check 3 (inherited entries):** fixed. ADR 0015 and D6 use the given replacement clause: entries are inherited from the parent's new DACL, and explicit DACLs are set on `<data>/steamcmd` and on the content store.
- **Re-check 4 (M4):** fixed. Task 1.1 now has the 0012 and 0009 annotations, the repointing of `architecture.md` lines 74, 168 and 169, and the extended Verify.
- **From the change's design re-check:**
  - ADR 0015 now refuses a data directory that is itself a reparse point, or whose final path differs, before anything is created in it (`data_dir_not_protected`).
  - Its logon paragraph now says the launcher uses the shared logon module for game servers and the daemon uses it in-process for SteamCMD (ADR 0014). This removes the "launcher starts SteamCMD" contradiction.

### Second re-check (reviewer)

Verified against ADRs 0014 and 0015 as they stand, design D6, D7, D8, D10 and the Failure table, host-service "Startup sequence", and tasks 1.1, 9.2, 9.3 and the test map:

- **Re-check 1 (marker).** ADR 0015 and D6 carry the prescribed rule (version 0 unless `acl-layout` is a no-follow regular file with one link, owned by SYSTEM or Administrators). The scenario "Layout marker planted by a standard user" is in host-service, its row `layout_marker_planted_by_a_standard_user` is in the test map (group 9), and task 9.2's Verify names it.
- **Re-check 2 (instances).** ADR 0015 and D6 both say the walk sets the DACL on `<data>/instances` but does not descend into it, and that instance directories get their own DACL and migration once the database is open. A junction in an M1 instance therefore stays the per-instance `acl_migration_failed` path, not a fatal start.
- **Re-check 3 (inherited entries).** ADR 0015 and D6 use the prescribed clause, so existing SteamCMD installations keep `yagura-steam` modify and existing content keeps `yagura-srv` read and execute after the walk.
- **Re-check 4 (M4).** Task 1.1 adds the 0012 and 0009 annotations, the repointing of `architecture.md` lines 74, 168 and 169, and the Verify "no line outside the superseded rows cites 0010 or 0013". ADR 0009's remaining "ADR 0013" citation is covered by that annotation.
- **Root reparse check (new).** ADR 0015, D6 and the Failure-table row agree: before anything is created in it, the data directory is opened with `FILE_OPEN_REPARSE_POINT` and refused with `data_dir_not_protected` if it is a reparse point or its final path differs. That runs before `DataDirectory.prepare` (`data_directory.dart:25-50`) and the lock, which is the only order that keeps `prepare`'s `createSync` calls and the lock file off a junction target. The scenario "Data directory is a link" and its test row back it. A child planted before the DACL is set (for example a `snapshots` junction, which `createSync` leaves as is) is caught by the walk and the scenario "Link in the data directory at first service start". The Startup-sequence requirement lists "protect" after "lock". It does not mention the root check, but that check's position is fixed by D6 and the junction scenario, so this is not a contradiction.
- **Logon-module wording (new).** ADR 0015 now says the launcher uses the shared logon module for game servers and the daemon uses it in-process for SteamCMD. This agrees with ADR 0014 paragraph 2, with D7 "Accounts", with D10 "Account" (the daemon starts SteamCMD suspended, in the operation's kill-on-close job, with pipes, not through `yagurad launch`), with task 9.3 and with ADR 0009 (launcher breakaway for game servers only; SteamCMD a child in the daemon's job).
- **Cross-ADR consistency.** I found no new contradiction among ADRs 0005 (staging-and-rename publish, with `yagura-steam` holding no entry on the content store), 0009, 0011 (passwords in LocalSystem's DPAPI scope), 0012 (install-time account/ACL statement replaced by ADR 0015's Context), 0014 and 0015, or between them and the change.

Non-blocking implementation note for task 9.2: on a fresh install `%ProgramData%\Yagura` does not exist yet, so the root check has to create it (as SYSTEM, without following links) and then open it, not fail on "not found". The fresh-install scenario will expose this if it is missed.

CHANGES_APPLIED is set to `yes`. The verdict is unchanged.

- **Post-pass edits to ADR 0015 (from the change's design re-check and a user decision):**
  - The root-check paragraph now creates the data directory if it is absent and opens it no-follow without `FILE_SHARE_DELETE`. It keeps that handle open until the owner and DACL are set through it, which closes the rename-and-replace race (change review R4).
  - A new Consequences bullet records the user's choice (a): the first service start trusts an existing data directory's contents. Yagura targets a dedicated single-admin host.

### Post-pass re-check (reviewer)

Both post-pass edits to ADR 0015 are correct, and CHANGES_APPLIED stays `yes`:
- **Root-handle wording (change review R4).** The paragraph now creates the data directory if absent, opens it with `FILE_OPEN_REPARSE_POINT` and without `FILE_SHARE_DELETE`, and keeps that handle open while it sets the owner and the protected DACL through it. The directory cannot be renamed while the handle is open, so the check-then-replace race is closed. The text matches design D6. D6 also says "then closes it", which the ADR need not repeat.
- **Consequences bullet (single-admin host).** It matches D6 and the user's choice (a). It contradicts no other ADR:
  - **ADR 0011.** Secret rows planted in a pre-created directory cannot be LocalSystem DPAPI blobs, so the scope rule deletes them.
  - **ADR 0012.** "Before the first service install" fits the WinSW install flow. ADR 0015's Context already replaces ADR 0012's install-time account and ACL statement.
  - **ADR 0005.** The bullet trusts existing content but does not change the staging-and-rename publish.
  - **ADRs 0009 and 0014.** Process ownership and SteamCMD launch are not affected.
