# Tasks

## Test map

Every scenario maps to a Dart test at the boundary it crosses: daemon behaviour against an in-process daemon with fake SteamCMD, fake process host and fake firewall where the real one is not needed; process rows against the real OS on the Windows CI runner (`integration_test/`, tagged `windows`); desktop rows as Flutter widget tests against a fake daemon connection. The group column says which task group turns the row green; every group belongs to M1.

| Requirement | Scenario | Test file | Test name | Group | State |
|---|---|---|---|---|---|
| plugin-hooks → Hook deadline | Infinite loop interrupted | packages/yagura_js/test/hook_deadline_test.dart | infinite_loop_interrupted | 2 (M1) | red |
| plugin-hooks → Hook deadline | Manifest deadline above the cap | packages/yagura_js/test/hook_deadline_test.dart | manifest_deadline_above_the_cap | 2 (M1) | red |
| plugin-hooks → Hook errors are reported with location | Thrown error | apps/yagurad/test/hooks/hook_errors_are_reported_with_location_test.dart | thrown_error | 2 (M1) | red |
| plugin-hooks → Hook errors are reported with location | Syntax error at load | apps/yagurad/test/hooks/hook_errors_are_reported_with_location_test.dart | syntax_error_at_load | 2 (M1) | red |
| plugin-hooks → Hook host calls are bounded | Large file read refused | apps/yagurad/test/hooks/hook_host_calls_are_bounded_test.dart | large_file_read_refused | 2 (M1) | red |
| plugin-hooks → Hook host calls are bounded | Waiting for a worker | apps/yagurad/test/hooks/hook_host_calls_are_bounded_test.dart | waiting_for_a_worker | 2 (M1) | red |
| plugin-hooks → Hook host calls are bounded | Degraded hook runtime | apps/yagurad/test/hooks/hook_host_calls_are_bounded_test.dart | degraded_hook_runtime | 2 (M1) | red |
| plugin-hooks → Hook host calls are bounded | Directory listing within limit | apps/yagurad/test/hooks/hook_host_calls_are_bounded_test.dart | directory_listing_within_limit | 2 (M1) | red |
| plugin-hooks → Hook input and output contract | Context contents | apps/yagurad/test/hooks/hook_input_and_output_contract_test.dart | context_contents | 2 (M1) | red |
| plugin-hooks → Hook input and output contract | Invalid result shape | apps/yagurad/test/hooks/hook_input_and_output_contract_test.dart | invalid_result_shape | 2 (M1) | red |
| plugin-hooks → Hook memory cap | Allocation beyond the cap | packages/yagura_js/test/hook_memory_cap_test.dart | allocation_beyond_the_cap | 2 (M1) | red |
| plugin-hooks → Hook memory cap | Oversized result | packages/yagura_js/test/hook_memory_cap_test.dart | oversized_result | 2 (M1) | red |
| plugin-hooks → Hook points | Pre-start hook adds arguments | apps/yagurad/test/hooks/hook_points_test.dart | pre_start_hook_adds_arguments | 2 (M1) | red |
| plugin-hooks → Hook points | Hook not exported | apps/yagurad/test/hooks/hook_points_test.dart | hook_not_exported | 2 (M1) | red |
| plugin-hooks → Sandboxed host API | File edit returned and applied by the daemon | apps/yagurad/test/hooks/sandboxed_host_api_test.dart | file_edit_returned_and_applied_by_the_daemon | 2 (M1) | red |
| plugin-hooks → Sandboxed host API | Write attempted from a hook | apps/yagurad/test/hooks/sandboxed_host_api_test.dart | write_attempted_from_a_hook | 2 (M1) | red |
| plugin-hooks → Sandboxed host API | Path escape refused | apps/yagurad/test/hooks/sandboxed_host_api_test.dart | path_escape_refused | 2 (M1) | red |
| plugin-hooks → Sandboxed host API | Edit into a staged mod refused | apps/yagurad/test/hooks/sandboxed_host_api_test.dart | edit_into_a_staged_mod_refused | 2 (M1) | red |
| plugin-manifest → Executable is the long-running server | Long-running executable tracked | packages/yagura_plugin/test/executable_is_the_long_running_server_test.dart | long_running_executable_tracked | 3 (M1) | red |
| plugin-manifest → Executable is the long-running server | Bootstrapper exits | packages/yagura_plugin/test/executable_is_the_long_running_server_test.dart | bootstrapper_exits | 3 (M1) | red |
| plugin-manifest → Launch templates | Conditional and joined arguments | packages/yagura_plugin/test/launch_templates_test.dart | conditional_and_joined_arguments | 3 (M1) | red |
| plugin-manifest → Launch templates | Template references an unknown setting | packages/yagura_plugin/test/launch_templates_test.dart | template_references_an_unknown_setting | 3 (M1) | red |
| plugin-manifest → Launch templates | Missing executable for this OS | packages/yagura_plugin/test/launch_templates_test.dart | missing_executable_for_this_os | 3 (M1) | red |
| plugin-manifest → Plugin discovery and validation | Valid plugin loaded | packages/yagura_plugin/test/plugin_discovery_and_validation_test.dart | valid_plugin_loaded | 3 (M1) | red |
| plugin-manifest → Plugin discovery and validation | Invalid manifest rejected with location | packages/yagura_plugin/test/plugin_discovery_and_validation_test.dart | invalid_manifest_rejected_with_location | 3 (M1) | red |
| plugin-manifest → Plugin discovery and validation | Unknown manifest version | packages/yagura_plugin/test/plugin_discovery_and_validation_test.dart | unknown_manifest_version | 3 (M1) | red |
| plugin-manifest → Plugin reload without restart | Fixed manifest picked up | packages/yagura_plugin/test/plugin_reload_without_restart_test.dart | fixed_manifest_picked_up | 3 (M1) | red |
| plugin-manifest → Plugin reload without restart | Broken edit keeps the old version | packages/yagura_plugin/test/plugin_reload_without_restart_test.dart | broken_edit_keeps_the_old_version | 3 (M1) | red |
| plugin-manifest → Plugin size limits | Oversized hooks file | packages/yagura_plugin/test/plugin_size_limits_test.dart | oversized_hooks_file | 3 (M1) | red |
| plugin-manifest → Plugin size limits | Within limits | packages/yagura_plugin/test/plugin_size_limits_test.dart | within_limits | 3 (M1) | red |
| plugin-manifest → Port declarations | Derived port follows its base | packages/yagura_plugin/test/port_declarations_test.dart | derived_port_follows_its_base | 3 (M1) | red |
| plugin-manifest → Port declarations | Derived port collides | packages/yagura_plugin/test/port_declarations_test.dart | derived_port_collides | 3 (M1) | red |
| plugin-manifest → Save data paths stay inside the instance | Valheim save directory inside the instance | packages/yagura_plugin/test/save_data_paths_stay_inside_the_instance_test.dart | valheim_save_directory_inside_the_instance | 3 (M1) | red |
| plugin-manifest → Save data paths stay inside the instance | Data path outside the instance | packages/yagura_plugin/test/save_data_paths_stay_inside_the_instance_test.dart | data_path_outside_the_instance | 3 (M1) | red |
| plugin-manifest → Settings schema types and constraints | Repeatable structure validated | packages/yagura_plugin/test/settings_schema_types_and_constraints_test.dart | repeatable_structure_validated | 3 (M1) | red |
| plugin-manifest → Settings schema types and constraints | Row with missing required field | packages/yagura_plugin/test/settings_schema_types_and_constraints_test.dart | row_with_missing_required_field | 3 (M1) | red |
| plugin-manifest → Settings schema types and constraints | Secret values are write-only | packages/yagura_plugin/test/settings_schema_types_and_constraints_test.dart | secret_values_are_write_only | 3 (M1) | red |
| plugin-manifest → Stop and health declarations | Log-match health check | packages/yagura_plugin/test/stop_and_health_declarations_test.dart | log_match_health_check | 3 (M1) | red |
| plugin-manifest → Stop and health declarations | Invalid health regex | packages/yagura_plugin/test/stop_and_health_declarations_test.dart | invalid_health_regex | 3 (M1) | red |
| host-service → Data directory layout | Default layout created | apps/yagurad/test/host/data_directory_layout_test.dart | default_layout_created | 4 (M1) | red |
| host-service → Data directory layout | Data directory not writable | apps/yagurad/test/host/data_directory_layout_test.dart | data_directory_not_writable | 4 (M1) | red |
| host-service → Single daemon per data directory | Second instance refused | apps/yagurad/test/host/single_daemon_per_data_directory_test.dart | second_instance_refused | 4 (M1) | red |
| host-service → Single daemon per data directory | Lock file left by a crashed daemon | apps/yagurad/test/host/single_daemon_per_data_directory_test.dart | lock_file_left_by_a_crashed_daemon | 4 (M1) | red |
| host-service → Startup sequence | Migration with backup | apps/yagurad/test/host/startup_sequence_test.dart | migration_with_backup | 4 (M1) | red |
| host-service → Startup sequence | Migration fails | apps/yagurad/test/host/startup_sequence_test.dart | migration_fails | 4 (M1) | red |
| instance-lifecycle → Deleting an instance protects game data | Delete with files snapshots first | apps/yagurad/test/instances/deleting_an_instance_protects_game_data_test.dart | delete_with_files_snapshots_first | 4 (M1) | red |
| instance-lifecycle → Deleting an instance protects game data | Delete an instance whose plugin is missing | apps/yagurad/test/instances/deleting_an_instance_protects_game_data_test.dart | delete_an_instance_whose_plugin_is_missing | 4 (M1) | red |
| instance-lifecycle → Deleting an instance protects game data | Delete keeping files | apps/yagurad/test/instances/deleting_an_instance_protects_game_data_test.dart | delete_keeping_files | 4 (M1) | red |
| instance-lifecycle → Deleting an instance protects game data | Delete with wrong confirmation | apps/yagurad/test/instances/deleting_an_instance_protects_game_data_test.dart | delete_with_wrong_confirmation | 4 (M1) | red |
| instance-lifecycle → Durable state with a portable instance file | Change persisted and mirrored | apps/yagurad/test/instances/durable_state_with_a_portable_instance_file_test.dart | change_persisted_and_mirrored | 4 (M1) | red |
| instance-lifecycle → Durable state with a portable instance file | instance.json write fails | apps/yagurad/test/instances/durable_state_with_a_portable_instance_file_test.dart | instance_json_write_fails | 4 (M1) | red |
| instance-lifecycle → Durable state with a portable instance file | Secrets excluded from instance.json | apps/yagurad/test/instances/durable_state_with_a_portable_instance_file_test.dart | secrets_excluded_from_instance_json | 4 (M1) | red |
| instance-lifecycle → Error reasons have defined exits | Acknowledge a crash loop | apps/yagurad/test/instances/error_reasons_have_defined_exits_test.dart | acknowledge_a_crash_loop | 4 (M1) | red |
| instance-lifecycle → Error reasons have defined exits | Start refused with invalid settings | apps/yagurad/test/instances/error_reasons_have_defined_exits_test.dart | start_refused_with_invalid_settings | 4 (M1) | red |
| instance-lifecycle → Error reasons have defined exits | Update clears an interrupted update | apps/yagurad/test/instances/error_reasons_have_defined_exits_test.dart | update_clears_an_interrupted_update | 4 (M1) | red |
| instance-lifecycle → Instance creation validates settings against the plugin schema | Valid instance created | apps/yagurad/test/instances/instance_creation_validates_settings_against_the_test.dart | valid_instance_created | 4 (M1) | red |
| instance-lifecycle → Instance creation validates settings against the plugin schema | Setting violates the schema | apps/yagurad/test/instances/instance_creation_validates_settings_against_the_test.dart | setting_violates_the_schema | 4 (M1) | red |
| instance-lifecycle → Instance creation validates settings against the plugin schema | Directory outside the instance roots | apps/yagurad/test/instances/instance_creation_validates_settings_against_the_test.dart | directory_outside_the_instance_roots | 4 (M1) | red |
| instance-lifecycle → Instance creation validates settings against the plugin schema | Port equal to the daemon API port | apps/yagurad/test/instances/instance_creation_validates_settings_against_the_test.dart | port_equal_to_the_daemon_api_port | 4 (M1) | red |
| instance-lifecycle → Instance creation validates settings against the plugin schema | Port collision with another instance | apps/yagurad/test/instances/instance_creation_validates_settings_against_the_test.dart | port_collision_with_another_instance | 4 (M1) | red |
| instance-lifecycle → Instance state machine | Start from stopped | apps/yagurad/test/instances/instance_state_machine_test.dart | start_from_stopped | 4 (M1) | red |
| instance-lifecycle → Instance state machine | Start while not installed | apps/yagurad/test/instances/instance_state_machine_test.dart | start_while_not_installed | 4 (M1) | red |
| instance-lifecycle → Instance state machine | Process exits during the health window | apps/yagurad/test/instances/instance_state_machine_test.dart | process_exits_during_the_health_window | 4 (M1) | red |
| instance-lifecycle → Instance state machine | Health check never passes | apps/yagurad/test/instances/instance_state_machine_test.dart | health_check_never_passes | 4 (M1) | red |
| instance-lifecycle → Interrupted operations are reported after a daemon restart | Daemon killed during an update | apps/yagurad/test/instances/interrupted_operations_are_reported_after_a_daem_test.dart | daemon_killed_during_an_update | 4 (M1) | red |
| instance-lifecycle → Interrupted operations are reported after a daemon restart | Daemon killed during install | apps/yagurad/test/instances/interrupted_operations_are_reported_after_a_daem_test.dart | daemon_killed_during_install | 4 (M1) | red |
| instance-lifecycle → One operation per instance at a time | Concurrent requests on one instance | apps/yagurad/test/instances/one_operation_per_instance_at_a_time_test.dart | concurrent_requests_on_one_instance | 4 (M1) | red |
| instance-lifecycle → One operation per instance at a time | Stop requested while starting | apps/yagurad/test/instances/one_operation_per_instance_at_a_time_test.dart | stop_requested_while_starting | 4 (M1) | red |
| instance-lifecycle → One operation per instance at a time | Stop during the health wait | apps/yagurad/test/instances/one_operation_per_instance_at_a_time_test.dart | stop_during_the_health_wait | 4 (M1) | red |
| instance-lifecycle → One operation per instance at a time | Queued operation becomes invalid | apps/yagurad/test/instances/one_operation_per_instance_at_a_time_test.dart | queued_operation_becomes_invalid | 4 (M1) | red |
| instance-lifecycle → One operation per instance at a time | Queue full | apps/yagurad/test/instances/one_operation_per_instance_at_a_time_test.dart | queue_full | 4 (M1) | red |
| instance-lifecycle → Operations report progress and can be cancelled | Install progress streamed | apps/yagurad/test/instances/operations_report_progress_and_can_be_cancelled_test.dart | install_progress_streamed | 4 (M1) | red |
| instance-lifecycle → Operations report progress and can be cancelled | Install cancelled mid-download | apps/yagurad/test/instances/operations_report_progress_and_can_be_cancelled_test.dart | install_cancelled_mid_download | 4 (M1) | red |
| instance-lifecycle → Operations report progress and can be cancelled | Update cancelled after the server was stopped | apps/yagurad/test/instances/operations_report_progress_and_can_be_cancelled_test.dart | update_cancelled_after_the_server_was_stopped | 4 (M1) | red |
| instance-lifecycle → Operations report progress and can be cancelled | Stop cancels queued starts | apps/yagurad/test/instances/operations_report_progress_and_can_be_cancelled_test.dart | stop_cancels_queued_starts | 4 (M1) | red |
| instance-lifecycle → Autostart after daemon or host restart | Host rebooted | apps/yagurad/test/instances/autostart_after_daemon_or_host_restart_test.dart | host_rebooted | 5 (M1) | red |
| instance-lifecycle → Autostart after daemon or host restart | Instance stopped by the admin before the reboot | apps/yagurad/test/instances/autostart_after_daemon_or_host_restart_test.dart | instance_stopped_by_the_admin_before_the_reboot | 5 (M1) | red |
| instance-lifecycle → Autostart after daemon or host restart | Crash-looped instance not autostarted | apps/yagurad/test/instances/autostart_after_daemon_or_host_restart_test.dart | crash_looped_instance_not_autostarted | 5 (M1) | red |
| instance-lifecycle → Autostart after daemon or host restart | Autostart fails | apps/yagurad/test/instances/autostart_after_daemon_or_host_restart_test.dart | autostart_fails | 5 (M1) | red |
| instance-lifecycle → Crash detection and restart policy | Crash is restarted | apps/yagurad/test/instances/crash_detection_and_restart_policy_test.dart | crash_is_restarted | 5 (M1) | red |
| instance-lifecycle → Crash detection and restart policy | Crash loop stops restarting | apps/yagurad/test/instances/crash_detection_and_restart_policy_test.dart | crash_loop_stops_restarting | 5 (M1) | red |
| instance-lifecycle → Graceful stop per plugin strategy | Grace period exceeded | apps/yagurad/test/instances/graceful_stop_per_plugin_strategy_test.dart | grace_period_exceeded | 5 (M1) | red |
| instance-lifecycle → Running servers survive daemon restarts | Re-attach after daemon restart | apps/yagurad/test/instances/running_servers_survive_daemon_restarts_test.dart | re_attach_after_daemon_restart | 5 (M1) | red |
| instance-lifecycle → Running servers survive daemon restarts | PID reused by another process | apps/yagurad/test/instances/running_servers_survive_daemon_restarts_test.dart | pid_reused_by_another_process | 5 (M1) | red |
| instance-lifecycle → Save data is declared and snapshotted | Snapshot before update | apps/yagurad/test/instances/save_data_is_declared_and_snapshotted_test.dart | snapshot_before_update | 6 (M1) | red |
| instance-lifecycle → Save data is declared and snapshotted | Not enough space for a snapshot | apps/yagurad/test/instances/save_data_is_declared_and_snapshotted_test.dart | not_enough_space_for_a_snapshot | 6 (M1) | red |
| instance-lifecycle → Save data is declared and snapshotted | Restore a snapshot | apps/yagurad/test/instances/save_data_is_declared_and_snapshotted_test.dart | restore_a_snapshot | 6 (M1) | red |
| instance-lifecycle → Save data is declared and snapshotted | Restoring the oldest snapshot | apps/yagurad/test/instances/save_data_is_declared_and_snapshotted_test.dart | restoring_the_oldest_snapshot | 6 (M1) | red |
| instance-lifecycle → Save data is declared and snapshotted | Snapshot skipped on request | apps/yagurad/test/instances/save_data_is_declared_and_snapshotted_test.dart | snapshot_skipped_on_request | 6 (M1) | red |
| instance-lifecycle → Save data is declared and snapshotted | Pre-delete snapshot of a deleted instance | apps/yagurad/test/instances/save_data_is_declared_and_snapshotted_test.dart | pre_delete_snapshot_of_a_deleted_instance | 6 (M1) | red |
| instance-lifecycle → Updates stop and restart a running server | Update while running | apps/yagurad/test/instances/updates_stop_and_restart_a_running_server_test.dart | update_while_running | 6 (M1) | red |
| instance-lifecycle → Updates stop and restart a running server | Update fails after stop | apps/yagurad/test/instances/updates_stop_and_restart_a_running_server_test.dart | update_fails_after_stop | 6 (M1) | red |
| steam-content → Install, update and validate apps | Update reports progress | apps/yagurad/test/steam/install_update_and_validate_apps_test.dart | update_reports_progress | 6 (M1) | red |
| steam-content → Install, update and validate apps | Two instances of one app installed at once | apps/yagurad/test/steam/install_update_and_validate_apps_test.dart | two_instances_of_one_app_installed_at_once | 6 (M1) | red |
| steam-content → Install, update and validate apps | Not enough disk space | apps/yagurad/test/steam/install_update_and_validate_apps_test.dart | not_enough_disk_space | 6 (M1) | red |
| steam-content → Login mode per plugin | Anonymous install | apps/yagurad/test/steam/login_mode_per_plugin_test.dart | anonymous_install | 6 (M1) | red |
| steam-content → SteamCMD is installed and managed by the daemon | First install bootstraps SteamCMD | apps/yagurad/test/steam/steamcmd_is_installed_and_managed_by_the_daemon_test.dart | first_install_bootstraps_steamcmd | 6 (M1) | red |
| steam-content → SteamCMD is installed and managed by the daemon | SteamCMD download fails | apps/yagurad/test/steam/steamcmd_is_installed_and_managed_by_the_daemon_test.dart | steamcmd_download_fails | 6 (M1) | red |
| steam-content → SteamCMD runs are bounded and cleaned up | Stalled download | apps/yagurad/test/steam/steamcmd_runs_are_bounded_and_cleaned_up_test.dart | stalled_download | 6 (M1) | red |
| steam-content → SteamCMD runs are bounded and cleaned up | Stray SteamCMD after a crash | apps/yagurad/test/steam/steamcmd_runs_are_bounded_and_cleaned_up_test.dart | stray_steamcmd_after_a_crash | 6 (M1) | red |
| steam-content → SteamCMD runs non-interactively | Known failure classified | apps/yagurad/test/steam/steamcmd_runs_non_interactively_test.dart | known_failure_classified | 6 (M1) | red |
| steam-content → SteamCMD runs non-interactively | Unknown failure surfaced | apps/yagurad/test/steam/steamcmd_runs_non_interactively_test.dart | unknown_failure_surfaced | 6 (M1) | red |
| log-streaming → Bounded buffer and backlog | Backlog after restart | apps/yagurad/test/logs/bounded_buffer_and_backlog_test.dart | backlog_after_restart | 7 (M1) | red |
| log-streaming → Bounded buffer and backlog | Request above the limit | apps/yagurad/test/logs/bounded_buffer_and_backlog_test.dart | request_above_the_limit | 7 (M1) | red |
| log-streaming → Declared log sources | Newest file followed after rotation | apps/yagurad/test/logs/declared_log_sources_test.dart | newest_file_followed_after_rotation | 7 (M1) | red |
| log-streaming → Declared log sources | Pattern matches nothing | apps/yagurad/test/logs/declared_log_sources_test.dart | pattern_matches_nothing | 7 (M1) | red |
| log-streaming → Encoding-aware decoding | SCUM UTF-16 log | apps/yagurad/test/logs/encoding_aware_decoding_test.dart | scum_utf_16_log | 7 (M1) | red |
| log-streaming → Encoding-aware decoding | Invalid bytes | apps/yagurad/test/logs/encoding_aware_decoding_test.dart | invalid_bytes | 7 (M1) | red |
| log-streaming → Live follow with backpressure | Live lines delivered | apps/yagurad/test/logs/live_follow_with_backpressure_test.dart | live_lines_delivered | 7 (M1) | red |
| log-streaming → Live follow with backpressure | Slow subscriber | apps/yagurad/test/logs/live_follow_with_backpressure_test.dart | slow_subscriber | 7 (M1) | red |
| log-streaming → Stdout captured to a file | Stdout survives daemon restart | apps/yagurad/test/logs/stdout_captured_to_a_file_test.dart | stdout_survives_daemon_restart | 7 (M1) | red |
| log-streaming → Stdout captured to a file | Capture file rotation | apps/yagurad/test/logs/stdout_captured_to_a_file_test.dart | capture_file_rotation | 7 (M1) | red |
| daemon-protocol → API version negotiation | Compatible versions | apps/yagurad/test/api/api_version_negotiation_test.dart | compatible_versions | 8 (M1) | red |
| daemon-protocol → API version negotiation | Incompatible major | apps/yagurad/test/api/api_version_negotiation_test.dart | incompatible_major | 8 (M1) | red |
| daemon-protocol → API version negotiation | Overlap during a migration | apps/yagurad/test/api/api_version_negotiation_test.dart | overlap_during_a_migration | 8 (M1) | red |
| daemon-protocol → Instance state and event stream | Snapshot then deltas | apps/yagurad/test/api/instance_state_and_event_stream_test.dart | snapshot_then_deltas | 8 (M1) | red |
| daemon-protocol → Instance state and event stream | State-only delta | apps/yagurad/test/api/instance_state_and_event_stream_test.dart | state_only_delta | 8 (M1) | red |
| daemon-protocol → Instance state and event stream | Slow subscriber | apps/yagurad/test/api/instance_state_and_event_stream_test.dart | slow_subscriber | 8 (M1) | red |
| daemon-protocol → Long operations are asynchronous with resumable progress | Reconnect without losing events | apps/yagurad/test/api/long_operations_are_asynchronous_with_resumable__test.dart | reconnect_without_losing_events | 8 (M1) | red |
| daemon-protocol → Long operations are asynchronous with resumable progress | Missed events no longer retained | apps/yagurad/test/api/long_operations_are_asynchronous_with_resumable__test.dart | missed_events_no_longer_retained | 8 (M1) | red |
| daemon-protocol → Long operations are asynchronous with resumable progress | Operation pruned from history | apps/yagurad/test/api/long_operations_are_asynchronous_with_resumable__test.dart | operation_pruned_from_history | 8 (M1) | red |
| daemon-protocol → Message size limits | Oversized request | apps/yagurad/test/api/message_size_limits_test.dart | oversized_request | 8 (M1) | red |
| daemon-protocol → Message size limits | Paged backlog | apps/yagurad/test/api/message_size_limits_test.dart | paged_backlog | 8 (M1) | red |
| daemon-protocol → Plugin-shaped data as versioned JSON | Stale form submission | apps/yagurad/test/api/plugin_shaped_data_as_versioned_json_test.dart | stale_form_submission | 8 (M1) | red |
| daemon-protocol → Plugin-shaped data as versioned JSON | Malformed JSON | apps/yagurad/test/api/plugin_shaped_data_as_versioned_json_test.dart | malformed_json | 8 (M1) | red |
| daemon-protocol → Structured errors | Field violation detail | apps/yagurad/test/api/structured_errors_test.dart | field_violation_detail | 8 (M1) | red |
| daemon-protocol → Structured errors | Unexpected internal failure | apps/yagurad/test/api/structured_errors_test.dart | unexpected_internal_failure | 8 (M1) | red |
| daemon-security → Development mode is localhost only | Dev mode on loopback | apps/yagurad/test/security/development_mode_is_localhost_only_test.dart | dev_mode_on_loopback | 8 (M1) | red |
| daemon-security → Development mode is localhost only | Dev mode on a public address | apps/yagurad/test/security/development_mode_is_localhost_only_test.dart | dev_mode_on_a_public_address | 8 (M1) | red |
| desktop-client → Forms rendered from plugin schemas | Daemon rejects a value | apps/yagura_desktop/test/forms_rendered_from_plugin_schemas_test.dart | daemon_rejects_a_value | 9 (M1) | red |
| desktop-client → Forms rendered from plugin schemas | Unknown field type | apps/yagura_desktop/test/forms_rendered_from_plugin_schemas_test.dart | unknown_field_type | 9 (M1) | red |
| desktop-client → Logs and console views | Follow and pause | apps/yagura_desktop/test/logs_and_console_views_test.dart | follow_and_pause | 9 (M1) | red |
| desktop-client → Logs and console views | Dropped lines marker | apps/yagura_desktop/test/logs_and_console_views_test.dart | dropped_lines_marker | 9 (M1) | red |
| instance-lifecycle → Graceful stop per plugin strategy | Valheim saves on a signal stop | apps/yagurad/test/instances/graceful_stop_per_plugin_strategy_test.dart | valheim_saves_on_a_signal_stop | 9 (M1) | red |

