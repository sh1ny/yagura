# Tasks

Parked backlog: never applied. Group numbers continue from `init-core-platform` (groups 1-9, M1) so references in the design stay valid. Each milestone change taken out of this backlog copies its groups and rows, renumbers them from 1, and adds `green` re-run rows for the M1 scenarios that ride along unchanged inside its MODIFIED requirements (those rows are not listed here).

## Test map

Every scenario of this backlog maps to a Dart test at the boundary it crosses: daemon behaviour against an in-process daemon with fake SteamCMD, fake process host and fake firewall where the real one is not needed; process, service and firewall rows against the real OS on Windows (and Linux for M5) CI runners (`integration_test/`, tagged `windows`/`linux`); desktop rows as Flutter widget tests against a fake daemon connection. The group column says which task group turns the row green; groups are tagged by milestone below.

| Requirement | Scenario | Test file | Test name | Group | State |
|---|---|---|---|---|---|
| desktop-client → Operations and interactive prompts | Steam Guard prompt | apps/yagura_desktop/test/operations_and_interactive_prompts_test.dart | steam_guard_prompt | 14 (M3) | red |
| desktop-client → Operations and interactive prompts | Prompt answered elsewhere | apps/yagura_desktop/test/operations_and_interactive_prompts_test.dart | prompt_answered_elsewhere | 14 (M3) | red |
| steam-content → Adding a Steam account with Steam Guard | Email code relayed | apps/yagurad/test/steam/adding_a_steam_account_with_steam_guard_test.dart | email_code_relayed | 14 (M3) | red |
| steam-content → Adding a Steam account with Steam Guard | Wrong code | apps/yagurad/test/steam/adding_a_steam_account_with_steam_guard_test.dart | wrong_code | 14 (M3) | red |
| steam-content → Adding a Steam account with Steam Guard | No code submitted in time | apps/yagurad/test/steam/adding_a_steam_account_with_steam_guard_test.dart | no_code_submitted_in_time | 14 (M3) | red |
| steam-content → Credential retention is the admin's choice | Password not remembered and cache valid | apps/yagurad/test/steam/credential_retention_is_the_admin_s_choice_test.dart | password_not_remembered_and_cache_valid | 14 (M3) | red |
| steam-content → Credential retention is the admin's choice | Cached login expired | apps/yagurad/test/steam/credential_retention_is_the_admin_s_choice_test.dart | cached_login_expired | 14 (M3) | red |
| steam-content → Game Server Login Tokens | Token injected at launch | apps/yagurad/test/steam/game_server_login_tokens_test.dart | token_injected_at_launch | 14 (M3) | red |
| steam-content → Game Server Login Tokens | Required token missing | apps/yagurad/test/steam/game_server_login_tokens_test.dart | required_token_missing | 14 (M3) | red |
| steam-content → Login mode per plugin | Account login not available | apps/yagurad/test/steam/login_mode_per_plugin_test.dart | account_login_not_available | 14 (M3) | red |
| steam-content → Steam passwords never reach disk or logs | Password absent from output | apps/yagurad/test/steam/steam_passwords_never_reach_disk_or_logs_test.dart | password_absent_from_output | 14 (M3) | red |
| steam-content → Steam passwords never reach disk or logs | Remember password | apps/yagurad/test/steam/steam_passwords_never_reach_disk_or_logs_test.dart | remember_password | 14 (M3) | red |
| steam-content → Workshop downloads | Workshop item downloaded | apps/yagurad/test/steam/workshop_downloads_test.dart | workshop_item_downloaded | 14 (M3) | red |
| steam-content → Workshop downloads | Item removed from the workshop | apps/yagurad/test/steam/workshop_downloads_test.dart | item_removed_from_the_workshop | 14 (M3) | red |
| daemon-protocol → Long operations are asynchronous with resumable progress | Missed events no longer retained | apps/yagurad/test/api/long_operations_are_asynchronous_with_resumable__test.dart | missed_events_no_longer_retained | 14 (M3) | red |
| config-bindings → Bindings map settings to file keys | Scalar binding applied | apps/yagurad/test/config/bindings_map_settings_to_file_keys_test.dart | scalar_binding_applied | 15 (M3) | red |
| config-bindings → Bindings map settings to file keys | Bound file missing | apps/yagurad/test/config/bindings_map_settings_to_file_keys_test.dart | bound_file_missing | 15 (M3) | red |
| config-bindings → Bindings map settings to file keys | Missing file created from the plugin template | apps/yagurad/test/config/bindings_map_settings_to_file_keys_test.dart | missing_file_created_from_the_plugin_template | 15 (M3) | red |
| config-bindings → Manual edits are detected, not overwritten blindly | Admin edit to an unbound key kept | apps/yagurad/test/config/manual_edits_are_detected_not_overwritten_blindl_test.dart | admin_edit_to_an_unbound_key_kept | 15 (M3) | red |
| config-bindings → Manual edits are detected, not overwritten blindly | Admin edit to a bound key reported | apps/yagurad/test/config/manual_edits_are_detected_not_overwritten_blindl_test.dart | admin_edit_to_a_bound_key_reported | 15 (M3) | red |
| config-bindings → Manual edits are detected, not overwritten blindly | Secret values masked in the event | apps/yagurad/test/config/manual_edits_are_detected_not_overwritten_blindl_test.dart | secret_values_masked_in_the_event | 15 (M3) | red |
| config-bindings → Round-trip preservation | Unchanged file stays identical | packages/yagura_formats/test/round_trip_preservation_test.dart | unchanged_file_stays_identical | 15 (M3) | red |
| config-bindings → Round-trip preservation | Comments and unknown keys survive | packages/yagura_formats/test/round_trip_preservation_test.dart | comments_and_unknown_keys_survive | 15 (M3) | red |
| config-bindings → Round-trip preservation | Unparseable file | packages/yagura_formats/test/round_trip_preservation_test.dart | unparseable_file | 15 (M3) | red |
| config-bindings → Supported formats | Unknown format name | packages/yagura_formats/test/supported_formats_test.dart | unknown_format_name | 15 (M3) | red |
| config-bindings → Writes are atomic | Interrupted apply | apps/yagurad/test/config/writes_are_atomic_test.dart | interrupted_apply | 15 (M3) | red |
| config-bindings → Writes are atomic | File locked by a running process | apps/yagurad/test/config/writes_are_atomic_test.dart | file_locked_by_a_running_process | 15 (M3) | red |
| plugin-hooks → Sandboxed host API | File edit returned and applied by the daemon | apps/yagurad/test/hooks/sandboxed_host_api_test.dart | file_edit_returned_and_applied_by_the_daemon | 15 (M3) | red |
| instance-lifecycle → Updates stop and restart a running server | Update while running | apps/yagurad/test/instances/updates_stop_and_restart_a_running_server_test.dart | update_while_running | 16 (M3) | red |
| mod-management → Key files and post-processing | Bikeys synced | apps/yagurad/test/mods/key_files_and_post_processing_test.dart | bikeys_synced | 16 (M3) | red |
| mod-management → Key files and post-processing | Shared key kept | apps/yagurad/test/mods/key_files_and_post_processing_test.dart | shared_key_kept | 16 (M3) | red |
| mod-management → Key files and post-processing | Admin's own key with the same name | apps/yagurad/test/mods/key_files_and_post_processing_test.dart | admin_s_own_key_with_the_same_name | 16 (M3) | red |
| mod-management → Key files and post-processing | Mod removed takes its key | apps/yagurad/test/mods/key_files_and_post_processing_test.dart | mod_removed_takes_its_key | 16 (M3) | red |
| mod-management → Load order and roles | Reorder changes launch order | apps/yagurad/test/mods/load_order_and_roles_test.dart | reorder_changes_launch_order | 16 (M3) | red |
| mod-management → Load order and roles | Unknown role | apps/yagurad/test/mods/load_order_and_roles_test.dart | unknown_role | 16 (M3) | red |
| mod-management → Mod changes require a stopped instance to apply | Add while running | apps/yagurad/test/mods/mod_changes_require_a_stopped_instance_to_apply_test.dart | add_while_running | 16 (M3) | red |
| mod-management → Mod changes require a stopped instance to apply | ApplyMods while running | apps/yagurad/test/mods/mod_changes_require_a_stopped_instance_to_apply_test.dart | applymods_while_running | 16 (M3) | red |
| mod-management → Mod update detection and update | Update available flagged | apps/yagurad/test/mods/mod_update_detection_and_update_test.dart | update_available_flagged | 16 (M3) | red |
| mod-management → Mod update detection and update | Update check cannot reach Steam | apps/yagurad/test/mods/mod_update_detection_and_update_test.dart | update_check_cannot_reach_steam | 16 (M3) | red |
| mod-management → Plugins declare mod support and strategy | Plugin without mod support | apps/yagurad/test/mods/plugins_declare_mod_support_and_strategy_test.dart | plugin_without_mod_support | 16 (M3) | red |
| mod-management → Plugins declare mod support and strategy | Server-managed mods | apps/yagurad/test/mods/plugins_declare_mod_support_and_strategy_test.dart | server_managed_mods | 16 (M3) | red |
| mod-management → Shared, versioned, immutable content store | Two instances share one download | apps/yagurad/test/mods/shared_versioned_immutable_content_store_test.dart | two_instances_share_one_download | 16 (M3) | red |
| mod-management → Shared, versioned, immutable content store | Update while another instance runs | apps/yagurad/test/mods/shared_versioned_immutable_content_store_test.dart | update_while_another_instance_runs | 16 (M3) | red |
| mod-management → Shared, versioned, immutable content store | Update requested for a running instance | apps/yagurad/test/mods/shared_versioned_immutable_content_store_test.dart | update_requested_for_a_running_instance | 16 (M3) | red |
| mod-management → Shared, versioned, immutable content store | One of two waiters cancels | apps/yagurad/test/mods/shared_versioned_immutable_content_store_test.dart | one_of_two_waiters_cancels | 16 (M3) | red |
| mod-management → Shared, versioned, immutable content store | Interrupted download | apps/yagurad/test/mods/shared_versioned_immutable_content_store_test.dart | interrupted_download | 16 (M3) | red |
| mod-management → Shared, versioned, immutable content store | Removing a mod from one instance | apps/yagurad/test/mods/shared_versioned_immutable_content_store_test.dart | removing_a_mod_from_one_instance | 16 (M3) | red |
| mod-management → Staging by link with copy fallback | DayZ mod linked | apps/yagurad/test/mods/staging_by_link_with_copy_fallback_test.dart | dayz_mod_linked | 16 (M3) | red |
| mod-management → Staging by link with copy fallback | Mod renamed on the workshop | apps/yagurad/test/mods/staging_by_link_with_copy_fallback_test.dart | mod_renamed_on_the_workshop | 16 (M3) | red |
| mod-management → Staging by link with copy fallback | Link not permitted | apps/yagurad/test/mods/staging_by_link_with_copy_fallback_test.dart | link_not_permitted | 16 (M3) | red |
| plugin-hooks → Sandboxed host API | Edit into a staged mod refused | apps/yagurad/test/hooks/sandboxed_host_api_test.dart | edit_into_a_staged_mod_refused | 16 (M3) | red |
| plugin-manifest → Launch templates | Conditional and joined arguments | packages/yagura_plugin/test/launch_templates_test.dart | conditional_and_joined_arguments | 16 (M3) | red |
| host-service → Data directory layout | Default layout created | apps/yagurad/test/host/data_directory_layout_test.dart | default_layout_created | 16 (M3) | red |
| log-streaming → Secrets masked in log streams | Password echoed by the server | apps/yagurad/test/logs/secrets_masked_in_log_streams_test.dart | password_echoed_by_the_server | 17 (M3) | red |
| log-streaming → Secrets masked in log streams | Backlog and crash lines masked | apps/yagurad/test/logs/secrets_masked_in_log_streams_test.dart | backlog_and_crash_lines_masked | 17 (M3) | red |
| log-streaming → Secrets masked in log streams | No secrets set | apps/yagurad/test/logs/secrets_masked_in_log_streams_test.dart | no_secrets_set | 17 (M3) | red |
| plugin-hooks → Hook points | Migration hook result applied | apps/yagurad/test/hooks/hook_points_test.dart | migration_hook_result_applied | 17 (M3) | red |
| plugin-manifest → Plugin version changes re-validate instances | Removed setting migrated | packages/yagura_plugin/test/plugin_version_changes_re_validate_instances_test.dart | removed_setting_migrated | 17 (M3) | red |
| plugin-manifest → Plugin version changes re-validate instances | Running instance after an invalidating reload | packages/yagura_plugin/test/plugin_version_changes_re_validate_instances_test.dart | running_instance_after_an_invalidating_reload | 17 (M3) | red |
| plugin-manifest → Plugin version changes re-validate instances | Migration hook fails | packages/yagura_plugin/test/plugin_version_changes_re_validate_instances_test.dart | migration_hook_fails | 17 (M3) | red |
| plugin-manifest → Plugin version changes re-validate instances | Settings no longer valid | packages/yagura_plugin/test/plugin_version_changes_re_validate_instances_test.dart | settings_no_longer_valid | 17 (M3) | red |
| instance-lifecycle → Graceful stop per plugin strategy | RCON unavailable during stop | apps/yagurad/test/instances/graceful_stop_per_plugin_strategy_test.dart | rcon_unavailable_during_stop | 18 (M4) | red |
| instance-lifecycle → Graceful stop per plugin strategy | Graceful RCON shutdown | apps/yagurad/test/instances/graceful_stop_per_plugin_strategy_test.dart | graceful_rcon_shutdown | 18 (M4) | red |
| rcon → One-shot commands | Command answered | apps/yagurad/test/rcon/one_shot_commands_test.dart | command_answered | 18 (M4) | red |
| rcon → One-shot commands | Instance not running | apps/yagurad/test/rcon/one_shot_commands_test.dart | instance_not_running | 18 (M4) | red |
| rcon → One-shot commands | Wrong password | apps/yagurad/test/rcon/one_shot_commands_test.dart | wrong_password | 18 (M4) | red |
| rcon → Plugin-declared RCON protocol | Protocol selected from manifest | apps/yagurad/test/rcon/plugin_declared_rcon_protocol_test.dart | protocol_selected_from_manifest | 18 (M4) | red |
| rcon → Plugin-declared RCON protocol | Plugin without RCON | apps/yagurad/test/rcon/plugin_declared_rcon_protocol_test.dart | plugin_without_rcon | 18 (M4) | red |
| rcon → Protocol keep-alives | Idle BattlEye session kept | apps/yagurad/test/rcon/protocol_keep_alives_test.dart | idle_battleye_session_kept | 18 (M4) | red |
| rcon → Protocol keep-alives | Keep-alive unanswered | apps/yagurad/test/rcon/protocol_keep_alives_test.dart | keep_alive_unanswered | 18 (M4) | red |
| rcon → Shared session and console stream | Two consoles share a session | apps/yagurad/test/rcon/shared_session_and_console_stream_test.dart | two_consoles_share_a_session | 18 (M4) | red |
| rcon → Shared session and console stream | Session drops | apps/yagurad/test/rcon/shared_session_and_console_stream_test.dart | session_drops | 18 (M4) | red |
| config-bindings → Manual edits are detected, not overwritten blindly | Game rewrites its own config | apps/yagurad/test/config/manual_edits_are_detected_not_overwritten_blindl_test.dart | game_rewrites_its_own_config | 19 (M4) | red |
| config-bindings → Supported formats | Repeated UE keys from a list setting | packages/yagura_formats/test/supported_formats_test.dart | repeated_ue_keys_from_a_list_setting | 19 (M4) | red |
| desktop-client → Forms rendered from plugin schemas | Repeatable list as a table | apps/yagura_desktop/test/forms_rendered_from_plugin_schemas_test.dart | repeatable_list_as_a_table | 19 (M4) | red |
| instance-lifecycle → Import and export instances | Import a copied instance | apps/yagurad/test/instances/import_and_export_instances_test.dart | import_a_copied_instance | 19 (M4) | red |
| instance-lifecycle → Import and export instances | Import with unknown plugin version | apps/yagurad/test/instances/import_and_export_instances_test.dart | import_with_unknown_plugin_version | 19 (M4) | red |
| host-service → Linux service | Unit installed | apps/yagurad/integration_test/linux/linux_service_test.dart | unit_installed | 20 (M5) | red |
| host-service → Linux service | systemd not available | apps/yagurad/integration_test/linux/linux_service_test.dart | systemd_not_available | 20 (M5) | red |
| host-service → Linux service | Stopping the unit keeps servers | apps/yagurad/integration_test/linux/linux_service_test.dart | stopping_the_unit_keeps_servers | 20 (M5) | red |

