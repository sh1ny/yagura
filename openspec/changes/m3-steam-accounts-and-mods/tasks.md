# Tasks

## Test map

Every scenario maps to a Dart test at the boundary it crosses:
- **Daemon behaviour** runs against an in-process daemon with fakes where the real thing is not needed: fake SteamCMD (extended in task 1.2 with workshop downloads and Steam Guard transcripts), a fake Steam Web API server, a fake process host and a fake firewall.
- **Formats** run as package tests in `packages/yagura_formats` over real-file corpora.
- **Windows behaviour** (junctions, reparse points, the launcher-to-relay stdin pipe) runs against the real OS. These tests are tagged `windows` and run on Windows CI.
- **Desktop rows** are Flutter widget tests against `test/support/fake_daemon.dart`.

Rows tagged `elevated` need administrator rights, the installed service or local accounts. They never run on the developer's desktop. They run only in the manual `elevated` workflow (`.github/workflows/elevated.yml`), and the run link and results are recorded in `docs/milestones/m3.md`. Rows that need a real Steam account or a real DayZ server are not rows here: they are the user-verified checks of tasks 1.1 and 10.3.

Rows marked `green` ride along unchanged inside a MODIFIED requirement and already pass; their group re-runs them. The group column says which task group turns the row green.

| Requirement | Scenario | Test file | Test name | Group | State |
|---|---|---|---|---|---|
| host-service → Data directory layout | Default layout created | apps/yagurad/test/host/data_directory_layout_test.dart | default_layout_created | 1 | red |
| host-service → Data directory layout | Content store protected | apps/yagurad/integration_test/service/content_store_acl_test.dart | content_store_protected (elevated) | 1 | red |
| host-service → Data directory layout | Data directory not writable | apps/yagurad/test/host/data_directory_layout_test.dart | data_directory_not_writable | 1 | green |
| host-service → Data directory layout | Instance root added locally | apps/yagurad/integration_test/admin/instance_roots_test.dart | instance_root_added_locally (elevated) | 1 | green |
| host-service → Data directory layout | Instance on another drive | apps/yagurad/integration_test/admin/instance_roots_test.dart | instance_on_another_drive (elevated) | 1 | green |
| host-service → Data directory layout | Root writable by non-administrators | apps/yagurad/integration_test/admin/instance_roots_test.dart | root_writable_by_non_administrators (elevated) | 1 | green |
| host-service → Data directory layout | Root still in use | apps/yagurad/integration_test/admin/instance_roots_test.dart | root_still_in_use (elevated) | 1 | green |
| config-bindings → Round-trip preservation | Unchanged file stays identical | packages/yagura_formats/test/round_trip_preservation_test.dart | unchanged_file_stays_identical | 2 | green |
| config-bindings → Round-trip preservation | Comments and unknown keys survive | packages/yagura_formats/test/round_trip_preservation_test.dart | comments_and_unknown_keys_survive | 2 | green |
| config-bindings → Round-trip preservation | Unparseable file | packages/yagura_formats/test/round_trip_preservation_test.dart | unparseable_file | 2 | green |
| config-bindings → Supported formats | Array value in dayz-cfg | packages/yagura_formats/test/supported_formats_test.dart | array_value_in_dayz_cfg | 2 | green |
| config-bindings → Bindings map settings to file keys | Scalar binding applied | apps/yagurad/test/config/bindings_map_settings_to_file_keys_test.dart | scalar_binding_applied | 3 | red |
| config-bindings → Bindings map settings to file keys | Bound file missing | apps/yagurad/test/config/bindings_map_settings_to_file_keys_test.dart | bound_file_missing | 3 | red |
| config-bindings → Bindings map settings to file keys | Missing file created from the plugin template | apps/yagurad/test/config/bindings_map_settings_to_file_keys_test.dart | missing_file_created_from_the_plugin_template | 3 | red |
| config-bindings → Bindings map settings to file keys | Secret setting bound | apps/yagurad/test/config/bindings_map_settings_to_file_keys_test.dart | secret_setting_bound | 3 | red |
| config-bindings → Bindings map settings to file keys | Binding names an unknown setting | apps/yagurad/test/config/bindings_map_settings_to_file_keys_test.dart | binding_names_an_unknown_setting | 3 | red |
| config-bindings → Manual edits are detected, not overwritten blindly | Admin edit to an unbound key kept | apps/yagurad/test/config/manual_edits_are_detected_not_overwritten_blindl_test.dart | admin_edit_to_an_unbound_key_kept | 3 | red |
| config-bindings → Manual edits are detected, not overwritten blindly | Admin edit to a bound key reported | apps/yagurad/test/config/manual_edits_are_detected_not_overwritten_blindl_test.dart | admin_edit_to_a_bound_key_reported | 3 | red |
| config-bindings → Manual edits are detected, not overwritten blindly | Secret values masked in the event | apps/yagurad/test/config/manual_edits_are_detected_not_overwritten_blindl_test.dart | secret_values_masked_in_the_event | 3 | red |
| config-bindings → Manual edits are detected, not overwritten blindly | Game rewrites its own config | apps/yagurad/test/config/manual_edits_are_detected_not_overwritten_blindl_test.dart | game_rewrites_its_own_config | 3 | red |
| config-bindings → Writes are atomic | Interrupted apply | apps/yagurad/test/config/writes_are_atomic_test.dart | interrupted_apply | 3 | red |
| config-bindings → Writes are atomic | File locked by a running process | apps/yagurad/test/config/writes_are_atomic_test.dart | file_locked_by_a_running_process | 3 | red |
| plugin-hooks → Sandboxed host API | File edit returned and applied by the daemon | apps/yagurad/test/hooks/sandboxed_host_api_test.dart | file_edit_returned_and_applied_by_the_daemon | 3 | red |
| plugin-hooks → Sandboxed host API | Edit in an unsupported format | apps/yagurad/test/hooks/sandboxed_host_api_test.dart | edit_in_an_unsupported_format | 3 | red |
| plugin-hooks → Sandboxed host API | Write attempted from a hook | apps/yagurad/test/hooks/sandboxed_host_api_test.dart | write_attempted_from_a_hook | 3 | green |
| plugin-hooks → Sandboxed host API | Path escape refused | apps/yagurad/test/hooks/sandboxed_host_api_test.dart | path_escape_refused | 3 | green |
| plugin-hooks → Sandboxed host API | Edit through a link refused | apps/yagurad/test/hooks/sandboxed_host_api_test.dart | edit_through_a_link_refused | 3 | green |
| config-bindings → Supported formats | Format of a later version | packages/yagura_plugin/test/supported_formats_test.dart | format_of_a_later_version | 4 | red |
| config-bindings → Supported formats | Unknown format name | packages/yagura_plugin/test/supported_formats_test.dart | unknown_format_name | 4 | red |
| plugin-manifest → Launch templates | Conditional and joined arguments | packages/yagura_plugin/test/launch_templates_test.dart | conditional_and_joined_arguments | 4 | green |
| plugin-manifest → Launch templates | Mod roles joined into arguments | packages/yagura_plugin/test/launch_templates_test.dart | mod_roles_joined_into_arguments | 4 | red |
| plugin-manifest → Launch templates | Template references an unknown setting | packages/yagura_plugin/test/launch_templates_test.dart | template_references_an_unknown_setting | 4 | green |
| plugin-manifest → Launch templates | Secret outside the secrets namespace | packages/yagura_plugin/test/launch_templates_test.dart | secret_outside_the_secrets_namespace | 4 | red |
| plugin-manifest → Launch templates | Missing executable for this OS | apps/yagurad/test/instances/launch_templates_test.dart | missing_executable_for_this_os | 4 | green |
| plugin-manifest → Stop and health declarations | Log-match health check | apps/yagurad/test/instances/log_match_health_check_test.dart | log_match_health_check | 4 | green |
| plugin-manifest → Stop and health declarations | Log file rewritten past its old size | apps/yagurad/test/instances/log_match_health_check_test.dart | log_file_rewritten_past_its_old_size | 4 | green |
| plugin-manifest → Stop and health declarations | Unsupported stop strategy | packages/yagura_plugin/test/stop_and_health_declarations_test.dart | unsupported_stop_strategy | 4 | green |
| plugin-manifest → Stop and health declarations | Bindings and mods sections accepted | packages/yagura_plugin/test/stop_and_health_declarations_test.dart | bindings_and_mods_sections_accepted | 4 | red |
| plugin-manifest → Stop and health declarations | Invalid health regex | packages/yagura_plugin/test/stop_and_health_declarations_test.dart | invalid_health_regex | 4 | green |
| steam-content → Game Server Login Tokens | Token injected at launch | apps/yagurad/test/steam/game_server_login_tokens_test.dart | token_injected_at_launch | 4 | red |
| steam-content → Game Server Login Tokens | Required token missing | apps/yagurad/test/steam/game_server_login_tokens_test.dart | required_token_missing | 4 | red |
| daemon-protocol → Long operations are asynchronous with resumable progress | Reconnect without losing events | apps/yagurad/test/api/long_operations_are_asynchronous_with_resumable__test.dart | reconnect_without_losing_events | 5 | green |
| daemon-protocol → Long operations are asynchronous with resumable progress | Missed events no longer retained | apps/yagurad/test/api/long_operations_are_asynchronous_with_resumable__test.dart | missed_events_no_longer_retained | 5 | red |
| daemon-protocol → Long operations are asynchronous with resumable progress | Pending prompt after reconnect | apps/yagurad/test/api/long_operations_are_asynchronous_with_resumable__test.dart | pending_prompt_after_reconnect | 5 | red |
| daemon-protocol → Long operations are asynchronous with resumable progress | Resume across coalesced progress | apps/yagurad/test/api/long_operations_are_asynchronous_with_resumable__test.dart | resume_across_coalesced_progress | 5 | green |
| daemon-protocol → Long operations are asynchronous with resumable progress | Operation pruned from history | apps/yagurad/test/api/long_operations_are_asynchronous_with_resumable__test.dart | operation_pruned_from_history | 5 | green |
| daemon-protocol → Pending prompts reach every client | Snapshot then raised and resolved | apps/yagurad/test/api/pending_prompts_reach_every_client_test.dart | snapshot_then_raised_and_resolved | 5 | red |
| daemon-protocol → Pending prompts reach every client | Late answer refused | apps/yagurad/test/api/pending_prompts_reach_every_client_test.dart | late_answer_refused | 5 | red |
| daemon-protocol → Pending prompts reach every client | Malformed answer | apps/yagurad/test/api/pending_prompts_reach_every_client_test.dart | malformed_answer | 5 | red |
| daemon-protocol → Pending prompts reach every client | Too many prompt watchers | apps/yagurad/test/api/pending_prompts_reach_every_client_test.dart | too_many_prompt_watchers | 5 | red |
| steam-content → Adding a Steam account with Steam Guard | Email code relayed | apps/yagurad/test/steam/adding_a_steam_account_with_steam_guard_test.dart | email_code_relayed | 5 | red |
| steam-content → Adding a Steam account with Steam Guard | Wrong code | apps/yagurad/test/steam/adding_a_steam_account_with_steam_guard_test.dart | wrong_code | 5 | red |
| steam-content → Adding a Steam account with Steam Guard | No code submitted in time | apps/yagurad/test/steam/adding_a_steam_account_with_steam_guard_test.dart | no_code_submitted_in_time | 5 | red |
| steam-content → Adding a Steam account with Steam Guard | Mobile approval not given | apps/yagurad/test/steam/adding_a_steam_account_with_steam_guard_test.dart | mobile_approval_not_given | 5 | red |
| steam-content → Adding a Steam account with Steam Guard | Wrong password | apps/yagurad/test/steam/adding_a_steam_account_with_steam_guard_test.dart | wrong_password | 5 | red |
| steam-content → Adding a Steam account with Steam Guard | Daemon restarted while adding | apps/yagurad/test/steam/adding_a_steam_account_with_steam_guard_test.dart | daemon_restarted_while_adding | 5 | red |
| steam-content → Adding a Steam account with Steam Guard | Account already added | apps/yagurad/test/steam/adding_a_steam_account_with_steam_guard_test.dart | account_already_added | 5 | red |
| steam-content → Credential retention is the admin's choice | Password not remembered and cache valid | apps/yagurad/test/steam/credential_retention_is_the_admin_s_choice_test.dart | password_not_remembered_and_cache_valid | 5 | red |
| steam-content → Credential retention is the admin's choice | Cached login expired | apps/yagurad/test/steam/credential_retention_is_the_admin_s_choice_test.dart | cached_login_expired | 5 | red |
| steam-content → Credential retention is the admin's choice | Remembered password needs Steam Guard during an update | apps/yagurad/test/steam/credential_retention_is_the_admin_s_choice_test.dart | remembered_password_needs_steam_guard_during_an_update | 5 | red |
| steam-content → Credential retention is the admin's choice | Account removed while in use | apps/yagurad/test/steam/credential_retention_is_the_admin_s_choice_test.dart | account_removed_while_in_use | 5 | red |
| steam-content → Login mode per plugin | Anonymous install | apps/yagurad/test/steam/login_mode_per_plugin_test.dart | anonymous_install | 5 | green |
| steam-content → Login mode per plugin | Account install | apps/yagurad/test/steam/login_mode_per_plugin_test.dart | account_install | 5 | red |
| steam-content → Login mode per plugin | Account login not available | apps/yagurad/test/steam/login_mode_per_plugin_test.dart | account_login_not_available | 5 | red |
| steam-content → Login mode per plugin | Optional account not linked | apps/yagurad/test/steam/login_mode_per_plugin_test.dart | optional_account_not_linked | 5 | red |
| steam-content → Steam passwords never reach disk or logs | Password absent from output | apps/yagurad/test/steam/steam_passwords_never_reach_disk_or_logs_test.dart | password_absent_from_output | 5 | red |
| steam-content → Steam passwords never reach disk or logs | Remember password | apps/yagurad/test/steam/steam_passwords_never_reach_disk_or_logs_test.dart | remember_password | 5 | red |
| steam-content → Steam passwords never reach disk or logs | Secret store refuses the password | apps/yagurad/test/steam/steam_passwords_never_reach_disk_or_logs_test.dart | secret_store_refuses_the_password | 5 | red |
| steam-content → SteamCMD is installed and managed by the daemon | First install bootstraps SteamCMD | apps/yagurad/test/steam/steamcmd_is_installed_and_managed_by_the_daemon_test.dart | first_install_bootstraps_steamcmd | 5 | green |
| steam-content → SteamCMD is installed and managed by the daemon | Account installation bootstrapped | apps/yagurad/test/steam/steamcmd_is_installed_and_managed_by_the_daemon_test.dart | account_installation_bootstrapped | 5 | red |
| steam-content → SteamCMD is installed and managed by the daemon | SteamCMD download fails | apps/yagurad/test/steam/steamcmd_is_installed_and_managed_by_the_daemon_test.dart | steamcmd_download_fails | 5 | green |
| mod-management → Shared, versioned, immutable content store | Two instances share one download | apps/yagurad/test/mods/shared_versioned_immutable_content_store_test.dart | two_instances_share_one_download | 6 | red |
| mod-management → Shared, versioned, immutable content store | Update while another instance runs | apps/yagurad/test/mods/shared_versioned_immutable_content_store_test.dart | update_while_another_instance_runs | 6 | red |
| mod-management → Shared, versioned, immutable content store | Update requested for a running instance | apps/yagurad/test/mods/shared_versioned_immutable_content_store_test.dart | update_requested_for_a_running_instance | 6 | red |
| mod-management → Shared, versioned, immutable content store | One of two waiters cancels | apps/yagurad/test/mods/shared_versioned_immutable_content_store_test.dart | one_of_two_waiters_cancels | 6 | red |
| mod-management → Shared, versioned, immutable content store | Interrupted download | apps/yagurad/test/mods/shared_versioned_immutable_content_store_test.dart | interrupted_download | 6 | red |
| mod-management → Shared, versioned, immutable content store | Removing a mod from one instance | apps/yagurad/test/mods/shared_versioned_immutable_content_store_test.dart | removing_a_mod_from_one_instance | 6 | red |
| mod-management → Shared, versioned, immutable content store | Unreferenced version collected | apps/yagurad/test/mods/shared_versioned_immutable_content_store_test.dart | unreferenced_version_collected | 6 | red |
| mod-management → Shared, versioned, immutable content store | Not enough disk for a mod | apps/yagurad/test/mods/shared_versioned_immutable_content_store_test.dart | not_enough_disk_for_a_mod | 6 | red |
| steam-content → Workshop downloads | Workshop item downloaded | apps/yagurad/test/steam/workshop_downloads_test.dart | workshop_item_downloaded | 6 | red |
| steam-content → Workshop downloads | Item removed from the workshop | apps/yagurad/test/steam/workshop_downloads_test.dart | item_removed_from_the_workshop | 6 | red |
| daemon-protocol → Instance state and event stream | Snapshot then deltas | apps/yagurad/test/api/instance_state_and_event_stream_test.dart | snapshot_then_deltas | 7 | green |
| daemon-protocol → Instance state and event stream | Mod update count delta | apps/yagurad/test/api/instance_state_and_event_stream_test.dart | mod_update_count_delta | 7 | red |
| daemon-protocol → Instance state and event stream | State-only delta | apps/yagurad/test/api/instance_state_and_event_stream_test.dart | state_only_delta | 7 | green |
| daemon-protocol → Instance state and event stream | Slow subscriber | apps/yagurad/test/api/instance_state_and_event_stream_test.dart | slow_subscriber | 7 | green |
| instance-lifecycle → Durable state with a portable instance file | Change persisted and mirrored | apps/yagurad/test/instances/durable_state_with_a_portable_instance_file_test.dart | change_persisted_and_mirrored | 7 | green |
| instance-lifecycle → Durable state with a portable instance file | Mod list mirrored | apps/yagurad/test/instances/durable_state_with_a_portable_instance_file_test.dart | mod_list_mirrored | 7 | red |
| instance-lifecycle → Durable state with a portable instance file | instance.json write fails | apps/yagurad/test/instances/durable_state_with_a_portable_instance_file_test.dart | instance_json_write_fails | 7 | green |
| instance-lifecycle → Durable state with a portable instance file | Secrets excluded from instance.json | apps/yagurad/test/instances/durable_state_with_a_portable_instance_file_test.dart | secrets_excluded_from_instance_json | 7 | green |
| instance-lifecycle → One operation per instance at a time | Concurrent requests on one instance | apps/yagurad/test/instances/one_operation_per_instance_at_a_time_test.dart | concurrent_requests_on_one_instance | 7 | green |
| instance-lifecycle → One operation per instance at a time | Heavy limit counts mod downloads | apps/yagurad/test/instances/one_operation_per_instance_at_a_time_test.dart | heavy_limit_counts_mod_downloads | 7 | red |
| instance-lifecycle → One operation per instance at a time | Stop requested while starting | apps/yagurad/test/instances/one_operation_per_instance_at_a_time_test.dart | stop_requested_while_starting | 7 | green |
| instance-lifecycle → One operation per instance at a time | Stop during the health wait | apps/yagurad/test/instances/one_operation_per_instance_at_a_time_test.dart | stop_during_the_health_wait | 7 | green |
| instance-lifecycle → One operation per instance at a time | Queued operation becomes invalid | apps/yagurad/test/instances/one_operation_per_instance_at_a_time_test.dart | queued_operation_becomes_invalid | 7 | green |
| instance-lifecycle → One operation per instance at a time | Queue full | apps/yagurad/test/instances/one_operation_per_instance_at_a_time_test.dart | queue_full | 7 | green |
| instance-lifecycle → Updates stop and restart a running server | Update while running | apps/yagurad/test/instances/updates_stop_and_restart_a_running_server_test.dart | update_while_running | 7 | red |
| instance-lifecycle → Updates stop and restart a running server | Update fails after stop | apps/yagurad/test/instances/updates_stop_and_restart_a_running_server_test.dart | update_fails_after_stop | 7 | green |
| instance-lifecycle → Updates stop and restart a running server | Mod update fails after stop | apps/yagurad/test/instances/updates_stop_and_restart_a_running_server_test.dart | mod_update_fails_after_stop | 7 | red |
| mod-management → Key files and post-processing | Bikeys synced | apps/yagurad/test/mods/key_files_and_post_processing_test.dart | bikeys_synced | 7 | red |
| mod-management → Key files and post-processing | Shared key kept | apps/yagurad/test/mods/key_files_and_post_processing_test.dart | shared_key_kept | 7 | red |
| mod-management → Key files and post-processing | Admin's own key with the same name | apps/yagurad/test/mods/key_files_and_post_processing_test.dart | admin_s_own_key_with_the_same_name | 7 | red |
| mod-management → Key files and post-processing | Mod removed takes its key | apps/yagurad/test/mods/key_files_and_post_processing_test.dart | mod_removed_takes_its_key | 7 | red |
| mod-management → Load order and roles | Reorder changes launch order | apps/yagurad/test/mods/load_order_and_roles_test.dart | reorder_changes_launch_order | 7 | red |
| mod-management → Load order and roles | Unknown role | apps/yagurad/test/mods/load_order_and_roles_test.dart | unknown_role | 7 | red |
| mod-management → Mod changes require a stopped instance to apply | Mods applied by start | apps/yagurad/test/mods/mod_changes_require_a_stopped_instance_to_apply_test.dart | mods_applied_by_start | 7 | red |
| mod-management → Mod changes require a stopped instance to apply | Add while running | apps/yagurad/test/mods/mod_changes_require_a_stopped_instance_to_apply_test.dart | add_while_running | 7 | red |
| mod-management → Mod changes require a stopped instance to apply | ApplyMods while running | apps/yagurad/test/mods/mod_changes_require_a_stopped_instance_to_apply_test.dart | applymods_while_running | 7 | red |
| mod-management → Mod update detection and update | Update available flagged | apps/yagurad/test/mods/mod_update_detection_and_update_test.dart | update_available_flagged | 7 | red |
| mod-management → Mod update detection and update | Only changed mods re-staged | apps/yagurad/test/mods/mod_update_detection_and_update_test.dart | only_changed_mods_re_staged | 7 | red |
| mod-management → Mod update detection and update | Update check cannot reach Steam | apps/yagurad/test/mods/mod_update_detection_and_update_test.dart | update_check_cannot_reach_steam | 7 | red |
| mod-management → Plugins declare mod support and strategy | Plugin without mod support | apps/yagurad/test/mods/plugins_declare_mod_support_and_strategy_test.dart | plugin_without_mod_support | 7 | red |
| mod-management → Plugins declare mod support and strategy | Server-managed mods | apps/yagurad/test/mods/plugins_declare_mod_support_and_strategy_test.dart | server_managed_mods | 7 | red |
| mod-management → Plugins declare mod support and strategy | Source of a later version | apps/yagurad/test/mods/plugins_declare_mod_support_and_strategy_test.dart | source_of_a_later_version | 7 | red |
| mod-management → Staging by link with copy fallback | DayZ mod linked | apps/yagurad/test/mods/staging_by_link_with_copy_fallback_test.dart | dayz_mod_linked | 7 | red |
| mod-management → Staging by link with copy fallback | Title unavailable when added | apps/yagurad/test/mods/staging_by_link_with_copy_fallback_test.dart | title_unavailable_when_added | 7 | red |
| mod-management → Staging by link with copy fallback | Admin folder with the staged name | apps/yagurad/test/mods/staging_by_link_with_copy_fallback_test.dart | admin_folder_with_the_staged_name | 7 | red |
| mod-management → Staging by link with copy fallback | Mod renamed on the workshop | apps/yagurad/test/mods/staging_by_link_with_copy_fallback_test.dart | mod_renamed_on_the_workshop | 7 | red |
| mod-management → Staging by link with copy fallback | Link not permitted | apps/yagurad/test/mods/staging_by_link_with_copy_fallback_test.dart | link_not_permitted | 7 | red |
| mod-management → Staging by link with copy fallback | Staged link replaced by the server | apps/yagurad/test/mods/staging_by_link_with_copy_fallback_test.dart | staged_link_replaced_by_the_server | 7 | red |
| plugin-hooks → Hook input and output contract | Context contents | apps/yagurad/test/hooks/hook_input_and_output_contract_test.dart | context_contents | 7 | green |
| plugin-hooks → Hook input and output contract | Context with a secret set | apps/yagurad/test/hooks/hook_input_and_output_contract_test.dart | context_with_a_secret_set | 7 | green |
| plugin-hooks → Hook input and output contract | Staged mods in the context | apps/yagurad/test/hooks/hook_input_and_output_contract_test.dart | staged_mods_in_the_context | 7 | red |
| plugin-hooks → Hook input and output contract | Invalid result shape | apps/yagurad/test/hooks/hook_input_and_output_contract_test.dart | invalid_result_shape | 7 | green |
| plugin-hooks → Hook points | Pre-start hook adds arguments | apps/yagurad/test/hooks/hook_points_test.dart | pre_start_hook_adds_arguments | 7 | green |
| plugin-hooks → Hook points | Mods-staged hook edits a config | apps/yagurad/test/hooks/hook_points_test.dart | mods_staged_hook_edits_a_config | 7 | red |
| plugin-hooks → Hook points | Hook not exported | apps/yagurad/test/hooks/hook_points_test.dart | hook_not_exported | 7 | green |
| plugin-hooks → Sandboxed host API | Reading a staged mod | apps/yagurad/test/hooks/sandboxed_host_api_test.dart | reading_a_staged_mod | 7 | red |
| plugin-hooks → Sandboxed host API | Edit into a staged mod refused | apps/yagurad/test/hooks/sandboxed_host_api_test.dart | edit_into_a_staged_mod_refused | 7 | red |
| log-streaming → Secrets masked in log streams | Password echoed by the server | apps/yagurad/test/logs/secrets_masked_in_log_streams_test.dart | password_echoed_by_the_server | 8 | red |
| log-streaming → Secrets masked in log streams | Backlog and crash lines masked | apps/yagurad/test/logs/secrets_masked_in_log_streams_test.dart | backlog_and_crash_lines_masked | 8 | red |
| log-streaming → Secrets masked in log streams | Replaced secret still masked | apps/yagurad/test/logs/secrets_masked_in_log_streams_test.dart | replaced_secret_still_masked | 8 | red |
| log-streaming → Secrets masked in log streams | Short secret inside a word | apps/yagurad/test/logs/secrets_masked_in_log_streams_test.dart | short_secret_inside_a_word | 8 | red |
| log-streaming → Secrets masked in log streams | No secrets set | apps/yagurad/test/logs/secrets_masked_in_log_streams_test.dart | no_secrets_set | 8 | red |
| plugin-hooks → Hook points | Migration hook result applied | apps/yagurad/test/hooks/hook_points_test.dart | migration_hook_result_applied | 8 | red |
| plugin-manifest → Plugin version changes re-validate instances | Removed setting migrated | apps/yagurad/test/plugins/plugin_version_changes_re_validate_instances_test.dart | removed_setting_migrated | 8 | red |
| plugin-manifest → Plugin version changes re-validate instances | Running instance after an invalidating reload | apps/yagurad/test/plugins/plugin_version_changes_re_validate_instances_test.dart | running_instance_after_an_invalidating_reload | 8 | red |
| plugin-manifest → Plugin version changes re-validate instances | Migration hook fails | apps/yagurad/test/plugins/plugin_version_changes_re_validate_instances_test.dart | migration_hook_fails | 8 | red |
| plugin-manifest → Plugin version changes re-validate instances | Settings no longer valid | apps/yagurad/test/plugins/plugin_version_changes_re_validate_instances_test.dart | settings_no_longer_valid | 8 | red |
| desktop-client → Config and plugin notices | External edit shown | apps/yagura_desktop/test/config_and_plugin_notices_test.dart | external_edit_shown | 9 | red |
| desktop-client → Config and plugin notices | Settings invalid after a reload | apps/yagura_desktop/test/config_and_plugin_notices_test.dart | settings_invalid_after_a_reload | 9 | red |
| desktop-client → Mods view | Mods added by id | apps/yagura_desktop/test/mods_view_test.dart | mods_added_by_id | 9 | red |
| desktop-client → Mods view | Key conflict shown | apps/yagura_desktop/test/mods_view_test.dart | key_conflict_shown | 9 | red |
| desktop-client → Mods view | Concurrent edit | apps/yagura_desktop/test/mods_view_test.dart | concurrent_edit | 9 | red |
| desktop-client → Operations and interactive prompts | Steam Guard prompt | apps/yagura_desktop/test/operations_and_interactive_prompts_test.dart | steam_guard_prompt | 9 | red |
| desktop-client → Operations and interactive prompts | Mobile approval prompt | apps/yagura_desktop/test/operations_and_interactive_prompts_test.dart | mobile_approval_prompt | 9 | red |
| desktop-client → Operations and interactive prompts | Prompt from another device's operation | apps/yagura_desktop/test/operations_and_interactive_prompts_test.dart | prompt_from_another_device_s_operation | 9 | red |
| desktop-client → Operations and interactive prompts | Prompt answered elsewhere | apps/yagura_desktop/test/operations_and_interactive_prompts_test.dart | prompt_answered_elsewhere | 9 | red |
| desktop-client → Operations and interactive prompts | Code rejected | apps/yagura_desktop/test/operations_and_interactive_prompts_test.dart | code_rejected | 9 | red |
| desktop-client → Steam accounts view | Account added from the desktop | apps/yagura_desktop/test/steam_accounts_view_test.dart | account_added_from_the_desktop | 9 | red |
| desktop-client → Steam accounts view | Account needs re-login | apps/yagura_desktop/test/steam_accounts_view_test.dart | account_needs_re_login | 9 | red |
| desktop-client → Steam accounts view | Removal refused | apps/yagura_desktop/test/steam_accounts_view_test.dart | removal_refused | 9 | red |
| daemon-protocol → Methods a daemon version does not implement | Method not built yet | apps/yagurad/test/api/methods_a_daemon_version_does_not_implement_test.dart | method_not_built_yet | 11 | green |
| daemon-protocol → Methods a daemon version does not implement | Service not built yet | apps/yagurad/test/api/methods_a_daemon_version_does_not_implement_test.dart | service_not_built_yet | 11 | red |

