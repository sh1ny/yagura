# Tasks

## Test map

Every scenario maps to a Dart test at the boundary it crosses: daemon behaviour against an in-process daemon with fake SteamCMD, fake process host and fake firewall where the real one is not needed; process, service and firewall rows against the real OS on Windows (and Linux for M5) CI runners (`integration_test/`, tagged `windows`/`linux`); desktop rows as Flutter widget tests against a fake daemon connection. The group column says which task group turns the row green; groups are tagged by milestone below.

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
| host-service → Data directory layout | Instance on another drive | apps/yagurad/test/host/data_directory_layout_test.dart | instance_on_another_drive | 4 (M1) | red |
| host-service → Single daemon per data directory | Second instance refused | apps/yagurad/test/host/single_daemon_per_data_directory_test.dart | second_instance_refused | 4 (M1) | red |
| host-service → Single daemon per data directory | Lock file left by a crashed daemon | apps/yagurad/test/host/single_daemon_per_data_directory_test.dart | lock_file_left_by_a_crashed_daemon | 4 (M1) | red |
| host-service → Startup sequence | Migration with backup | apps/yagurad/test/host/startup_sequence_test.dart | migration_with_backup | 4 (M1) | red |
| host-service → Startup sequence | Firewall unavailable at startup | apps/yagurad/test/host/startup_sequence_test.dart | firewall_unavailable_at_startup | 4 (M1) | red |
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
| daemon-security → Audit log | Instance deletion audited | apps/yagurad/test/security/audit_log_test.dart | instance_deletion_audited | 10 (M2) | red |
| daemon-security → Audit log | Scanner flood | apps/yagurad/test/security/audit_log_test.dart | scanner_flood | 10 (M2) | red |
| daemon-security → Audit log | Secret set without value in audit | apps/yagurad/test/security/audit_log_test.dart | secret_set_without_value_in_audit | 10 (M2) | red |
| daemon-security → Client pins the daemon CA | Fingerprint mismatch at pairing | apps/yagurad/test/security/client_pins_the_daemon_ca_test.dart | fingerprint_mismatch_at_pairing | 10 (M2) | red |
| daemon-security → Client pins the daemon CA | Daemon CA matches stored CA | apps/yagurad/test/security/client_pins_the_daemon_ca_test.dart | daemon_ca_matches_stored_ca | 10 (M2) | red |
| daemon-security → Daemon identity created on first start | First start | apps/yagurad/test/security/daemon_identity_created_on_first_start_test.dart | first_start | 10 (M2) | red |
| daemon-security → Daemon identity created on first start | Secret store unavailable | apps/yagurad/test/security/daemon_identity_created_on_first_start_test.dart | secret_store_unavailable | 10 (M2) | red |
| daemon-security → Device certificate renewal | Renewal before expiry | apps/yagurad/test/security/device_certificate_renewal_test.dart | renewal_before_expiry | 10 (M2) | red |
| daemon-security → Device certificate renewal | Revoking a renewed device | apps/yagurad/test/security/device_certificate_renewal_test.dart | revoking_a_renewed_device | 10 (M2) | red |
| daemon-security → Device certificate renewal | Renewal without a valid certificate | apps/yagurad/test/security/device_certificate_renewal_test.dart | renewal_without_a_valid_certificate | 10 (M2) | red |
| daemon-security → Device management | Revoke another device | apps/yagurad/test/security/device_management_test.dart | revoke_another_device | 10 (M2) | red |
| daemon-security → Device management | Revoking the last device | apps/yagurad/test/security/device_management_test.dart | revoking_the_last_device | 10 (M2) | red |
| daemon-security → Local admin channel is restricted to administrators | Administrator requests a pairing code | apps/yagurad/test/security/local_admin_channel_is_restricted_to_administrat_test.dart | administrator_requests_a_pairing_code | 10 (M2) | red |
| daemon-security → Local admin channel is restricted to administrators | Non-administrator | apps/yagurad/test/security/local_admin_channel_is_restricted_to_administrat_test.dart | non_administrator | 10 (M2) | red |
| daemon-security → Mutual TLS on every call | Call without a client certificate | apps/yagurad/test/security/mutual_tls_on_every_call_test.dart | call_without_a_client_certificate | 10 (M2) | red |
| daemon-security → Mutual TLS on every call | Revoked device | apps/yagurad/test/security/mutual_tls_on_every_call_test.dart | revoked_device | 10 (M2) | red |
| daemon-security → Pairing with a one-time code | Successful enrollment | apps/yagurad/test/security/pairing_with_a_one_time_code_test.dart | successful_enrollment | 10 (M2) | red |
| daemon-security → Pairing with a one-time code | Expired or reused code | apps/yagurad/test/security/pairing_with_a_one_time_code_test.dart | expired_or_reused_code | 10 (M2) | red |
| daemon-security → Pairing with a one-time code | Brute force from one address | apps/yagurad/test/security/pairing_with_a_one_time_code_test.dart | brute_force_from_one_address | 10 (M2) | red |
| daemon-security → Pairing with a one-time code | Distributed guessing | apps/yagurad/test/security/pairing_with_a_one_time_code_test.dart | distributed_guessing | 10 (M2) | red |
| daemon-security → Secrets never leave the daemon | No read path for secrets | apps/yagurad/test/security/secrets_never_leave_the_daemon_test.dart | no_read_path_for_secrets | 10 (M2) | red |
| daemon-security → Secrets never leave the daemon | Data directory scan | apps/yagurad/test/security/secrets_never_leave_the_daemon_test.dart | data_directory_scan | 10 (M2) | red |
| host-service → Data directory layout | Instance root added locally | apps/yagurad/test/host/data_directory_layout_test.dart | instance_root_added_locally | 10 (M2) | red |
| host-service → Game servers run under a low-privilege account | Server process identity | apps/yagurad/integration_test/windows/game_servers_run_under_a_low_privilege_account_test.dart | server_process_identity | 11 (M2) | red |
| host-service → Game servers run under a low-privilege account | Logon fails | apps/yagurad/integration_test/windows/game_servers_run_under_a_low_privilege_account_test.dart | logon_fails | 11 (M2) | red |
| host-service → Servers survive service stop and upgrade | Service restart | apps/yagurad/integration_test/windows/servers_survive_service_stop_and_upgrade_test.dart | service_restart | 11 (M2) | red |
| host-service → Servers survive service stop and upgrade | Server exits while the daemon is down | apps/yagurad/integration_test/windows/servers_survive_service_stop_and_upgrade_test.dart | server_exits_while_the_daemon_is_down | 11 (M2) | red |
| host-service → Windows service install and control | Install as a service | apps/yagurad/integration_test/windows/windows_service_install_and_control_test.dart | install_as_a_service | 11 (M2) | red |
| host-service → Windows service install and control | Not elevated | apps/yagurad/integration_test/windows/windows_service_install_and_control_test.dart | not_elevated | 11 (M2) | red |
| instance-lifecycle → Daemon file operations do not follow links planted in instance directories | Junction planted in a config folder | apps/yagurad/test/instances/daemon_file_operations_do_not_follow_links_plant_test.dart | junction_planted_in_a_config_folder | 11 (M2) | red |
| instance-lifecycle → Daemon file operations do not follow links planted in instance directories | Recorded mod link | apps/yagurad/test/instances/daemon_file_operations_do_not_follow_links_plant_test.dart | recorded_mod_link | 11 (M2) | red |
| instance-lifecycle → Daemon file operations do not follow links planted in instance directories | Delete never descends into a link | apps/yagurad/test/instances/daemon_file_operations_do_not_follow_links_plant_test.dart | delete_never_descends_into_a_link | 11 (M2) | red |
| instance-lifecycle → Only verified game server processes are terminated | Forged run file | apps/yagurad/test/instances/only_verified_game_server_processes_are_terminat_test.dart | forged_run_file | 11 (M2) | red |
| instance-lifecycle → Only verified game server processes are terminated | Genuine server | apps/yagurad/test/instances/only_verified_game_server_processes_are_terminat_test.dart | genuine_server | 11 (M2) | red |
| steam-content → Install, update and validate apps | Other instance's server blocked during an update | apps/yagurad/test/steam/install_update_and_validate_apps_test.dart | other_instance_s_server_blocked_during_an_update | 11 (M2) | red |
| firewall-rules → Daemon API port rule | Fresh host reachable after install | apps/yagurad/test/firewall/daemon_api_port_rule_test.dart | fresh_host_reachable_after_install | 12 (M2) | red |
| firewall-rules → Daemon API port rule | Firewall unavailable at service install | apps/yagurad/test/firewall/daemon_api_port_rule_test.dart | firewall_unavailable_at_service_install | 12 (M2) | red |
| firewall-rules → Daemon API port rule | Port changed | apps/yagurad/test/firewall/daemon_api_port_rule_test.dart | port_changed | 12 (M2) | red |
| firewall-rules → Only owned rules are changed | Admin's own rule untouched | apps/yagurad/test/firewall/only_owned_rules_are_changed_test.dart | admin_s_own_rule_untouched | 12 (M2) | red |
| firewall-rules → Only owned rules are changed | Foreign rule inside the group | apps/yagurad/test/firewall/only_owned_rules_are_changed_test.dart | foreign_rule_inside_the_group | 12 (M2) | red |
| firewall-rules → Owned rules derived from instance ports | Rules created after install | apps/yagurad/test/firewall/owned_rules_derived_from_instance_ports_test.dart | rules_created_after_install | 12 (M2) | red |
| firewall-rules → Owned rules derived from instance ports | Firewall service unavailable | apps/yagurad/test/firewall/owned_rules_derived_from_instance_ports_test.dart | firewall_service_unavailable | 12 (M2) | red |
| firewall-rules → RCON ports closed by default | Default RCON not exposed | apps/yagurad/test/firewall/rcon_ports_closed_by_default_test.dart | default_rcon_not_exposed | 12 (M2) | red |
| firewall-rules → RCON ports closed by default | Exposed RCON with the firewall unavailable | apps/yagurad/test/firewall/rcon_ports_closed_by_default_test.dart | exposed_rcon_with_the_firewall_unavailable | 12 (M2) | red |
| firewall-rules → RCON ports closed by default | Admin exposes RCON | apps/yagurad/test/firewall/rcon_ports_closed_by_default_test.dart | admin_exposes_rcon | 12 (M2) | red |
| firewall-rules → Reconcile desired and actual rules | Port change on a stopped instance | apps/yagurad/test/firewall/reconcile_desired_and_actual_rules_test.dart | port_change_on_a_stopped_instance | 12 (M2) | red |
| firewall-rules → Reconcile desired and actual rules | Port change on a running instance | apps/yagurad/test/firewall/reconcile_desired_and_actual_rules_test.dart | port_change_on_a_running_instance | 12 (M2) | red |
| firewall-rules → Reconcile desired and actual rules | Rule deleted by hand | apps/yagurad/test/firewall/reconcile_desired_and_actual_rules_test.dart | rule_deleted_by_hand | 12 (M2) | red |
| desktop-client → Device certificate renewal by the client | Renewal on connect | apps/yagura_desktop/test/device_certificate_renewal_by_the_client_test.dart | renewal_on_connect | 13 (M2) | red |
| desktop-client → Device certificate renewal by the client | Certificate already expired | apps/yagura_desktop/test/device_certificate_renewal_by_the_client_test.dart | certificate_already_expired | 13 (M2) | red |
| desktop-client → Forms rendered from plugin schemas | Someone else saved first | apps/yagura_desktop/test/forms_rendered_from_plugin_schemas_test.dart | someone_else_saved_first | 13 (M2) | red |
| desktop-client → Multiple paired daemons | Two daemons online | apps/yagura_desktop/test/multiple_paired_daemons_test.dart | two_daemons_online | 13 (M2) | red |
| desktop-client → Multiple paired daemons | Daemon offline | apps/yagura_desktop/test/multiple_paired_daemons_test.dart | daemon_offline | 13 (M2) | red |
| desktop-client → Multiple paired daemons | Device revoked | apps/yagura_desktop/test/multiple_paired_daemons_test.dart | device_revoked | 13 (M2) | red |
| desktop-client → Pairing from the client | Pair a new daemon | apps/yagura_desktop/test/pairing_from_the_client_test.dart | pair_a_new_daemon | 13 (M2) | red |
| desktop-client → Pairing from the client | Malformed pairing string | apps/yagura_desktop/test/pairing_from_the_client_test.dart | malformed_pairing_string | 13 (M2) | red |
| instance-lifecycle → Concurrent edits are detected by revision | Two clients edit the same instance | apps/yagurad/test/instances/concurrent_edits_are_detected_by_revision_test.dart | two_clients_edit_the_same_instance | 13 (M2) | red |
| instance-lifecycle → Concurrent edits are detected by revision | Runtime state does not change the revision | apps/yagurad/test/instances/concurrent_edits_are_detected_by_revision_test.dart | runtime_state_does_not_change_the_revision | 13 (M2) | red |
| instance-lifecycle → Concurrent edits are detected by revision | Autostart unchanged when omitted | apps/yagurad/test/instances/concurrent_edits_are_detected_by_revision_test.dart | autostart_unchanged_when_omitted | 13 (M2) | red |
| instance-lifecycle → Concurrent edits are detected by revision | Current revision accepted | apps/yagurad/test/instances/concurrent_edits_are_detected_by_revision_test.dart | current_revision_accepted | 13 (M2) | red |
| desktop-client → Operations and interactive prompts | Steam Guard prompt | apps/yagura_desktop/test/operations_and_interactive_prompts_test.dart | steam_guard_prompt | 14 (M3) | red |
| desktop-client → Operations and interactive prompts | Prompt answered elsewhere | apps/yagura_desktop/test/operations_and_interactive_prompts_test.dart | prompt_answered_elsewhere | 14 (M3) | red |
| steam-content → Adding a Steam account with Steam Guard | Email code relayed | apps/yagurad/test/steam/adding_a_steam_account_with_steam_guard_test.dart | email_code_relayed | 14 (M3) | red |
| steam-content → Adding a Steam account with Steam Guard | Wrong code | apps/yagurad/test/steam/adding_a_steam_account_with_steam_guard_test.dart | wrong_code | 14 (M3) | red |
| steam-content → Adding a Steam account with Steam Guard | No code submitted in time | apps/yagurad/test/steam/adding_a_steam_account_with_steam_guard_test.dart | no_code_submitted_in_time | 14 (M3) | red |
| steam-content → Credential retention is the admin's choice | Password not remembered and cache valid | apps/yagurad/test/steam/credential_retention_is_the_admin_s_choice_test.dart | password_not_remembered_and_cache_valid | 14 (M3) | red |
| steam-content → Credential retention is the admin's choice | Cached login expired | apps/yagurad/test/steam/credential_retention_is_the_admin_s_choice_test.dart | cached_login_expired | 14 (M3) | red |
| steam-content → Game Server Login Tokens | Token injected at launch | apps/yagurad/test/steam/game_server_login_tokens_test.dart | token_injected_at_launch | 14 (M3) | red |
| steam-content → Game Server Login Tokens | Required token missing | apps/yagurad/test/steam/game_server_login_tokens_test.dart | required_token_missing | 14 (M3) | red |
| steam-content → Login mode per plugin | Account required but none linked | apps/yagurad/test/steam/login_mode_per_plugin_test.dart | account_required_but_none_linked | 14 (M3) | red |
| steam-content → Steam passwords never reach disk or logs | Password absent from output | apps/yagurad/test/steam/steam_passwords_never_reach_disk_or_logs_test.dart | password_absent_from_output | 14 (M3) | red |
| steam-content → Steam passwords never reach disk or logs | Remember password | apps/yagurad/test/steam/steam_passwords_never_reach_disk_or_logs_test.dart | remember_password | 14 (M3) | red |
| steam-content → Workshop downloads | Workshop item downloaded | apps/yagurad/test/steam/workshop_downloads_test.dart | workshop_item_downloaded | 14 (M3) | red |
| steam-content → Workshop downloads | Item removed from the workshop | apps/yagurad/test/steam/workshop_downloads_test.dart | item_removed_from_the_workshop | 14 (M3) | red |
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