## 14. [M3] Steam accounts and Steam Guard

Covers: desktop-client → Operations and interactive prompts; steam-content → Login mode per plugin; steam-content → Adding a Steam account with Steam Guard; steam-content → Credential retention is the admin's choice; steam-content → Game Server Login Tokens; steam-content → Workshop downloads; steam-content → Steam passwords never reach disk or logs.

- [ ] 14.1 Spike: with a test Steam account, record SteamCMD's output and behaviour with stdin closed for email code, authenticator code and mobile approval; add the patterns to `steam/patterns.yaml` and the transcripts to the fake SteamCMD fixtures. Record in `docs/spikes/m3-steam-guard.md` and set the login timeouts from it.
- [ ] 14.2 Write the failing tests for this group's rows.
- [ ] 14.3 Implement accounts (one SteamCMD installation each), `AddAccount`/`ReauthAccount` operations with `WAITING_FOR_INPUT` prompts and `RespondToPrompt`, password scrubbing, `remember_password`, `steam_reauth_required`, GSLT secrets injected by template, workshop downloads and metadata (design D8). Wire the client's Steam Guard dialog. Verify: this group's rows are green; flip them.

## 15. [M3] Formats and config bindings

Covers: config-bindings → Bindings map settings to file keys; config-bindings → Supported formats; config-bindings → Round-trip preservation; config-bindings → Manual edits are detected, not overwritten blindly; config-bindings → Writes are atomic.