## 1. [M3] Steam Guard spike, migration 7, data layout and fixtures

- [ ] 1.1 Spike (design A1). The agent writes a throwaway script under `tool/spikes/m3_steam_guard/`. The user runs it on their own machine with a Steam test account they control, one run per Guard kind (email code, authenticator code, mobile approval). The script never stores the password. For each run it records SteamCMD's output and exit behaviour with stdin on NUL; whether `+login <user> <pass> <code>` completes; whether a mobile approval completes in the same run; and what `+login <user>` alone does with an expired or removed cached login (exit, password request, or loop). After each login it scans every file under the installation (`logs/`, `config/`, everything else) for the password. Record the results in `docs/spikes/m3-steam-guard.md`, including whether D3's file scrub is needed. Then add the `login` pattern group to `steam/patterns.yaml` (version 3) and regenerate it with `dart run tool/embed_steam_patterns.dart`. Verify: the spike document records each behaviour and the scan result; the embedded-patterns check in the existing Steam tests passes; the timeouts in D2 are confirmed or corrected in the spike document.
- [ ] 1.2 Extend `test/fixtures/fake_steamcmd/fake_steamcmd.dart`:
  - `+workshop_download_item <app> <item>` writing into `steamapps/workshop/content/<app>/<item>/`;
  - login transcripts from the spike (each Guard kind, wrong password, rate limit, expired cache, a mobile approval that arrives after a delay or never);
  - an echo of the command line, and a log file under the installation's `logs/` when the spike shows SteamCMD writes one.

  Add a fake Steam Web API server (`test/fixtures/fake_workshop_api.dart`) for `GetPublishedFileDetails`, with per-item results, `time_updated`, private or missing items, delays and failures. Verify: each fixture has a self-test under `test/fixtures/` that passes.