## 1. [M1] Workspace and first spikes

- [ ] 1.1 Create the pub workspace from design D1: `apps/yagurad`, `apps/yagura_desktop`, `packages/{yagura_proto,yagura_js,yagura_formats,yagura_plugin}`, `proto/`, `schemas/`, `plugins/`, `tool/`; `analysis_options.yaml` with strict casts and inference; a Windows + Linux CI workflow running `dart analyze` and `dart test` for every package. Verify: CI is green on an empty test per package.
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
- [ ] 4.3 Implement the instance manager (create with serialised port and directory checks incl. the daemon API port and instance roots (design D21), state machine guards and the error-reason exits of design D17 incl. `Acknowledge`, `instance.json` mirroring with secret placeholders, delete with confirmation and `pre_delete` snapshot hook point) and the operation runner (per-instance FIFO, 10 queued max, heavy slots per design D3, step events with sequence numbers and per-step progress coalescing, cancellation and stop-while-busy per design D18, startup recovery marking `interrupted` per design D9). Verify: this group's rows are green; flip them.

## 5. [M1] Process model: launch, relay, signal, re-attach

Covers: instance-lifecycle → Crash detection and restart policy; instance-lifecycle → Running servers survive daemon restarts; instance-lifecycle → Graceful stop per plugin strategy; instance-lifecycle → Autostart after daemon or host restart.