- [ ] 15.1 Collect real-file corpora for `ini`, `json`, `dayz-cfg` and `kv` under `packages/yagura_formats/test/corpus/` (DayZ `serverDZ.cfg`, `cfggameplay.json`, BattlEye cfg, generic INI).
- [ ] 15.2 Write the failing tests for this group's rows, plus a byte-identical round-trip test over every corpus file.
- [ ] 15.3 Implement the four parsers with lossless trees, then the binder: bindings in the manifest schema, `create`/`template`, apply before `onPreStart`, hook file edits applied after bindings through the M1 file-edit writer (`init-core-platform` D23, extended to these formats), hash tracking, `external_edit` events, `game_writes`, atomic replace with the 5 s lock retry. Verify: this group's rows are green; flip them.

## 16. [M3] Mod pipeline and content store

Covers: instance-lifecycle → Updates stop and restart a running server (`update_mods`); plugin-hooks → Hook points (`onModsStaged`); mod-management → Plugins declare mod support and strategy; mod-management → Shared, versioned, immutable content store; mod-management → Staging by link with copy fallback; mod-management → Key files and post-processing; mod-management → Load order and roles; mod-management → Mod changes require a stopped instance to apply; mod-management → Mod update detection and update.

- [ ] 16.1 Write the failing tests for this group's rows.
- [ ] 16.2 Implement the versioned content store (`.staging` + atomic rename, single-flight per item version with waiter detach, GC of versions unreferenced 7 days, `.staging` cleanup at startup), instance-mod rows with pinned versions and fixed staged names, junction creation through FFI with copy fallback, `staged_version`/`desired_version` with both counted by GC, key-file ownership per design D19 (`key_conflict`), roles and load order, the update check timer (6 h, jittered, backoff) and `Mods` service. Verify: this group's rows are green; flip them.