- [x] 1.3 Write the failing tests for this group's red rows (`default_layout_created`, `content_store_protected`), and `test/host/migration_7_test.dart`, which follows `migration_4_test.dart`. Verify: they fail because `content/` and the migration 7 tables are missing.
- [ ] 1.4 Add migration 7: `steam_accounts`, `operations.account_id`, `instance_mods` (with `stage_kind`), `content_versions`, `placed_keys`, `bound_files` and `replaced_secrets` (design D1, D6-D9, D11). Make `DataDirectory.prepare` create `content/` and `content/.staging/` (D6). Verify: `migration_7_test.dart` and `default_layout_created` pass, and those rows are flipped green. Re-run the green rows of this group (`data_directory_not_writable`; the `instance_roots_test.dart` rows run in the elevated workflow). Run `content_store_protected` in the elevated workflow and record the run in `docs/milestones/m3.md`, then flip it.

## 2. [M3] Lossless config parsers

- [x] 2.1 Collect real-file corpora under `packages/yagura_formats/test/corpus/`: DayZ `serverDZ.cfg`, `cfggameplay.json`, `BEServer_x64.cfg`, a generic INI with `;` and `#` comments, files with a BOM, CRLF and LF line endings, and trailing whitespace. Verify: each corpus file is present with its source noted in `corpus/README.md`.
- [x] 2.2 Write the failing tests for this group's rows, plus `corpus_round_trips_byte_for_byte`, which covers every corpus file in every format, in `round_trip_preservation_test.dart`. Verify: they fail because the parsers are missing.
- [x] 2.3 Implement `IniDocument`, `DayzCfgDocument` and `KvDocument` with the `JsonDocument` surface (`parse`, `toSource`, `get`, `set`), on token trees that keep comments, whitespace, line endings, BOM and order (D9). Verify: this group's rows and the corpus test pass, the rows are flipped green, and `dart analyze packages/yagura_formats` is clean.