- [ ] 5.1 Write the failing tests for this group's rows; process tests run on the Windows CI runner against a small test server executable in `apps/yagurad/test/fixtures/fake_server/` that logs, handles Ctrl+C and can crash on command.
- [ ] 5.2 Implement the `ProcessHost` interface and its Windows implementation (design D2): `launch` with `CreateProcessW` (console mode) and the flags from ADR 0009, `relay` (pipes, rotating capture 10 MiB × 5, `relay.json`, `exit.json`, ignores console events), `signal` (AttachConsole + GenerateConsoleCtrlEvent), exit waiters, re-attach by PID + executable + start time. Verify: rows for re-attach and PID reuse green.
- [ ] 5.3 Implement stop strategies (`signal`, `kill`; `rcon` wired in group 18), grace period and `stopped_by`, the restart policy with the crash-loop window on a monotonic clock, crash notices with the last 50 lines, and autostart (design D14). Verify: this group's rows are green; flip them.

## 6. [M1] Steam (anonymous), install, update and snapshots

Covers: instance-lifecycle → Updates stop and restart a running server; instance-lifecycle → Save data is declared and snapshotted; steam-content → SteamCMD is installed and managed by the daemon; steam-content → Login mode per plugin; steam-content → SteamCMD runs non-interactively; steam-content → Install, update and validate apps; steam-content → SteamCMD runs are bounded and cleaned up.