## 17. [M3] DayZ plugin, plugin migrations and M3 exit

Covers: log-streaming → Secrets masked in log streams; plugin-hooks → Hook points; plugin-manifest → Plugin version changes re-validate instances.

- [ ] 17.1 Write the failing tests for this group's rows.
- [ ] 17.2 Implement plugin version change handling (`migrateSettings`, `settings_invalid`, `plugin_missing`) and secret masking in log streams. Verify: rows green; flip them.
- [ ] 17.3 Write `plugins/dayz/` (account login, workshop app 221100, Yagura-owned `yagura/serverDZ.cfg` and BattlEye cfg templates with `RConPort`/`RConPassword`, client/server mod roles, bikey rules, `data_paths`, log sources; stop strategy `signal` (or `kill`) with grace seconds, and no `rcon` section or `rcon` stop, which M1 rejects and task 18.2 adds). Verify on a Windows host with BattlEye: 10+ workshop mods install, link, load and survive a mod update (M3 exit criterion); record in `docs/milestones/m3.md`.

## 18. [M4] RCON

Covers: instance-lifecycle → Graceful stop per plugin strategy; desktop-client → Logs and console views (console); rcon → Plugin-declared RCON protocol; rcon → One-shot commands; rcon → Shared session and console stream; rcon → Protocol keep-alives.