## 3. [M3] Config binder and hook edits

- [ ] 3.1 Write the failing tests for this group's red rows. Verify: they fail for the missing binder, not for setup errors.
- [ ] 3.2 Accept the manifest's `bindings` section in `packages/yagura_plugin` (`loader.dart:404-426`, schema `manifest_schema.g.dart`): file path templates over `settings`, `ports`, `paths` and `os` that stay inside the instance root; `format`; `create` and `template`; `game_writes`; at most 64 distinct files; `ue-ini`, `xml` and `vdf` rejected with `unsupported_in_this_version`. Verify: the manifest tests for these refusals pass, and the manifest docs are regenerated.
- [ ] 3.3 Implement `ConfigBinder` to replace `FileEditWriter` (D9):
  - one pass per operation, applied in its order;
  - `bound_files` hashes and `external_edit` events, with secret values masked as `***`;
  - `game_writes`;
  - secret values read from the secret store at apply time only;
  - a 250 ms / 5 s lock retry that ends in `file_locked`, and rollback of the whole pass.

  `yagura.formats` in `hooks/host_api.dart` gains `ini`, `dayz-cfg` and `kv`. Verify: this group's rows pass and are flipped green. Re-run the green rows (`write_attempted_from_a_hook`, `path_escape_refused`, `edit_through_a_link_refused`) and the existing file-edit tests.