## 1. [M1] Workspace and first spikes

- [ ] 1.1 Create the pub workspace from design D1: `apps/yagurad`, `apps/yagura_desktop`, `packages/{yagura_proto,yagura_js,yagura_formats,yagura_plugin}`, `proto/`, `schemas/`, `plugins/`, `tool/`; `apps/yagura_desktop` from `flutter create --platforms=windows,linux` (no other platform folders; macOS is undecided) reduced to a placeholder app; `analysis_options.yaml` with strict casts and inference on `package:lints` (`package:flutter_lints` for the desktop app); `analyze` (whole workspace) and `test` (`dart test` per Dart package, `flutter test` for the desktop app) tasks in `mise.toml` next to the existing `format`, `format:check`, `changelog` and `release-notes`; a Windows + Linux CI workflow that installs the toolchain pinned in `mise.toml` and runs `mise run format:check`, `mise run analyze` and `mise run test`. After `pub get`, discover dependency-provided agent skills with the `skills` package and install only those from dependencies the workspace actually uses into `.claude/skills/`, recorded in `.claude/skills/UPSTREAM.json`. Verify: CI is green on an empty test per package.
- [ ] 1.2 Spike (ADR 0003): vendor quickjs-ng (pinned tag, MIT notice) in `packages/yagura_js/third_party/`, add `hook/build.dart` using `native_toolchain_c` to compile it on Windows (MSVC) and Linux, and a smoke test that evaluates `1+1` through FFI. Verify: the smoke test passes on the Windows CI runner. If MSVC fails, try clang-cl; record the outcome in `packages/yagura_js/README.md`.
- [ ] 1.3 Spike (ADR 0009): a throwaway `yagurad launch`/`relay`/`signal` prototype that starts `valheim_server.exe` (anonymous SteamCMD download done by hand) in a hidden new console and delivers Ctrl+C. Verify on a Windows machine: the world save file's timestamp updates before the process exits, and the server survives killing the prototype parent. Record findings (flags that worked, Valheim behaviour) in `docs/spikes/m1-process-model.md`.
- [ ] 1.4 Generate Dart code from `proto/yagura/v1` into `packages/yagura_proto` with `tool/gen_proto.dart` (protoc + protoc_plugin pinned). Verify: `dart analyze packages/yagura_proto` is clean and a round-trip test serialises an `Instance`.