- [ ] 18.1 Write the failing tests for this group's rows against fake BattlEye (UDP), Source RCON (TCP) and WebRCON (WebSocket) servers in `apps/yagurad/test/fixtures/`.
- [ ] 18.2 Implement the three adapters with keep-alives, the shared session per instance, `Execute`, the `Console` stream with command echo and 8 subscribers, reconnect backoff, auth-failure stop, and the `rcon` stop strategy. Relax the manifest's `rcon` section and `rcon` stop rejection, and add the `rcon` section and stop to `plugins/dayz/`. Add the console view to the client. Verify: this group's rows are green; flip them.

## 19. [M4] Complex configs, more games, import/export and M4 exit

Covers: config-bindings → Supported formats; config-bindings → Manual edits are detected, not overwritten blindly; desktop-client → Forms rendered from plugin schemas; instance-lifecycle → Import and export instances.

- [ ] 19.1 Add `ue-ini`, `xml` and `vdf` parsers with corpora (ARK:SA `GameUserSettings.ini`/`Game.ini`); write the failing tests for this group's rows.
- [ ] 19.2 Implement `list` bindings with `repeat` mode, import/export, and the client's table editor for `list` settings. Verify: rows green; flip them.
- [ ] 19.3 Write `plugins/ark_sa/` (anonymous 2430930, `-mods=` server-managed, Source RCON, `game_writes: true` bindings), `plugins/scum/` (UTF-16LE logs, signal stop verified on Windows), `plugins/rust/` (WebRCON). Verify each with `yagura plugin lint` and a manual run recorded in `docs/milestones/m4.md`.