## 4. [M3] Manifest sections, secret launch arguments and GSLT

- [ ] 4.1 Write the failing tests for this group's red rows. Add a `windows`-tagged test `integration_test/process/secret_launch_args_test.dart` that starts a real relay in console mode and checks that the server's argv holds the value and no run file does. Verify: they fail because of the missing namespaces and channel.
- [ ] 4.2 Accept `mods` (sources `steam_workshop` and `server_managed`; `url_archive` rejected with `unsupported_in_this_version` naming `mods.source`; stage modes; `stage_dir`, default `server`; `link_name`; `copy_fallback`; key rules; roles) and `steam.gslt` in the loader and schema. Keep rejecting the `rcon` section, stop `rcon` and health `query`. Add the `mods.<role>` and `secrets.<setting>` template namespaces (`templates.dart:104-110,179-181`). Verify: the plugin-manifest and supported-formats rows of this group pass and are flipped green, and the manifest docs are regenerated.
- [ ] 4.3 Implement D4:
  - `LaunchInput` written and read in both modes (`windows_process_host.dart:173-185`, `run_command.dart:195-205`), with `launch_input_missing`;
  - the launcher-to-relay stdin pipe through `STARTF_USESTDHANDLES` in `CreateProcessAsUserW` and `spawnProcess`;
  - the relay reading the line before `writeRelay` (`launcher_modes.dart:248,280-300`);
  - `{"secret": ...}` entries in `launch.json`, and `***` in every reported argument list;
  - `gslt_required`.

  Verify: the GSLT rows and `secret_launch_args_test.dart` pass on Windows CI, and the rows are flipped green. The service-mode path is covered by extending `integration_test/service/game_servers_run_under_a_low_privilege_account_test.dart` (`elevated`), which runs in the elevated workflow; record that run in `docs/milestones/m3.md`. Re-run the green rows of this group.