## 2. [M1] yagura_js and the hook runner

Covers: plugin-hooks → Hook points; plugin-hooks → Hook input and output contract; plugin-hooks → Hook deadline; plugin-hooks → Hook memory cap; plugin-hooks → Hook errors are reported with location; plugin-hooks → Sandboxed host API; plugin-hooks → Hook host calls are bounded.

- [ ] 2.1 Write the failing tests for this group's test-map rows; verify each fails for the stated reason (missing API, not a compile error elsewhere).
- [ ] 2.2 Implement `yagura_js`: runtime/context lifecycle, `JS_SetMemoryLimit`, `JS_SetMaxStackSize`, interrupt handler with a monotonic deadline, eval, call-with-JSON, synchronous host functions with JSON arguments, exception + stack extraction. Verify: the deadline and memory rows go green.
- [ ] 2.3 Implement the hook runner (design D4): isolate per call, 4 worker slots (wait excluded from the deadline), watchdog of deadline + 2 s that releases the slot and requests an isolate kill, leaked-worker accounting with `hook_runtime_degraded` at 2, context and result schemas per hook, result and context size caps, the pure `yagura.*` host API (`log`, `fs.readText`, `fs.list` read-only and sandboxed by canonical path, `formats.<fmt>.parse/serialize` stubs wired to `yagura_formats` as formats land). Verify: every row of this group is green; flip them.
- [ ] 2.4 Document the hook contract and host API in `docs/plugins/hooks.md` with one example per hook point. Verify: the examples are executed by a test that loads them from the doc.