## 20. [M5] Linux agent

Covers: host-service → Linux service.

- [ ] 20.1 Write the failing integration tests for this group's rows (Linux runner).
- [ ] 20.2 Implement the POSIX `ProcessHost` (posix_spawn + setsid, servers in transient systemd scopes, SIGTERM for `signal`), the systemd unit install, the Linux secret store, a firewalld/ufw adapter behind the firewall interface, and Linux executables in the reference plugins. Verify: this group's rows are green; flip them, and record the M5 run in `docs/milestones/m5.md`.

## 21. [M3-M5] Integration

- [ ] 21.1 Run every package's tests on Windows and Linux CI and `openspec validate --all --strict`. Verify: all pass and every test-map row is green.
- [ ] 21.2 Re-run the secret scan of `apps/yagurad/integration_test/secrets_data_directory_scan_test.dart` over a full install-start-update-stop workflow that also sets the secrets added after M2 (Steam account passwords, GSLT, RCON passwords), and extend it to the snapshot directories and logs. Verify: no secret value found outside the accepted exceptions.
- [ ] 21.3 Write back into `openspec/architecture.md` the decisions and Resource Bounds rows of this design that the baseline lacks (mod pipeline, content store, RCON, Linux agent). Verify: each is present in `openspec/architecture.md`.

## Workflow follow-up

- This change is never applied or archived. At each milestone, `specwright-roadmap next` creates the milestone's change (for example `m2-secure-remote-host`) from its groups here: the requirements as ADDED, or MODIFIED where this backlog lists them so, the decisions and table rows its groups depend on, and its test-map rows. That change gets its own design review. The moved material is then deleted here, and this change is deleted when nothing is left.
- When a task adds a dependency to any workspace package, re-run the dependency skill discovery and update `.claude/skills/UPSTREAM.json`.
- Milestone exit criteria that are user-verified are run by the user, never marked passed on their behalf.