## 5. [M3] Steam accounts, Steam Guard and prompts

- [ ] 5.1 Write the failing tests for this group's red rows against the fake SteamCMD transcripts from task 1.2. Verify: they fail because the Steam service is still a stub.
- [ ] 5.2 Implement the `Steam` service in place of its stub in `api/stub_apis.dart` (D1):
  - `ListAccounts`, `AddAccount`, `ReauthAccount` and `RemoveAccount` (`account_in_use`, `account_exists`, `too_many_accounts`);
  - one SteamCMD installation per account under `<data>/steamcmd/<id>/`;
  - runner queues keyed by subject (`account:<id>`, `host`);
  - startup recovery of `adding` rows;
  - the `account_optional` fix at `manifest.dart:282`;
  - account login in instance installs and updates.

  Verify: the account and login-mode rows pass.
- [ ] 5.3 Implement D2 and D13: the login step and the `login` patterns; `PromptBroker`, with compare-and-set answers, the 5-minute code and 2-minute mobile-approval waits, and `waiting_for_input`; `RespondToPrompt` (`prompt_resolved`, `prompt_answer_invalid`); `Operations.WatchPrompts`, with its entry in `security/method_access.dart`, 32 subscribers, 256 events behind and then a resync; the pending prompt in the operation snapshot. Verify: the daemon-protocol rows of this group pass.
- [ ] 5.4 Implement D3: the Scrubber on every SteamCMD line; `remember_password` stored as secret `steam:<id>` (`secret_store_unavailable`); `steam_reauth_required`; and SteamCMD's file scrub after each login run and at startup, if task 1.1 found the password in its files. Verify: the password rows pass. Flip this group's rows green and re-run its green rows (`anonymous_install`, `first_install_bootstraps_steamcmd`, `steamcmd_download_fails`, and the existing operations-stream rows).