## 3. [M1] Plugin manifest v1

Covers: plugin-manifest → Plugin discovery and validation; plugin-manifest → Plugin size limits; plugin-manifest → Plugin reload without restart; plugin-manifest → Settings schema types and constraints; plugin-manifest → Launch templates; plugin-manifest → Port declarations; plugin-manifest → Stop and health declarations; plugin-manifest → Save data paths stay inside the instance; plugin-manifest → Executable is the long-running server.

- [ ] 3.1 Write the failing tests for this group's rows.
- [ ] 3.2 Write `schemas/plugin-manifest.v1.json` (identity, steam, executable, ports with derived ports, settings schema types incl. object/list/secret, launch template entries, stop, health, data_paths, hooks, logs, plus reserved sections for bindings, mods and rcon validated in their own groups). Verify: the schema validates the Valheim manifest and rejects each invalid fixture.
- [ ] 3.3 Implement `yagura_plugin`: loader with size limits, JSON Schema validation with line numbers, template parser/renderer (paths validated at load), settings validation with defaults and field paths, schema-version hash (design D5), data_paths containment check. Add `yagura plugin lint <dir>`. Verify: this group's rows are green; flip them.
- [ ] 3.4 Write `docs/plugins/manifest.md` (every field, with the Valheim manifest as the walkthrough). Verify: a test lints every manifest snippet in the doc.