- [ ] 6.1 Write the failing tests for this group's rows using a fake SteamCMD (`apps/yagurad/test/fixtures/fake_steamcmd/`) that replays recorded output, honours `+quit`, and can stall or fail on command.
- [ ] 6.2 Implement the Steam service for anonymous logins: SteamCMD bootstrap per installation, argument-only invocation with stdin closed, kill-on-close job object, one run per installation with app runs keyed by instance directory (design D7), SteamCMD spawned suspended then assigned to the job, `waiting_for_steamcmd` reporting, `steam/patterns.yaml` classifier, progress parsing, 15 min no-progress and 12 h caps, stray SteamCMD sweep at startup, disk check. Verify: rows green.
- [ ] 6.3 Implement install, update (stop → snapshot → download → apply config → start-if-running) and validate operations, and snapshots per design D12 (last 3, space check on the snapshots volume, restore pinning, `pre_restore`, orphan listing, audited `skip_snapshot`). Verify: this group's rows are green; flip them.

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
- [ ] 9.4 Run the M1 exit criteria from `openspec/roadmap.md` on a Windows machine and record the results (user-verified ones by the user) in `docs/milestones/m1.md`. Verify: every M1 criterion has a recorded pass.

## 10. [M2] PKI, pairing and mTLS

Covers: daemon-security → Daemon identity created on first start; daemon-security → Pairing with a one-time code; daemon-security → Client pins the daemon CA; daemon-security → Mutual TLS on every call; daemon-security → Device certificate renewal; daemon-security → Device management; daemon-security → Audit log; daemon-security → Secrets never leave the daemon; daemon-security → Local admin channel is restricted to administrators; host-service → Data directory layout.