## 6. [M3] Workshop metadata, downloads and content store

- [ ] 6.1 Write the failing tests for this group's red rows against the fake Web API and fake SteamCMD. Verify: they fail because the workshop client and the content store are missing.
- [ ] 6.2 Implement the workshop metadata client (D5): batches of 100, 1 request/s, a 15 s timeout, a configurable base URL, the version re-read after download, and `workshop_item_changing`. Verify: `workshop_item_downloaded` and `item_removed_from_the_workshop` pass.
- [ ] 6.3 Implement the content store (D6):
  - pipeline-owned acquisition runs that take the runner's installation lock and heavy slot, with their own cancel token and progress fanned out to waiters;
  - waiters that hold no lock or slot (`waiting_for_steamcmd`);
  - a shared prompt for each run (D2 "Prompts in pipeline runs");
  - a no-follow publish copy into `content/.staging/<run-id>/`, then a rename;
  - `content_versions`, the 2× disk check, GC at startup and daily, and `.staging` cleanup at startup.

  Verify: the content-store rows pass and this group's rows are flipped green.

## 7. [M3] Mod pipeline: rows, staging, keys, apply and updates

- [ ] 7.1 Write the failing tests for this group's red rows. Extend `integration_test/files/daemon_file_operations_do_not_follow_links_test.dart` (`windows`) with recorded-junction cases:
  - a read continues into the content store;
  - a write below the junction is refused;
  - a recorded path whose junction points at another target is `sandbox_violation`;
  - snapshot walks skip recorded paths.

  Verify: these tests fail because the junction FFI and the InstanceFs exception are missing.
- [ ] 7.2 Implement the junction FFI (`FSCTL_SET_REPARSE_POINT` and `FSCTL_GET_REPARSE_POINT`, relative to the instance root handle) and the recorded-junction exception in `InstanceFs` and `ConfinedFs` (D7, ADR 0015). Verify: the extended `windows` tests pass on Windows CI.
- [ ] 7.3 Implement the `Mods` service in place of its stub:
  - `SetMods`, with `expected_revision`, `too_many_mods` (256), roles, and background metadata that fixes each name once (`@<item id>` fallback);
  - `ListMods`, `ApplyMods` (`instance_running`), `CheckModUpdates` (subject `host` for all instances) and `UpdateMods`;
  - the mods mirrored into `instance.json`.

  Verify: the load-order, mod-change and durable-state rows pass.
- [ ] 7.4 Implement staging and keys (D7, D8):
  - recorded entries, `stage_kind` and the `.yagura-staged` marker, and `stage_name_conflict`;
  - copy fallback and `stage_link_failed`;
  - `server_managed`;
  - `placed_keys` and `key_conflict`, and `key_rule_too_broad`;
  - `onModsStaged` on every stage step, with staged mods in the hook context;
  - the `stage_mods` step in Start, the `update_mods` step in Update, and heavy-step accounting.

  Verify: the staging, key, hook-point and lifecycle rows pass.
- [ ] 7.5 Implement the update check timer (D14): every 6 h ± 30 min, first run 10 min after start, backoff from 5 min doubling to 6 h, and `mod_updates_available` deltas on `WatchInstances`. Verify: the update-detection and `mod_update_count_delta` rows pass. Flip this group's rows green and re-run its green rows (`instance_state_and_event_stream_test.dart`, `one_operation_per_instance_at_a_time_test.dart`, `durable_state_with_a_portable_instance_file_test.dart`, `hook_points_test.dart`, `hook_input_and_output_contract_test.dart`, `updates_stop_and_restart_a_running_server_test.dart`).

## 8. [M3] Plugin migrations and log masking