## 4. [M1] Daemon core: data directory, state and operations

Covers: host-service → Data directory layout; host-service → Startup sequence; host-service → Single daemon per data directory; instance-lifecycle → Instance creation validates settings against the plugin schema; instance-lifecycle → Instance state machine; instance-lifecycle → One operation per instance at a time; instance-lifecycle → Operations report progress and can be cancelled; instance-lifecycle → Interrupted operations are reported after a daemon restart; instance-lifecycle → Durable state with a portable instance file; instance-lifecycle → Deleting an instance protects game data; instance-lifecycle → Error reasons have defined exits.

- [ ] 4.1 Write the failing tests for this group's rows (fakes for process host and Steam service).
- [ ] 4.2 Implement data directory layout, the OS exclusive lock (`LockFileEx`/`flock`), SQLite with numbered migrations and pre-migration backup, and the startup sequence with fatal and degraded steps (design D9). Verify: host rows green.
- [ ] 4.3 Implement the instance manager (create with serialised port and directory checks incl. the daemon API port and the default instance root `<data>/instances` (design D21; configured roots come with the local admin channel in M2), state machine guards and the error-reason exits of design D17 incl. `Acknowledge`, `instance.json` mirroring with secret placeholders, delete with confirmation and `pre_delete` snapshot hook point) and the operation runner (per-instance FIFO, 10 queued max, heavy slots per design D3, step events with sequence numbers and per-step progress coalescing, cancellation and stop-while-busy per design D18, startup recovery marking `interrupted` per design D9). Verify: this group's rows are green; flip them.