- [ ] 10.1 Spike: issue a CA, a server certificate (SAN `yagurad-<id>`) and a client certificate from a CSR with the `x509` package; connect a `package:grpc` client with the CA as sole root and authority override; confirm that with `requestClientCertificate: true` an unknown client certificate fails the handshake. Record in `docs/spikes/m2-tls.md`; if request mode accepts unknown certificates, switch to the separate pairing listener described in `docs/protocol.md` before continuing.
- [ ] 10.2 Write the failing tests for this group's rows.
- [ ] 10.3 Implement the secret store (DPAPI user scope via FFI, Linux file store stub), daemon identity creation and server-certificate rotation, pairing codes (hash stored, 10 min, single use, per-address and global throttles per design D20), `Pairing` service (Info, Enroll, RenewCertificate, devices with certificate rows), the fail-closed auth interceptor keyed by certificate SHA-256 with a test per method, stream closing on revocation, the audit log of state-changing calls and the separate aggregated auth-failure table, daily server-certificate rotation check, and the local admin channel (named pipe with SYSTEM/Administrators ACL) with `yagurad pair|devices|status`. Verify: this group's rows are green; flip them.

## 11. [M2] Windows service and game-server account

Covers: host-service → Windows service install and control; host-service → Game servers run under a low-privilege account; host-service → Servers survive service stop and upgrade; instance-lifecycle → Daemon file operations do not follow links planted in instance directories; instance-lifecycle → Only verified game server processes are terminated; steam-content → Install, update and validate apps.