- [ ] 8.1 Write the failing tests for this group's red rows. Verify: they fail for the missing migration operation and masker.
- [ ] 8.2 Implement D10: the `migrate_settings` operation at the queue head, outside the 10-operation bound and retargeted by a repeat reload; the `pluginVersion` write moved out of `reconcilePlugins` (`instance_manager.dart:1312-1320`); the `migrateSettings` hook with secret placeholders; the gate (`invalid_state`, with stop and delete exempt); the recovery (a valid save records the loaded version); and startup reconciliation. Verify: the plugin-version rows and `migration_hook_result_applied` pass.
- [ ] 8.3 Implement D11: `SecretMasker` at log ingestion, rebuilt on secret changes; `replaced_secrets` pruned hourly after 24 h; substring matching from 6 characters, whole-word matching below that. Verify: the log-streaming rows pass, and this group's rows are flipped green.

## 9. [M3] Desktop: prompts, accounts, mods and notices

- [ ] 9.1 Extend `DaemonTransport` (`lib/src/transport.dart`) and `test/support/fake_daemon.dart` with the Steam and Mods methods, `WatchPrompts` and `RespondToPrompt`. Write the failing widget tests for this group's rows. Verify: they fail because the views are missing.
- [ ] 9.2 Implement the desktop side:
  - handle `prompt`, `promptResolved` and `eventsDropped` in `connection.dart:564-643` instead of dropping them, and open `WatchPrompts` per connected daemon;
  - the prompt dialog for the code kinds and mobile approval, answered elsewhere, and code rejected;
  - the Steam accounts view, which clears the password field after the call and stores it nowhere, and shows reauth and refused removal;
  - the account picker on the instance;
  - the mods view (add by id, order, roles, warnings, `revision_conflict`);
  - the external-edit and `settings_invalid` notices.

  Verify: this group's rows pass and are flipped green, and `flutter analyze` and the existing desktop tests pass.

## 10. [M3] DayZ plugin and real-host verification

- [ ] 10.1 Write `plugins/dayz/` per D12:
  - account login, app 223350, workshop app 221100;
  - `server/yagura/serverDZ.cfg` and `server/yagura/battleye/BEServer_x64.cfg` created from templates, with `dayz-cfg` and `kv` bindings;
  - `stage_dir: server`, `link_name: "@{{mod.name_safe}}"`, `copy_fallback: true`, key rule to `server/keys/`, roles `client` and `server`;
  - `-config`, `-BEpath`, `-profiles`, `-mod=` and `-serverMod=`;
  - `data_paths` and log sources under `server/`, `log_match` health, stop `signal` with a 60 s grace period, and no `rcon` section.

  Verify: `yagura plugin lint plugins/dayz` passes, and a loader test shows the plugin `loaded`.
- [ ] 10.2 Add an in-process end-to-end test, `apps/yagurad/test/mods/dayz_mods_end_to_end_test.dart` (fake SteamCMD, fake Web API, fake process host). In it:
  - a DayZ instance with 12 workshop mods goes from mod ids to a launched server in one `Start`, with links, keys, `-mod=` order and the bound files;
  - a second instance with the same mod version shares one content-store directory;
  - a mod update re-links only the changed mod.

  Verify: the test passes. It covers exit criterion 4 and the agent side of exit criterion 3; record it in `docs/milestones/m3.md`.
- [ ] 10.3 (user) On a Windows host with DayZ Server and BattlEye, which the user runs:
  - add a Steam account protected by Steam Guard from the desktop;
  - check that the code prompt reaches the desktop and the login completes;
  - search the data directory and the daemon logs for the password, and find none;
  - take DayZ with 10+ workshop mods from mod ids to a running server with linked mods and keys in one action;
  - check that the server stays correct across a mod update.

  The same run also settles two design assumptions:
  - **A2:** does DayZ save and exit on Ctrl+C? If not, switch the plugin to `kill` and note it.
  - **A3:** does BattlEye load mods through junctions? If not, the plugin keeps `copy_fallback` and the result is noted.

  Verify: the user's results for exit criteria 2 and 3 are recorded in `docs/milestones/m3.md`. They are never marked passed on the user's behalf.

## 11. [M3] Integration, write-back and M3 exit

- [ ] 11.1 Extend `apps/yagurad/integration_test/secrets_data_directory_scan_test.dart` with a run that adds an account through the fake SteamCMD with a known password, remembered and not remembered, and sets a GSLT and a secret bound into a config file. Scan the data directory, the account installations, snapshots, run files, operation history and daemon logs. Verify: no secret value is found outside the accepted locations: the secrets table, SteamCMD's `config.vdf` cached token, and a bound secret's own file.
- [ ] 11.2 Update `docs/protocol.md`: this version implements `Steam`, `Mods`, `Operations.WatchPrompts` and `RespondToPrompt`, and still not `Rcon`. Verify: `service_not_built_yet` and `method_not_built_yet` pass and are flipped green, and the document lists the methods.
- [ ] 11.3 Write back into `openspec/architecture.md`:
  - the content-store publisher is the mod pipeline, not the Steam service (line 155);
  - the components this change adds (account service, prompt broker, workshop client, config binder, secret masker);
  - the State & Ownership and Resource Bounds rows this design adds (accounts 32, mods per instance 256, prompts, `WatchPrompts` 32, bound files 64, key rules 1,024, update check).

  Verify: each is present in `openspec/architecture.md`.
- [ ] 11.4 Run every package's tests on Windows CI and `openspec validate --all --strict`, and run the elevated workflow once for this change's `elevated` rows. Verify: everything passes, every test-map row is green, and the agent-verified exit criteria 1, 4, 5 and 6 are recorded in `docs/milestones/m3.md` with run links.

## Workflow follow-up

- Archive this change after its PR merges, and run `specwright-roadmap close` for M3 once exit criteria 2 and 3 have the user's results.
- The material this change took from `platform-backlog` (groups 14-17, decisions D8 and D19, and the M3 requirements) is already deleted there. M4 starts from what is left.
- When a task adds a dependency to any workspace package, re-run the dependency skill discovery and update `.claude/skills/UPSTREAM.json`.
- Releases are off (`release.enabled: false`), so no version bump task.