## 5. [M1] Process model: launch, relay, signal, re-attach

Covers: instance-lifecycle → Crash detection and restart policy; instance-lifecycle → Running servers survive daemon restarts; instance-lifecycle → Graceful stop per plugin strategy; instance-lifecycle → Autostart after daemon or host restart.

- [ ] 5.1 Write the failing tests for this group's rows; process tests run on the Windows CI runner against a small test server executable in `apps/yagurad/test/fixtures/fake_server/` that logs, handles Ctrl+C and can crash on command.
- [ ] 5.2 Implement the `ProcessHost` interface and its Windows implementation (design D2): `launch` with `CreateProcessW` (console mode) and the flags from ADR 0009, `relay` (pipes, rotating capture 10 MiB × 5, `relay.json`, `exit.json`, ignores console events), `signal` (AttachConsole + GenerateConsoleCtrlEvent), exit waiters, re-attach by PID + executable + start time. Verify: rows for re-attach and PID reuse green.
- [ ] 5.3 Implement stop strategies (`signal`, `kill`; `rcon` comes with RCON in M4), grace period and `stopped_by`, the restart policy with the crash-loop window on a monotonic clock, crash notices with the last 50 lines, and autostart (design D14). Verify: this group's rows are green; flip them.

## 6. [M1] Steam (anonymous), install, update and snapshots