- [ ] 11.1 Write the failing integration tests for this group's rows (Windows runner, elevated).
- [ ] 11.2 Package WinSW 2.x with `tool/winsw/yagurad.xml`; implement `service install|uninstall|status` (elevation check, account `yagura-srv` with batch-logon right and random password in the secret store, directory ACLs from ADR 0013, daemon port firewall rule), the launcher's `LogonUserW` + `LoadUserProfileW` + `CreateProcessAsUserW` path on the `YaguraSrv\Default` window station, the `InstanceFs` component (design D13) used by every daemon file operation in instance directories, parent/token-user verification before any terminate with the verified-relay fallback, and ACL withdrawal around SteamCMD runs (design D13). Verify: rows green; flip them.
- [ ] 11.3 Spike/verify on a Windows host that the relay console starts as `yagura-srv` from the service, that `yagurad signal` running as LocalSystem delivers Ctrl+C to it so Valheim saves, and that `sc stop yagurad`, a restart and an in-place upgrade leave a running Valheim server's PID unchanged (M2 exit criteria); if WinSW stops it, implement the native service entry point fallback from ADR 0012 and repeat. Record in `docs/milestones/m2.md`.
- [ ] 11.4 Write `docs/adr/0014-acl-withdrawal-during-steamcmd-runs.md` (`Status: proposed`, `Supersedes: 0010` for its race reasoning only: other instances' servers share `yagura-srv`, so the instance ACL is withdrawn for the whole SteamCMD run per design D13), get it reviewed as a baseline round in `openspec/architecture-review.md` per the `specwright-roadmap` close rule, then accept it and update the in-force index. Verify: the index lists 0014 superseding 0010 and the review shows a passing verdict.

## 12. [M2] Firewall reconciler

Covers: firewall-rules → Owned rules derived from instance ports; firewall-rules → Only owned rules are changed; firewall-rules → Reconcile desired and actual rules; firewall-rules → RCON ports closed by default; firewall-rules → Daemon API port rule.

- [ ] 12.1 Write the failing tests for this group's rows against a fake NetSecurity runner, plus one Windows integration test against the real firewall.
- [ ] 12.2 Implement the reconciler: desired rules per design D16 (installed instances; launched ports while running, saved ports otherwise) plus the daemon port, one batched PowerShell script per reconcile with a 30 s timeout, owned-name parsing, `unmanaged` reporting, rule recreation, `firewall: degraded` on failure, RCON ports closed unless exposed. Verify: this group's rows are green; flip them.

## 13. [M2] Remote desktop: pairing, multi-daemon, revisions

Covers: desktop-client → Multiple paired daemons; desktop-client → Pairing from the client; desktop-client → Forms rendered from plugin schemas; desktop-client → Device certificate renewal by the client; instance-lifecycle → Concurrent edits are detected by revision.

- [ ] 13.1 Write the failing tests for this group's rows.
- [ ] 13.2 Implement instance revisions in the daemon (`expected_revision` on every mutating call, `revision_conflict`) and in the client (reload keeping edits). Verify: rows green.
- [ ] 13.3 Implement client pairing from a pairing string (keychain key, CSR, `Pairing.Info` pin check, authority override), the daemon list with connection states and backoff, renewal under 30 days on connect and daily, and `revoked`/`expired` handling. Verify: this group's rows are green; flip them.
- [ ] 13.4 Run the M2 exit criteria and record them in `docs/milestones/m2.md`. Verify: every M2 criterion has a recorded pass.

## 14. [M3] Steam accounts and Steam Guard

Covers: desktop-client → Operations and interactive prompts; steam-content → Login mode per plugin; steam-content → Adding a Steam account with Steam Guard; steam-content → Credential retention is the admin's choice; steam-content → Game Server Login Tokens; steam-content → Workshop downloads; steam-content → Steam passwords never reach disk or logs.

- [ ] 14.1 Spike: with a test Steam account, record SteamCMD's output and behaviour with stdin closed for email code, authenticator code and mobile approval; add the patterns to `steam/patterns.yaml` and the transcripts to the fake SteamCMD fixtures. Record in `docs/spikes/m3-steam-guard.md` and set the login timeouts from it.
- [ ] 14.2 Write the failing tests for this group's rows.
- [ ] 14.3 Implement accounts (one SteamCMD installation each), `AddAccount`/`ReauthAccount` operations with `WAITING_FOR_INPUT` prompts and `RespondToPrompt`, password scrubbing, `remember_password`, `steam_reauth_required`, GSLT secrets injected by template, workshop downloads and metadata (design D8). Wire the client's Steam Guard dialog. Verify: this group's rows are green; flip them.

## 15. [M3] Formats and config bindings

Covers: config-bindings → Bindings map settings to file keys; config-bindings → Supported formats; config-bindings → Round-trip preservation; config-bindings → Manual edits are detected, not overwritten blindly; config-bindings → Writes are atomic.

- [ ] 15.1 Collect real-file corpora for `ini`, `json`, `dayz-cfg` and `kv` under `packages/yagura_formats/test/corpus/` (DayZ `serverDZ.cfg`, `cfggameplay.json`, BattlEye cfg, generic INI).
- [ ] 15.2 Write the failing tests for this group's rows, plus a byte-identical round-trip test over every corpus file.
- [ ] 15.3 Implement the four parsers with lossless trees, then the binder: bindings in the manifest schema, `create`/`template`, apply before `onPreStart`, hook file edits applied after bindings, hash tracking, `external_edit` events, `game_writes`, atomic replace with the 5 s lock retry. Verify: this group's rows are green; flip them.

## 16. [M3] Mod pipeline and content store

Covers: mod-management → Plugins declare mod support and strategy; mod-management → Shared, versioned, immutable content store; mod-management → Staging by link with copy fallback; mod-management → Key files and post-processing; mod-management → Load order and roles; mod-management → Mod changes require a stopped instance to apply; mod-management → Mod update detection and update.

- [ ] 16.1 Write the failing tests for this group's rows.
- [ ] 16.2 Implement the versioned content store (`.staging` + atomic rename, single-flight per item version with waiter detach, GC of versions unreferenced 7 days, `.staging` cleanup at startup), instance-mod rows with pinned versions and fixed staged names, junction creation through FFI with copy fallback, `staged_version`/`desired_version` with both counted by GC, key-file ownership per design D19 (`key_conflict`), roles and load order, the update check timer (6 h, jittered, backoff) and `Mods` service. Verify: this group's rows are green; flip them.

## 17. [M3] DayZ plugin, plugin migrations and M3 exit

Covers: log-streaming → Secrets masked in log streams; plugin-hooks → Hook points; plugin-manifest → Plugin version changes re-validate instances.

- [ ] 17.1 Write the failing tests for this group's rows.
- [ ] 17.2 Implement plugin version change handling (`migrateSettings`, `settings_invalid`, `plugin_missing`) and secret masking in log streams. Verify: rows green; flip them.
- [ ] 17.3 Write `plugins/dayz/` (account login, workshop app 221100, Yagura-owned `yagura/serverDZ.cfg` and BattlEye cfg templates with `RConPort`/`RConPassword`, client/server mod roles, bikey rules, `data_paths`, log sources, `rcon` stop). Verify on a Windows host with BattlEye: 10+ workshop mods install, link, load and survive a mod update (M3 exit criterion); record in `docs/milestones/m3.md`.

## 18. [M4] RCON

Covers: instance-lifecycle → Graceful stop per plugin strategy; rcon → Plugin-declared RCON protocol; rcon → One-shot commands; rcon → Shared session and console stream; rcon → Protocol keep-alives.

- [ ] 18.1 Write the failing tests for this group's rows against fake BattlEye (UDP), Source RCON (TCP) and WebRCON (WebSocket) servers in `apps/yagurad/test/fixtures/`.
- [ ] 18.2 Implement the three adapters with keep-alives, the shared session per instance, `Execute`, the `Console` stream with command echo and 8 subscribers, reconnect backoff, auth-failure stop, and the `rcon` stop strategy. Add the console view to the client. Verify: this group's rows are green; flip them.

## 19. [M4] Complex configs, more games, import/export and M4 exit

Covers: config-bindings → Supported formats; config-bindings → Manual edits are detected, not overwritten blindly; desktop-client → Forms rendered from plugin schemas; instance-lifecycle → Import and export instances.

- [ ] 19.1 Add `ue-ini`, `xml` and `vdf` parsers with corpora (ARK:SA `GameUserSettings.ini`/`Game.ini`); write the failing tests for this group's rows.
- [ ] 19.2 Implement `list` bindings with `repeat` mode, import/export, and the client's table editor for `list` settings. Verify: rows green; flip them.
- [ ] 19.3 Write `plugins/ark_sa/` (anonymous 2430930, `-mods=` server-managed, Source RCON, `game_writes: true` bindings), `plugins/scum/` (UTF-16LE logs, signal stop verified on Windows), `plugins/rust/` (WebRCON). Verify each with `yagura plugin lint` and a manual run recorded in `docs/milestones/m4.md`.

## 20. [M5] Linux agent

Covers: host-service → Linux service.

- [ ] 20.1 Write the failing integration tests for this group's rows (Linux runner).
- [ ] 20.2 Implement the POSIX `ProcessHost` (posix_spawn + setsid, servers in transient systemd scopes, SIGTERM for `signal`), the systemd unit install, the Linux secret store, a firewalld/ufw adapter behind the firewall interface, and Linux executables in the reference plugins. Verify: this group's rows are green; flip them, and record the M5 run in `docs/milestones/m5.md`.

## 21. [M1-M5] Integration

- [ ] 21.1 Run every package's tests on Windows and Linux CI and `openspec validate --all --strict`. Verify: all pass and every test-map row is green.
- [ ] 21.2 Run the secret scan over a full install-start-update-stop workflow (data, instance and snapshot directories, logs). Verify: no secret value found outside the accepted exceptions.
- [ ] 21.3 Write back into `openspec/architecture.md` the refinements this design owns (error-reason exits from D17, the Resource Bounds rows marked *, the InstanceFs component, startup fatal/degraded split). Verify: `grep -n InstanceFs openspec/architecture.md` shows the component row and the bounds table lists the 8 MiB subscriber bound.

## Workflow follow-up

- At each milestone close, move the remaining task groups into the next milestone's change as described in `openspec/roadmap.md`, then archive `init-core-platform` with the groups already done.
- Milestone exit criteria that are user-verified are run by the user, never marked passed on their behalf.