Covers: instance-lifecycle → Updates stop and restart a running server; instance-lifecycle → Save data is declared and snapshotted; steam-content → SteamCMD is installed and managed by the daemon; steam-content → Login mode per plugin; steam-content → SteamCMD runs non-interactively; steam-content → Install, update and validate apps; steam-content → SteamCMD runs are bounded and cleaned up.

- [ ] 6.1 Write the failing tests for this group's rows using a fake SteamCMD (`apps/yagurad/test/fixtures/fake_steamcmd/`) that replays recorded output, honours `+quit`, and can stall or fail on command.
- [ ] 6.2 Implement the Steam service for anonymous logins: SteamCMD bootstrap per installation, argument-only invocation with stdin closed, kill-on-close job object, one run per installation with app runs keyed by instance directory (design D7), SteamCMD spawned suspended then assigned to the job, `waiting_for_steamcmd` reporting, `steam/patterns.yaml` classifier, progress parsing, 15 min no-progress and 12 h caps, stray SteamCMD sweep at startup, disk check. Verify: rows green.
- [ ] 6.3 Implement install, update (stop → snapshot → download → apply config → start-if-running) and validate operations, and snapshots per design D12 (last 3, space check on the snapshots volume, restore pinning, `pre_restore`, orphan listing, `skip_snapshot` recorded in the operation result). Verify: this group's rows are green; flip them.

## 7. [M1] Log hub

Covers: log-streaming → Declared log sources; log-streaming → Encoding-aware decoding; log-streaming → Stdout captured to a file; log-streaming → Bounded buffer and backlog; log-streaming → Live follow with backpressure.

- [ ] 7.1 Write the failing tests for this group's rows.
- [ ] 7.2 Implement log sources (stdout capture and file globs with `newest`/`fixed` rotation), polling tailers (design D6) with persisted offsets, decoding for utf-8, utf-16le and latin-1 with replacement characters, ring buffers (10,000 lines / 4 MiB), backlog with the 5,000 cap, follow with 1,000-line lag and `dropped` markers. Verify: this group's rows are green; flip them.

## 8. [M1] gRPC API and dev mode

Covers: daemon-protocol → API version negotiation; daemon-protocol → Structured errors; daemon-protocol → Long operations are asynchronous with resumable progress; daemon-protocol → Instance state and event stream; daemon-protocol → Plugin-shaped data as versioned JSON; daemon-protocol → Message size limits; daemon-security → Development mode is localhost only.

- [ ] 8.1 Write the failing tests for this group's rows against an in-process server and generated client.
- [ ] 8.2 Implement the gRPC server for the M1 services (`System`, `Plugins`, `Instances`, `Operations`, `Logs`), `ErrorDetail` mapping with reason codes from `docs/protocol.md`, incident ids for `INTERNAL`, message size limits, `WatchInstances` with snapshot, slim deltas and the 1,000-event / 8 MiB bound (design D15), `WatchOperation` resume by `after_sequence` with `events_dropped`, JSON documents with schema-version checks, and the `--dev` loopback-only plaintext listener with reflection. Verify: this group's rows are green; flip them.
- [ ] 8.3 Add a test that every reason code used in the daemon appears in `docs/protocol.md` and vice versa. Verify: it passes.

## 9. [M1] Valheim plugin, minimal desktop and M1 exit

Covers: desktop-client → Forms rendered from plugin schemas; desktop-client → Logs and console views; instance-lifecycle → Graceful stop per plugin strategy.

- [ ] 9.1 Write `plugins/valheim/plugin.yaml` (anonymous app 896660, `-savedir`/`-logFile` inside the instance, ports game/query with derived query, `signal` stop, log-match health, `data_paths`), with no `hooks.js`. Verify: `yagura plugin lint plugins/valheim` passes.
- [ ] 9.2 Write the failing widget tests for this group's rows.
- [ ] 9.3 Implement the desktop client skeleton (design D10): a dev-mode connection to one daemon, instance list from `WatchInstances`, schema-driven settings form (all v1 field types, read-only fallback), operation progress view, log view with backlog, follow, pause and dropped markers. Verify: this group's M1 rows are green; flip them.
- [ ] 9.4 Run every package's tests on Windows and Linux CI and `openspec validate --all --strict`. Verify: all pass and every row of this change's test map is green.
- [ ] 9.5 Write back into `openspec/architecture.md` the refinements this design owns: the error-reason exits from D17, the Resource Bounds rows marked *, and the startup fatal/degraded split from D9. Verify: the architecture state machine section lists the D17 exits and the bounds table lists the 8 MiB `WatchInstances` subscriber bound.
- [ ] 9.6 Run the M1 exit criteria from `openspec/roadmap.md` on a Windows machine and record the results (user-verified ones by the user) in `docs/milestones/m1.md`. Verify: every M1 criterion has a recorded pass.

## Workflow follow-up

- This change is M1 (Walking skeleton) only. The M2-M5 requirements, decisions and task groups are parked in `openspec/changes/platform-backlog/`, which is never applied; `specwright-roadmap next` takes each following milestone out of it as its own change after this one is archived.
- When a task adds a dependency to any workspace package, re-run the dependency skill discovery from 1.1 and update `.claude/skills/UPSTREAM.json`.
- Milestone exit criteria that are user-verified are run by the user, never marked passed on their behalf.
