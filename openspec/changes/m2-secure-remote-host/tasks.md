# Tasks

## Test map

Every scenario maps to a Dart test at the boundary it crosses: daemon behaviour against an in-process daemon (fake SteamCMD, fake process host, fake firewall and fake data-directory protector where the real one is not needed), Windows behaviour against the real OS (tagged `windows`, run on Windows CI), and desktop rows as Flutter widget tests against fake daemon connections. Rows that need administrator rights, the installed service, local accounts or the real firewall are tagged `elevated`. They never run on the developer's desktop (they create accounts, profiles, a service and firewall rules): they run only in the manual `elevated` workflow (`.github/workflows/elevated.yml`, on a GitHub Windows runner, which runs as administrator; started by hand with `workflow_dispatch` once it is on `main`, or by pushing an `elevated/<name>` branch until then), started by hand when a group's `elevated` rows are verified, with the run link and results recorded in `docs/milestones/m2.md`. Rows that need the real Valheim server are also tagged `valheim`. Rows marked `(M1)` ride along unchanged inside a MODIFIED requirement and already pass; their group re-runs them. The group column says which task group turns the row green.

| Requirement | Scenario | Test file | Test name | Group | State |
|---|---|---|---|---|---|
| daemon-security → Daemon identity created on first start | First start | apps/yagurad/test/security/daemon_identity_created_on_first_start_test.dart | first_start | 6 | red |
| daemon-security → Daemon identity created on first start | Server certificate rotated | apps/yagurad/test/security/daemon_identity_created_on_first_start_test.dart | server_certificate_rotated | 6 | red |
| daemon-security → Daemon identity created on first start | Secret store unavailable | apps/yagurad/test/security/daemon_identity_created_on_first_start_test.dart | secret_store_unavailable | 6 | red |
| daemon-security → Pairing with a one-time code | Successful enrollment | apps/yagurad/test/security/pairing_with_a_one_time_code_test.dart | successful_enrollment | 6 | red |
| daemon-security → Pairing with a one-time code | Expired or reused code | apps/yagurad/test/security/pairing_with_a_one_time_code_test.dart | expired_or_reused_code | 6 | red |
| daemon-security → Pairing with a one-time code | Brute force from one address | apps/yagurad/test/security/pairing_with_a_one_time_code_test.dart | brute_force_from_one_address | 6 | red |
| daemon-security → Pairing with a one-time code | Distributed guessing | apps/yagurad/test/security/pairing_with_a_one_time_code_test.dart | distributed_guessing | 6 | red |
| daemon-security → Client pins the daemon CA | Fingerprint mismatch at pairing | apps/yagura_desktop/test/client_pins_the_daemon_ca_test.dart | fingerprint_mismatch_at_pairing | 11 | red |
| daemon-security → Client pins the daemon CA | Daemon CA matches stored CA | apps/yagura_desktop/test/client_pins_the_daemon_ca_test.dart | daemon_ca_matches_stored_ca | 11 | red |
| daemon-security → Mutual TLS on every call | Call without a client certificate | apps/yagurad/test/security/mutual_tls_on_every_call_test.dart | call_without_a_client_certificate | 6 | red |
| daemon-security → Mutual TLS on every call | Revoked device | apps/yagurad/test/security/mutual_tls_on_every_call_test.dart | revoked_device | 6 | red |
| daemon-security → Mutual TLS on every call | Method added without an exemption | apps/yagurad/test/security/mutual_tls_on_every_call_test.dart | method_added_without_an_exemption | 6 | red |
| daemon-security → Mutual TLS on every call | Certificate from another CA | apps/yagurad/test/security/mutual_tls_on_every_call_test.dart | certificate_from_another_ca | 6 | red |
| daemon-security → Device certificate renewal | Renewal before expiry | apps/yagurad/test/security/device_certificate_renewal_test.dart | renewal_before_expiry | 6 | red |
| daemon-security → Device certificate renewal | Revoking a renewed device | apps/yagurad/test/security/device_certificate_renewal_test.dart | revoking_a_renewed_device | 6 | red |
| daemon-security → Device certificate renewal | Renewal without a valid certificate | apps/yagurad/test/security/device_certificate_renewal_test.dart | renewal_without_a_valid_certificate | 6 | red |
| daemon-security → Device management | Revoke another device | apps/yagurad/test/security/device_management_test.dart | revoke_another_device | 6 | red |
| daemon-security → Device management | Revoking the last device | apps/yagurad/test/security/device_management_test.dart | revoking_the_last_device | 6 | red |
| daemon-security → Device management | Last device revoked on the host | apps/yagurad/integration_test/admin/device_management_on_the_host_test.dart (`windows`) | last_device_revoked_on_the_host | 7 | red |
| daemon-security → Audit log | Instance deletion audited | apps/yagurad/test/security/audit_log_test.dart | instance_deletion_audited | 6 | red |
| daemon-security → Audit log | Scanner flood | apps/yagurad/test/security/audit_log_test.dart | scanner_flood | 6 | red |
| daemon-security → Audit log | Secret set without value in audit | apps/yagurad/test/security/audit_log_test.dart | secret_set_without_value_in_audit | 6 | red |
| daemon-security → Secrets never leave the daemon | No read path for secrets | apps/yagurad/test/security/secrets_never_leave_the_daemon_test.dart | no_read_path_for_secrets | 3 | green |
| daemon-security → Secrets never leave the daemon | Data directory scan | apps/yagurad/integration_test/secrets_data_directory_scan_test.dart (`windows`) | data_directory_scan | 12 | red |
| daemon-security → Secrets never leave the daemon | Secret store fails on write | apps/yagurad/test/security/secrets_never_leave_the_daemon_test.dart | secret_store_fails_on_write | 3 | green |
| daemon-security → Local admin channel is restricted to administrators | Administrator requests a pairing code | apps/yagurad/integration_test/admin/local_admin_channel_test.dart (`elevated`) | administrator_requests_a_pairing_code | 7 | red |
| daemon-security → Local admin channel is restricted to administrators | Non-administrator | apps/yagurad/integration_test/admin/local_admin_channel_test.dart (`elevated`) | non_administrator | 7 | red |
| daemon-security → Local admin channel is restricted to administrators | Channel served by another process | apps/yagurad/integration_test/admin/local_admin_channel_test.dart (`windows`) | channel_served_by_another_process | 7 | red |
| daemon-security → Local admin channel is restricted to administrators | Daemon not running | apps/yagurad/integration_test/admin/local_admin_channel_test.dart (`windows`) | daemon_not_running | 7 | red |
| daemon-security → Development mode is localhost only | Dev mode on loopback | apps/yagurad/test/security/development_mode_is_localhost_only_test.dart | dev_mode_on_loopback | 6 (M1) | green |
| daemon-security → Development mode is localhost only | Dev mode on a public address | apps/yagurad/test/security/development_mode_is_localhost_only_test.dart | dev_mode_on_a_public_address | 6 (M1) | green |
| daemon-security → Development mode is localhost only | Dev mode default bind | apps/yagurad/test/security/development_mode_is_localhost_only_test.dart | dev_mode_default_bind | 6 (M1) | green |
| daemon-security → Development mode is localhost only | Started without dev mode | apps/yagurad/test/security/development_mode_is_localhost_only_test.dart | started_without_dev_mode | 6 | red |
| daemon-security → Development mode is localhost only | Started from a console without dev mode | apps/yagurad/test/security/development_mode_is_localhost_only_test.dart | started_from_a_console_without_dev_mode | 6 | red |
| desktop-client → Multiple paired daemons | Two daemons online | apps/yagura_desktop/test/multiple_paired_daemons_test.dart | two_daemons_online | 11 | red |
| desktop-client → Multiple paired daemons | Daemon restarted | apps/yagura_desktop/test/multiple_paired_daemons_test.dart | daemon_restarted | 11 | red |
| desktop-client → Multiple paired daemons | Daemon offline | apps/yagura_desktop/test/multiple_paired_daemons_test.dart | daemon_offline | 11 | red |
| desktop-client → Multiple paired daemons | Device revoked | apps/yagura_desktop/test/multiple_paired_daemons_test.dart | device_revoked | 11 | red |
| desktop-client → Multiple paired daemons | No shared API version | apps/yagura_desktop/test/multiple_paired_daemons_test.dart | no_shared_api_version | 11 | red |
| desktop-client → Pairing from the client | Pair a new daemon | apps/yagura_desktop/test/pairing_from_the_client_test.dart | pair_a_new_daemon | 11 | red |
| desktop-client → Pairing from the client | Malformed pairing string | apps/yagura_desktop/test/pairing_from_the_client_test.dart | malformed_pairing_string | 11 | red |
| desktop-client → Pairing from the client | Pairing code rejected | apps/yagura_desktop/test/pairing_from_the_client_test.dart | pairing_code_rejected | 11 | red |
| desktop-client → Device certificate renewal by the client | Renewal on connect | apps/yagura_desktop/test/device_certificate_renewal_by_the_client_test.dart | renewal_on_connect | 11 | red |
| desktop-client → Device certificate renewal by the client | Certificate already expired | apps/yagura_desktop/test/device_certificate_renewal_by_the_client_test.dart | certificate_already_expired | 11 | red |
| desktop-client → Forms rendered from plugin schemas | Daemon rejects a value | apps/yagura_desktop/test/forms_rendered_from_plugin_schemas_test.dart | daemon_rejects_a_value | 11 (M1) | green |
| desktop-client → Forms rendered from plugin schemas | Unknown field type | apps/yagura_desktop/test/forms_rendered_from_plugin_schemas_test.dart | unknown_field_type | 11 (M1) | green |
| desktop-client → Forms rendered from plugin schemas | Create an instance with a secret | apps/yagura_desktop/test/forms_rendered_from_plugin_schemas_test.dart | create_an_instance_with_a_secret | 11 | red |
| desktop-client → Forms rendered from plugin schemas | Someone else saved first | apps/yagura_desktop/test/forms_rendered_from_plugin_schemas_test.dart | someone_else_saved_first | 11 | red |
| firewall-rules → Owned rules derived from instance ports | Rules created after install | apps/yagurad/test/firewall/owned_rules_derived_from_instance_ports_test.dart | rules_created_after_install | 10 | red |
| firewall-rules → Owned rules derived from instance ports | Not installed has no rules | apps/yagurad/test/firewall/owned_rules_derived_from_instance_ports_test.dart | not_installed_has_no_rules | 10 | red |
| firewall-rules → Owned rules derived from instance ports | Firewall service unavailable | apps/yagurad/test/firewall/owned_rules_derived_from_instance_ports_test.dart | firewall_service_unavailable | 10 | red |
| firewall-rules → Only owned rules are changed | Admin's own rule untouched | apps/yagurad/integration_test/firewall/windows_firewall_test.dart (`elevated`) | admins_own_rule_untouched | 10 | red |
| firewall-rules → Only owned rules are changed | Foreign rule inside the group | apps/yagurad/integration_test/firewall/windows_firewall_test.dart (`elevated`) | foreign_rule_inside_the_group | 10 | red |
| firewall-rules → Reconcile desired and actual rules | Port change on a stopped instance | apps/yagurad/test/firewall/reconcile_desired_and_actual_rules_test.dart | port_change_on_a_stopped_instance | 10 | red |
| firewall-rules → Reconcile desired and actual rules | Port change on a running instance | apps/yagurad/test/firewall/reconcile_desired_and_actual_rules_test.dart | port_change_on_a_running_instance | 10 | red |
| firewall-rules → Reconcile desired and actual rules | Rule deleted by hand | apps/yagurad/integration_test/firewall/windows_firewall_test.dart (`elevated`) | rule_deleted_by_hand | 10 | red |
| firewall-rules → Reconcile desired and actual rules | Dev mode manages no rules | apps/yagurad/test/firewall/reconcile_desired_and_actual_rules_test.dart | dev_mode_manages_no_rules | 10 | red |
| firewall-rules → Reconcile desired and actual rules | Reconcile times out | apps/yagurad/test/firewall/reconcile_desired_and_actual_rules_test.dart | reconcile_times_out | 10 | red |
| firewall-rules → RCON ports closed by default | Default RCON not exposed | apps/yagurad/test/firewall/rcon_ports_closed_by_default_test.dart | default_rcon_not_exposed | 10 | red |
| firewall-rules → RCON ports closed by default | Admin exposes RCON | apps/yagurad/test/firewall/rcon_ports_closed_by_default_test.dart | admin_exposes_rcon | 10 | red |
| firewall-rules → RCON ports closed by default | Exposed RCON with the firewall unavailable | apps/yagurad/test/firewall/rcon_ports_closed_by_default_test.dart | exposed_rcon_with_the_firewall_unavailable | 10 | red |
| firewall-rules → Daemon API port rule | Fresh host reachable after install | apps/yagurad/integration_test/service/daemon_api_port_rule_test.dart (`elevated`) | fresh_host_reachable_after_install | 10 | red |
| firewall-rules → Daemon API port rule | Firewall unavailable at service install | apps/yagurad/integration_test/service/daemon_api_port_rule_test.dart (`elevated`) | firewall_unavailable_at_service_install | 10 | red |
| firewall-rules → Daemon API port rule | Port changed | apps/yagurad/integration_test/service/daemon_api_port_rule_test.dart (`elevated`) | port_changed | 10 | red |
| host-service → Windows service install and control | Install as a service | apps/yagurad/integration_test/service/windows_service_install_and_control_test.dart (`elevated`) | install_as_a_service | 8 | red |
| host-service → Windows service install and control | Not elevated | apps/yagurad/integration_test/service/windows_service_install_and_control_test.dart (`windows`) | not_elevated | 8 | red |
| host-service → Windows service install and control | Already installed | apps/yagurad/integration_test/service/windows_service_install_and_control_test.dart (`elevated`) | already_installed | 8 | red |
| host-service → Game servers run under a low-privilege account | Server process identity | apps/yagurad/integration_test/service/game_servers_run_under_a_low_privilege_account_test.dart (`elevated`) | server_process_identity | 9 | red |
| host-service → Game servers run under a low-privilege account | Instance created before the service | apps/yagurad/integration_test/service/game_servers_run_under_a_low_privilege_account_test.dart (`elevated`) | instance_created_before_the_service | 9 | red |
| host-service → Game servers run under a low-privilege account | Logon fails | apps/yagurad/integration_test/service/game_servers_run_under_a_low_privilege_account_test.dart (`elevated`) | logon_fails | 9 | red |
| host-service → Servers survive service stop and upgrade | Service restart | apps/yagurad/integration_test/service/servers_survive_service_stop_and_upgrade_test.dart (`elevated`) | service_restart | 8 | red |
| host-service → Servers survive service stop and upgrade | Service upgraded in place | apps/yagurad/integration_test/service/servers_survive_service_stop_and_upgrade_test.dart (`elevated`) | service_upgraded_in_place | 8 | red |
| host-service → Servers survive service stop and upgrade | Server exits while the daemon is down | apps/yagurad/integration_test/service/servers_survive_service_stop_and_upgrade_test.dart (`elevated`) | server_exits_while_the_daemon_is_down | 8 | red |
| host-service → Data directory layout | Default layout created | apps/yagurad/test/host/data_directory_layout_test.dart | default_layout_created | 7 (M1) | green |
| host-service → Data directory layout | Data directory not writable | apps/yagurad/test/host/data_directory_layout_test.dart | data_directory_not_writable | 7 (M1) | green |
| host-service → Data directory layout | Instance root added locally | apps/yagurad/integration_test/admin/instance_roots_test.dart (`windows`) | instance_root_added_locally | 7 | red |
| host-service → Data directory layout | Instance on another drive | apps/yagurad/integration_test/admin/instance_roots_test.dart (`windows`) | instance_on_another_drive | 7 | red |
| host-service → Data directory layout | Root writable by non-administrators | apps/yagurad/integration_test/admin/instance_roots_test.dart (`windows`) | root_writable_by_non_administrators | 7 | red |
| host-service → Data directory layout | Root still in use | apps/yagurad/integration_test/admin/instance_roots_test.dart (`windows`) | root_still_in_use | 7 | red |
| host-service → Startup sequence | Migration with backup | apps/yagurad/test/host/startup_sequence_test.dart | migration_with_backup | 2 (M1) | green |
| host-service → Startup sequence | Migration fails | apps/yagurad/test/host/startup_sequence_test.dart | migration_fails | 2 (M1) | green |
| host-service → Startup sequence | Data directory used by a dev daemon first | apps/yagurad/test/host/startup_sequence_test.dart | data_directory_used_by_a_dev_daemon_first | 2 | green |
| host-service → Startup sequence | Data directory created by an earlier daemon | apps/yagurad/integration_test/service/startup_sequence_service_test.dart (`elevated`) | data_directory_created_by_an_earlier_daemon | 9 | red |
| host-service → Startup sequence | Data directory is a link | apps/yagurad/integration_test/service/startup_sequence_service_test.dart (`elevated`) | data_directory_is_a_link | 9 | red |
| host-service → Startup sequence | Layout marker planted by a standard user | apps/yagurad/integration_test/service/startup_sequence_service_test.dart (`elevated`) | layout_marker_planted_by_a_standard_user | 9 | red |
| host-service → Startup sequence | Link in the data directory at first service start | apps/yagurad/integration_test/service/startup_sequence_service_test.dart (`elevated`) | link_in_the_data_directory_at_first_service_start | 9 | red |
| host-service → Startup sequence | Firewall unavailable at startup | apps/yagurad/test/host/startup_sequence_test.dart | firewall_unavailable_at_startup | 10 | red |
| instance-lifecycle → Concurrent edits are detected by revision | Two clients edit the same instance | apps/yagurad/test/instances/concurrent_edits_are_detected_by_revision_test.dart | two_clients_edit_the_same_instance | 4 | red |
| instance-lifecycle → Concurrent edits are detected by revision | Runtime state does not change the revision | apps/yagurad/test/instances/concurrent_edits_are_detected_by_revision_test.dart | runtime_state_does_not_change_the_revision | 4 | red |
| instance-lifecycle → Concurrent edits are detected by revision | Autostart unchanged when omitted | apps/yagurad/test/instances/concurrent_edits_are_detected_by_revision_test.dart | autostart_unchanged_when_omitted | 4 | red |
| instance-lifecycle → Concurrent edits are detected by revision | Current revision accepted | apps/yagurad/test/instances/concurrent_edits_are_detected_by_revision_test.dart | current_revision_accepted | 4 | red |
| instance-lifecycle → Concurrent edits are detected by revision | Restore from a stale view | apps/yagurad/test/instances/concurrent_edits_are_detected_by_revision_test.dart | restore_from_a_stale_view | 4 | red |
| instance-lifecycle → Concurrent edits are detected by revision | Revision missing | apps/yagurad/test/instances/concurrent_edits_are_detected_by_revision_test.dart | revision_missing | 4 | red |
| instance-lifecycle → Daemon file operations do not follow links planted in instance directories | Junction planted in a config folder | apps/yagurad/integration_test/files/daemon_file_operations_do_not_follow_links_test.dart (`windows`) | junction_planted_in_a_config_folder | 5 | red |
| instance-lifecycle → Daemon file operations do not follow links planted in instance directories | Instance directory replaced by a junction | apps/yagurad/integration_test/files/daemon_file_operations_do_not_follow_links_test.dart (`windows`) | instance_directory_replaced_by_a_junction | 5 | red |
| instance-lifecycle → Daemon file operations do not follow links planted in instance directories | Plain instance files | apps/yagurad/integration_test/files/daemon_file_operations_do_not_follow_links_test.dart (`windows`) | plain_instance_files | 5 | red |
| instance-lifecycle → Daemon file operations do not follow links planted in instance directories | Delete never descends into a link | apps/yagurad/integration_test/files/daemon_file_operations_do_not_follow_links_test.dart (`windows`) | delete_never_descends_into_a_link | 5 | red |
| instance-lifecycle → Only verified game server processes are terminated | Forged run file | apps/yagurad/integration_test/process/only_verified_game_server_processes_are_terminated_test.dart (`windows`) | forged_run_file | 9 | red |
| instance-lifecycle → Only verified game server processes are terminated | Forged run file and no verified server | apps/yagurad/integration_test/process/only_verified_game_server_processes_are_terminated_test.dart (`windows`) | forged_run_file_and_no_verified_server | 9 | red |
| instance-lifecycle → Only verified game server processes are terminated | Genuine server | apps/yagurad/integration_test/process/only_verified_game_server_processes_are_terminated_test.dart (`windows`) | genuine_server | 9 | red |
| instance-lifecycle → Graceful stop per plugin strategy | Valheim saves on a signal stop | apps/yagurad/test/instances/graceful_stop_per_plugin_strategy_test.dart (`valheim`) | valheim_saves_on_a_signal_stop | 9 (M1) | green |
| instance-lifecycle → Graceful stop per plugin strategy | Valheim saves on a signal stop from the service | apps/yagurad/integration_test/service/graceful_stop_from_the_service_test.dart (`elevated`, `valheim`) | valheim_saves_on_a_signal_stop_from_the_service | 9 | red |
| instance-lifecycle → Graceful stop per plugin strategy | Grace period exceeded | apps/yagurad/test/instances/graceful_stop_per_plugin_strategy_test.dart | grace_period_exceeded | 9 (M1) | green |
| instance-lifecycle → Instance creation validates settings against the plugin schema | Valid instance created | apps/yagurad/test/instances/instance_creation_validates_settings_against_the_test.dart | valid_instance_created | 7 (M1) | green |
| instance-lifecycle → Instance creation validates settings against the plugin schema | Game-server account access set | apps/yagurad/integration_test/service/game_servers_run_under_a_low_privilege_account_test.dart (`elevated`) | game_server_account_access_set | 9 | red |
| instance-lifecycle → Instance creation validates settings against the plugin schema | Setting violates the schema | apps/yagurad/test/instances/instance_creation_validates_settings_against_the_test.dart | setting_violates_the_schema | 7 (M1) | green |
| instance-lifecycle → Instance creation validates settings against the plugin schema | Directory outside the instance roots | apps/yagurad/test/instances/instance_creation_validates_settings_against_the_test.dart | directory_outside_the_instance_roots | 7 | red |
| instance-lifecycle → Instance creation validates settings against the plugin schema | Port equal to the daemon API port | apps/yagurad/test/instances/instance_creation_validates_settings_against_the_test.dart | port_equal_to_the_daemon_api_port | 7 (M1) | green |
| instance-lifecycle → Instance creation validates settings against the plugin schema | Port collision with another instance | apps/yagurad/test/instances/instance_creation_validates_settings_against_the_test.dart | port_collision_with_another_instance | 7 (M1) | green |
| instance-lifecycle → Save data is declared and snapshotted | Snapshot before update | apps/yagurad/test/instances/save_data_is_declared_and_snapshotted_test.dart | snapshot_before_update | 5 (M1) | green |
| instance-lifecycle → Save data is declared and snapshotted | Not enough space for a snapshot | apps/yagurad/test/instances/save_data_is_declared_and_snapshotted_test.dart | not_enough_space_for_a_snapshot | 5 (M1) | green |
| instance-lifecycle → Save data is declared and snapshotted | Restore a snapshot | apps/yagurad/test/instances/save_data_is_declared_and_snapshotted_test.dart | restore_a_snapshot | 5 (M1) | green |
| instance-lifecycle → Save data is declared and snapshotted | Restoring the oldest snapshot | apps/yagurad/test/instances/save_data_is_declared_and_snapshotted_test.dart | restoring_the_oldest_snapshot | 5 (M1) | green |
| instance-lifecycle → Save data is declared and snapshotted | Daemon killed during a restore | apps/yagurad/test/instances/save_data_is_declared_and_snapshotted_test.dart | daemon_killed_during_a_restore | 5 (M1) | green |
| instance-lifecycle → Save data is declared and snapshotted | Snapshot skipped on request | apps/yagurad/test/instances/save_data_is_declared_and_snapshotted_test.dart | snapshot_skipped_on_request | 6 | red |
| instance-lifecycle → Save data is declared and snapshotted | Pre-delete snapshot of a deleted instance | apps/yagurad/test/instances/save_data_is_declared_and_snapshotted_test.dart | pre_delete_snapshot_of_a_deleted_instance | 5 (M1) | green |
| instance-lifecycle → Deleting an instance protects game data | Delete with files snapshots first | apps/yagurad/test/instances/deleting_an_instance_protects_game_data_test.dart | delete_with_files_snapshots_first | 5 (M1) | green |
| instance-lifecycle → Deleting an instance protects game data | Delete an instance whose plugin is missing | apps/yagurad/test/instances/deleting_an_instance_protects_game_data_test.dart | delete_an_instance_whose_plugin_is_missing | 5 (M1) | green |
| instance-lifecycle → Deleting an instance protects game data | Delete keeping files | apps/yagurad/test/instances/deleting_an_instance_protects_game_data_test.dart | delete_keeping_files | 10 | red |
| instance-lifecycle → Deleting an instance protects game data | Delete with wrong confirmation | apps/yagurad/test/instances/deleting_an_instance_protects_game_data_test.dart | delete_with_wrong_confirmation | 5 (M1) | green |
| instance-lifecycle → Durable state with a portable instance file | Change persisted and mirrored | apps/yagurad/test/instances/durable_state_with_a_portable_instance_file_test.dart | change_persisted_and_mirrored | 5 (M1) | green |
| instance-lifecycle → Durable state with a portable instance file | instance.json write fails | apps/yagurad/test/instances/durable_state_with_a_portable_instance_file_test.dart | instance_json_write_fails | 5 (M1) | green |
| instance-lifecycle → Durable state with a portable instance file | Secrets excluded from instance.json | apps/yagurad/test/instances/durable_state_with_a_portable_instance_file_test.dart | secrets_excluded_from_instance_json | 3 | green |
| instance-lifecycle → Error reasons have defined exits | Acknowledge a crash loop | apps/yagurad/test/instances/error_reasons_have_defined_exits_test.dart | acknowledge_a_crash_loop | 9 (M1) | green |
| instance-lifecycle → Error reasons have defined exits | Start refused with invalid settings | apps/yagurad/test/instances/error_reasons_have_defined_exits_test.dart | start_refused_with_invalid_settings | 9 (M1) | green |
| instance-lifecycle → Error reasons have defined exits | Update clears an interrupted update | apps/yagurad/test/instances/error_reasons_have_defined_exits_test.dart | update_clears_an_interrupted_update | 9 (M1) | green |
| instance-lifecycle → Error reasons have defined exits | Acknowledge a rejected run record | apps/yagurad/test/instances/error_reasons_have_defined_exits_test.dart | acknowledge_a_rejected_run_record | 9 | red |
| instance-lifecycle → Error reasons have defined exits | Start refused after a rejected run record | apps/yagurad/test/instances/error_reasons_have_defined_exits_test.dart | start_refused_after_a_rejected_run_record | 9 | red |
| plugin-hooks → Hook input and output contract | Context contents | apps/yagurad/test/hooks/hook_input_and_output_contract_test.dart | context_contents | 3 | green |
| plugin-hooks → Hook input and output contract | Context with a secret set | apps/yagurad/test/hooks/hook_input_and_output_contract_test.dart | context_with_a_secret_set | 3 | green |
| plugin-hooks → Hook input and output contract | Invalid result shape | apps/yagurad/test/hooks/hook_input_and_output_contract_test.dart | invalid_result_shape | 3 (M1) | green |
| plugin-manifest → Secret settings are write-only | Secret values are write-only | apps/yagurad/test/instances/secret_settings_are_write_only_test.dart | secret_values_are_write_only | 3 | green |
| plugin-manifest → Secret settings are write-only | Settings saved with the secret placeholder | apps/yagurad/test/instances/secret_settings_are_write_only_test.dart | settings_saved_with_the_secret_placeholder | 3 | green |
| plugin-manifest → Secret settings are write-only | Secret value in a settings save | apps/yagurad/test/instances/secret_settings_are_write_only_test.dart | secret_value_in_a_settings_save | 3 | green |
| plugin-manifest → Secret settings are write-only | Secret value in a create | apps/yagurad/test/instances/secret_settings_are_write_only_test.dart | secret_value_in_a_create | 3 | green |
| plugin-manifest → Secret settings are write-only | Secret cleared | apps/yagurad/test/instances/secret_settings_are_write_only_test.dart | secret_cleared | 3 | green |
| plugin-manifest → Secret settings are write-only | Default on a secret rejected | packages/yagura_plugin/test/secret_settings_are_write_only_test.dart | default_on_a_secret_rejected | 3 | green |
| plugin-manifest → Secret settings are write-only | Nested secret rejected | packages/yagura_plugin/test/secret_settings_are_write_only_test.dart | nested_secret_rejected | 3 | green |
| plugin-manifest → Required secrets are checked at start | Required secret unset at start | apps/yagurad/test/instances/required_secrets_are_checked_at_start_test.dart | required_secret_unset_at_start | 3 | green |
| plugin-manifest → Required secrets are checked at start | Required secret set | apps/yagurad/test/instances/required_secrets_are_checked_at_start_test.dart | required_secret_set | 3 | green |
| steam-content → Install, update and validate apps | Update reports progress | apps/yagurad/test/steam/install_update_and_validate_apps_test.dart | update_reports_progress | 9 (M1) | green |
| steam-content → Install, update and validate apps | SteamCMD runs without SYSTEM rights | apps/yagurad/integration_test/service/steamcmd_account_test.dart (`elevated`) | steamcmd_runs_without_system_rights | 9 | red |
| steam-content → Install, update and validate apps | SteamCMD separated from game servers | apps/yagurad/integration_test/service/steamcmd_account_test.dart (`elevated`) | steamcmd_separated_from_game_servers | 9 | red |
| steam-content → Install, update and validate apps | Link planted into a system folder during an update | apps/yagurad/integration_test/service/steamcmd_account_test.dart (`elevated`) | link_planted_into_a_system_folder_during_an_update | 9 | red |
| steam-content → Install, update and validate apps | Two instances of one app installed at once | apps/yagurad/test/steam/install_update_and_validate_apps_test.dart | two_instances_of_one_app_installed_at_once | 9 (M1) | green |
| steam-content → Install, update and validate apps | Not enough disk space | apps/yagurad/test/steam/install_update_and_validate_apps_test.dart | not_enough_disk_space | 9 (M1) | green |
| steam-content → Install, update and validate apps | First install without a known size | apps/yagurad/test/steam/install_update_and_validate_apps_test.dart | first_install_without_a_known_size | 9 (M1) | green |

## 1. [M2] ADRs, spikes and dependencies

- [x] 1.1 Write ADR 0014 "SteamCMD runs as a low-privilege account" (`docs/adr/0014-...md`, `Status: proposed`, `Supersedes: 0010`) from design D10, and ADR 0015 "Game-server account and directory ACLs" (`Supersedes: 0013`) from D7, D8 and D10, including the protected instance-directory DACL, the admin-only roots and the `<data>/steamcmd` entry. Review both as a baseline round in `openspec/architecture-review.md` (the `specwright-roadmap` close rule for a superseding ADR). Once that review passes, set them accepted with the date, add their rows to the in-force index in `openspec/architecture.md`, and remove the rows for 0010 and 0013 (their files stay unchanged); annotate the 0012 row with "account and ACL setup: see 0015" and the 0009 row with "account: 0015; SteamCMD: 0014", and repoint the ADR 0010 and 0013 citations in the component table and contracts list (`architecture.md` lines 74, 168, 169) to 0014 and 0015. Verify: the review file ends in a passing verdict, `openspec/architecture.md` lists 0014 and 0015 but not 0010 or 0013, and no line other than the Supersedes cells of the 0014 and 0015 rows cites 0010 or 0013.
- [x] 1.2 Spike S1: in a throwaway `tool/spikes/m2_tls/`, serve grpc 5.2.0 with `requestClientCertificate: true` and check that (a) a client without a certificate completes the handshake and calls a method, (b) a client with a certificate from another CA gets through TLS with `call.clientCertificate` set, (c) an expired client certificate is presented or refused. Also sign a P-256 CSR with `x509` on the daemon side, and build a PKCS#10 CSR in-process with `pointycastle` on the client side. Record the results and the decision (one listener, or the port + 1 fallback from D1) in `docs/milestones/m2.md`, and amend D1 only with the user's agreement if the fallback is needed. Verify: the spike's script output is quoted in `docs/milestones/m2.md`.
- [x] 1.3 Spike S2 in the `elevated` workflow on a GitHub Windows runner (a throwaway `elevated/**` branch, never merged), not on a developer's desktop: register a throwaway WinSW service running a stub that launches a relay as a temporary low-privilege account on its own window station and desktop; stop, restart and upgrade the service, then check that the relay survives each one; check that `yagurad signal` as LocalSystem can deliver Ctrl+C to that relay's console (otherwise the D7 fallback is used); run a SteamCMD install as a second account on a separate desktop. Record the results in `docs/milestones/m2.md`. Verify: each check has a pass/fail line there, and any fallback taken is named.
- [x] 1.4 Add the workspace package `packages/yagura_pki` (empty library, depending on `pointycastle`; D1) and the dependencies (`yagura_pki` in `apps/yagurad`; `yagura_pki`, `pointycastle`, `flutter_secure_storage` in `apps/yagura_desktop`), the bundled WinSW 2.x executable with its MIT notice under `tool/winsw/`, and an `elevated` tag in `apps/yagurad/dart_test.yaml` (skipped by default, like `valheim`) and `paths: [test, integration_test]` in the same file, so every `dart test` in `apps/yagurad` (ci.yml and the `elevated` workflow) also loads `integration_test/`, and the manual `elevated` workflow (`.github/workflows/elevated.yml`, on a GitHub Windows runner, which runs as administrator; started by hand with `workflow_dispatch` once it is on `main`, or by pushing an `elevated/<name>` branch until then) that runs `dart test --run-skipped -t elevated` in `apps/yagurad` outside the runner's job. Re-run the dependency skill discovery and update `.claude/skills/UPSTREAM.json`. Verify: `dart pub get`, `dart analyze` and `flutter analyze` are clean, and `dart test` skips `elevated` tests by default.

## 2. [M2] Win32 security bindings, secret store and migration 4

Covers: host-service → Startup sequence (secret store step, scope recovery; M1 migration rows re-run). The store built here is what groups 3, 6 and 9 use.

- [x] 2.1 Write the failing tests for this group's rows and unit tests for `SecretStore` (put/get/delete, `scope_sid` recorded, foreign-scope rows); verify each fails for the stated reason.
- [x] 2.2 Add to `platform/win32.dart` the hand-written bindings the change needs: DPAPI, token queries (`OpenProcessToken`, `GetTokenInformation`), SID conversion, and the security-descriptor calls (`ConvertStringSecurityDescriptorToSecurityDescriptorW`, `SetKernelObjectSecurity`). Verify: `dart analyze` is clean, and a `windows` test round-trips a DPAPI blob and reads the current process's user SID.
- [x] 2.3 Implement migration 4 (`secrets` with `scope_sid`, `instances.revision`, `instances.acl_layout`, `runs.launched_ports`, the device, certificate, pairing-code, audit and auth-failure tables, `instance_roots`, and the SteamCMD ready and size rows) and the DPAPI `SecretStore` (D3) as a fatal startup step, with service-mode recovery of foreign-scope rows (notice `secrets_reset`) and the dev-mode refusal. Verify: `data_directory_used_by_a_dev_daemon_first` and the store tests pass; `migration_with_backup` and `migration_fails` still pass; flip the rows.
- [x] 2.4 Document the secret store, the scope rule and the recovery in `docs/` (operator notes next to the data-directory docs). Verify: the doc names `secrets_reset` and `secret_store_unavailable`, and the reason-code test from M1 task 8.3 passes.
- [x] 2.5 Review this group's diff with a fresh-context reviewer before group 3 starts; fix any P0/P1 finding. Verify: the review result has no open P0/P1.

## 3. [M2] Secret settings contract

Covers: plugin-manifest → Secret settings are write-only, Required secrets are checked at start; plugin-hooks → Hook input and output contract; daemon-security → Secrets never leave the daemon (read path, write failure); instance-lifecycle → Durable state (secrets excluded).

- [x] 3.1 Write the failing tests for this group's rows; delete `apps/yagurad/test/instances/secret_settings_stay_unset_test.dart` together with the REMOVED requirement it covered. Verify: the new tests fail for the stated reason, and `dart test` has no reference to the deleted test.
- [x] 3.2 Implement `SetSecret` and `DeleteSecret` through the secret store, `secret_via_set_secret` for values in CreateInstance and UpdateSettings (`settings.dart:163-180`), `{"secret": true, "set": <bool>}` in reads, the hook context and `instance.json`, the `secret_required` check at Start, and deletion of secret rows with the instance. Verify: this group's rows pass; flip them; `invalid_result_shape` still passes.
- [x] 3.3 Update `docs/protocol.md` (reasons `secret_via_set_secret`, `secret_required`, the SetSecret flow) and `docs/plugins/manifest.md` (secret settings). Verify: the M1 reason-code and doc-snippet tests pass.
- [x] 3.4 Review this group's diff with a fresh-context reviewer; fix any P0/P1 finding. Verify: no open P0/P1.

## 4. [M2] Instance revisions

Covers: instance-lifecycle → Concurrent edits are detected by revision.

- [x] 4.1 Write the failing tests for this group's rows; verify each fails for the stated reason.
- [ ] 4.2 Implement D12: `expected_revision` checked and incremented in the write transaction for UpdateSettings, SetSecret, DeleteSecret, DeleteInstance and RestoreSnapshot (incremented when a restore is accepted), `revision_required` and `revision_conflict` with the current revision in the details, and `Instance.revision` read from the database instead of `0` (`instance.dart:124`). Verify: this group's rows pass; flip them.
- [ ] 4.3 Update `docs/protocol.md` on revision semantics (which calls, when restore increments). Verify: the reason-code test passes.
- [ ] 4.4 Review this group's diff with a fresh-context reviewer; fix any P0/P1 finding. Verify: no open P0/P1.

## 5. [M2] ConfinedFs and InstanceFs

Covers: instance-lifecycle → Daemon file operations do not follow links planted in instance directories; the M1 snapshot, delete and durable-state rows re-run on the new file layer.

- [ ] 5.1 Write the failing `windows` tests for this group's rows against real NTFS junctions and symbolic links; verify each fails for the stated reason.
- [ ] 5.2 Add the `NtCreateFile`, `GetFinalPathNameByHandleW` and related bindings, and implement `ConfinedFs` (D8): root open with reparse refusal and final-path check, handle-relative walk, read, list, atomic write, no-descend delete, and copy-for-snapshot. Verify: this group's rows pass; flip them.
- [ ] 5.3 Move every caller listed in D8 (including the SteamCMD install-directory creation and `_recordSize`) to InstanceFs, give `<data>/steamcmd` its own ConfinedFs root for the bootstrap download, cleanup and installation delete, move the ready marker and app sizes to the database, delete `InstanceRoot`, and add the enforcement test that no `dart:io` file call under `lib/src/` takes an instance or steamcmd path outside the ConfinedFs files. Verify: the enforcement test passes, and the M1 rows of groups 5 and 9 still pass.
- [ ] 5.4 Review this group's diff with a fresh-context reviewer; fix any P0/P1 finding. Verify: no open P0/P1.

## 6. [M2] Identity, pairing, mutual TLS and audit

Covers: daemon-security → Daemon identity, Pairing with a one-time code, Mutual TLS on every call, Device certificate renewal, Device management (remote), Audit log, Development mode is localhost only; instance-lifecycle → Snapshot skipped on request.

- [ ] 6.1 Implement `packages/yagura_pki` test-first (D1: DER encoder and parser, certificate and CSR build, sign and verify, the certificate profile and CSR rules; tests parse each output back, complete a TLS handshake, and check that TLS refuses a chain through a client certificate used as an issuer), then write the failing tests for this group's rows against an in-process server with a real TLS listener and clients holding certificates built with it; verify each fails for the stated reason.
- [ ] 6.2 Implement the CA, the server certificate and its rotation (D1, D4: close and re-serve, fallback to the old certificate with `server_cert_rotation_failed`, exit when both binds fail), with identity created only in service mode, and the `service_mode_required` exit for console starts without `--dev` (`run_command.dart:133-142`). Verify: the identity and development-mode rows pass; flip them.
- [ ] 6.3 Implement the `AuthGate` in `GuardedService` and around both reflection services (D2), pairing (`Pairing.Info`, `Pairing.Enroll` with code format, throttles and the 50-guess invalidation), renewal, device listing and revocation with the 5 s stream cancellation, and the audit and auth-failure tables with in-memory aggregation (D4). Add the descriptor-walk test and a v1alpha reflection test. Verify: the remaining group rows pass, including `snapshot_skipped_on_request`; flip them.
- [ ] 6.4 Add `admin_channel_ok`, `service_accounts_ok` and `server_cert_not_after` to `DaemonHealth` in `proto/yagura/v1/system.proto`, regenerate `packages/yagura_proto`, and update `docs/protocol.md` (pairing flow, mTLS, reasons including `certificate_expired` and `csr_invalid` in the Auth reasons, the M2 row of "Methods by daemon version"; drop the conditional spike sentence and the port + 1 fallback from "Per-call authorization"). Verify: the M1 methods-by-version and reason-code tests pass.
- [ ] 6.5 Review this group's diff with a fresh-context reviewer; fix any P0/P1 finding. Verify: no open P0/P1.

## 7. [M2] Local admin channel and instance roots

Covers: daemon-security → Local admin channel is restricted to administrators, Device management (host revoke); host-service → Data directory layout (roots); instance-lifecycle → Instance creation (directory outside the roots).

- [ ] 7.1 Write the failing tests for this group's rows; verify each fails for the stated reason.
- [ ] 7.2 Implement the admin pipe (D5): `FILE_FLAG_FIRST_PIPE_INSTANCE` with the SY/BA descriptor, `admin_channel_squatted`, the CLI's LocalSystem server check (`admin_channel_untrusted`), `elevation_required`, `daemon_not_running`, and the `pair`, `devices`, `status` and `roots` commands audited as `host-admin`. Verify: the admin-channel and host-revoke rows pass (`elevated` rows in the `elevated` workflow); flip them.
- [ ] 7.3 Implement `roots add|remove|list` with the protected DACL written by `SetKernelObjectSecurity` (`root_not_protected`, `root_in_use`), and make instance creation check the configured roots with no ACL change on refusal. Verify: the roots rows and `directory_outside_the_instance_roots` pass; flip them; the M1 instance-creation rows still pass.
- [ ] 7.4 Document the admin CLI (`pair`, `devices`, `status`, `roots`) in the operator docs. Verify: every command and reason it can print appears in the doc.
- [ ] 7.5 Review this group's diff with a fresh-context reviewer; fix any P0/P1 finding. Verify: no open P0/P1.

## 8. [M2] Windows service install, upgrade and survival

Covers: host-service → Windows service install and control, Servers survive service stop and upgrade.

- [ ] 8.1 Write the failing tests for this group's rows (`elevated` ones run in the `elevated` workflow against a throwaway data directory and service name); verify each fails for the stated reason.
- [ ] 8.2 Implement `service install|configure|uninstall|status` (D6): versioned install directories, the WinSW XML template in `tool/winsw/`, the 60 s ready poll over the admin pipe, upgrade from a newer bundle, `service_exists`, `port_conflict` on configure, `--purge-accounts` (accounts, their profiles and secret rows) with `servers_running`, and deletion of unused version directories at startup. Verify: this group's rows pass in the `elevated` workflow; record them in `docs/milestones/m2.md`; flip them.
- [ ] 8.3 Write `docs/install.md` (install, configure, upgrade, uninstall, and the pairing command printed at the end). Verify: each command in it is exercised by a row of this group.
- [ ] 8.4 Review this group's diff with a fresh-context reviewer; fix any P0/P1 finding. Verify: no open P0/P1.

## 9. [M2] Service accounts, launcher, ACLs and verified termination

Covers: host-service → Game servers run under a low-privilege account, Startup sequence (data-directory protection); steam-content → Install, update and validate apps (SteamCMD account; M1 rows re-run); instance-lifecycle → Only verified game server processes are terminated, Graceful stop (service), Instance creation (account access), Error reasons have defined exits (`run_record_rejected`; M1 rows re-run).

- [ ] 9.1 Write the failing tests for this group's rows; verify each fails for the stated reason.
- [ ] 9.2 Implement account creation and repair for `yagura-srv` and `yagura-steam` at every service-mode start (D7: password encoding, password set without a test logon, Users-only membership, the four named logon rights, `service_accounts_ok`), the data-directory protection before the database opens (D6: owner, protected DACL, the `<data>/acl-layout` walk, `data_dir_not_protected`), owner Administrators on every DACL write, the instance-directory DACL at create, and the one-time ACL migration of older instances through the InstanceFs walk (`acl_layout`, `acl_migration_failed`). Verify: `game_server_account_access_set`, `instance_created_before_the_service`, `data_directory_created_by_an_earlier_daemon`, `data_directory_is_a_link`, `layout_marker_planted_by_a_standard_user` and `link_in_the_data_directory_at_first_service_start` pass in the `elevated` workflow; flip them; `data_directory_used_by_a_dev_daemon_first` still passes with the fake protector.
- [ ] 9.3 Implement the shared logon module (`LogonUserW`, profile load balanced by `UnloadUserProfile`, environment, `CreateProcessAsUserW`) on `YaguraSrv\Default` and `YaguraSteam\Default` with account-SID ACLs, game servers as `yagura-srv` through the launcher, SteamCMD (and the bootstrap `tar` extraction) as `yagura-steam` started by the daemon itself (`CREATE_SUSPENDED`, the operation's kill-on-close job, stdout/stderr pipes, handle inheritance limited to those pipe ends; D10), and the signal path from spike 1.3. Verify: the server-identity, logon, SteamCMD and service graceful-stop rows pass in the `elevated` workflow; flip them; the M1 steam and graceful-stop rows still pass.
- [ ] 9.4 Implement process verification (D9): token user and parentage checks before any signal, kill or re-attach, the forged-`relay.json` fallback, and `error: run_record_rejected` with its exits. Verify: the verification and error-reason rows pass; flip them; the M1 error-reason rows still pass.
- [ ] 9.5 Update `docs/protocol.md` (`launch_logon_failed`, `run_record_rejected`, `acl_migration_failed`, `data_dir_not_protected`) and the operator docs (accounts, what they can access, and the shared-host note that the first service start trusts an existing data directory, D6). Verify: the reason-code test passes.
- [ ] 9.6 Review this group's diff with a fresh-context reviewer; fix any P0/P1 finding. Verify: no open P0/P1.

## 10. [M2] Firewall reconciler

Covers: firewall-rules (all requirements); host-service → Startup sequence (firewall unavailable); instance-lifecycle → Deleting (owned rules removed).

- [ ] 10.1 Write the failing tests for this group's rows (fake firewall for in-process rows, the real Windows Firewall for `elevated` rows); verify each fails for the stated reason.
- [ ] 10.2 Write the reconcile PowerShell script and time one run with 300 rules in the `elevated` workflow (never on the developer's desktop). If it takes over 10 s, stop and revisit D11 with the user before wiring triggers. Verify: the timing is recorded in `docs/milestones/m2.md`, and `admins_own_rule_untouched` and `foreign_rule_inside_the_group` pass in the `elevated` workflow.
- [ ] 10.3 Implement the reconciler (D11): desired state from instances and launched ports, the owned-name regex with its round-trip test, single-flight with one coalesced pending run, operations awaiting the reconcile (60 s bound), degraded flags and `firewall_ok`, service mode only (`not_built` in dev mode), the API port rule, and the triggers. Verify: all firewall rows, `firewall_unavailable_at_startup` and `delete_keeping_files` pass (`elevated` ones in the `elevated` workflow); flip them.
- [ ] 10.4 Document the firewall rules (naming, what is never touched, how to see degraded state) in the operator docs. Verify: the doc names the group, the naming scheme and `firewall_unavailable`.
- [ ] 10.5 Review this group's diff with a fresh-context reviewer; fix any P0/P1 finding. Verify: no open P0/P1.

## 11. [M2] Desktop: paired daemons, pairing, renewal and conflicts

Covers: desktop-client (all requirements); daemon-security → Client pins the daemon CA.

- [ ] 11.1 Write the failing widget tests for this group's rows against fake daemon connections and a fake keychain; verify each fails for the stated reason.
- [ ] 11.2 Implement the daemon registry and per-daemon secure connections (D13): keychain storage, pinned CA with authority `yagurad-<daemon-id>`, connection states with backoff 1 s to 30 s, `revoked` and `expired`, and the loopback dev daemon entry. Verify: the multiple-daemons and CA-pinning rows pass; flip them.
- [ ] 11.3 Implement pairing from a pairing string (in-process key and CSR, `Pairing.Info`, fingerprint check, `Enroll`, key deleted on failure), renewal on connect and every 24 h, the create flow calling `SetSecret` after `CreateInstance`, and the revision-conflict reload that keeps edits. Verify: the remaining group rows pass; flip them; the M1 forms rows still pass.
- [ ] 11.4 Update the desktop user docs (pairing, daemon list states, conflicts). Verify: each state shown in the UI is described.
- [ ] 11.5 Review this group's diff with a fresh-context reviewer; fix any P0/P1 finding. Verify: no open P0/P1.

## 12. [M2] Integration, write-back and M2 exit

- [ ] 12.1 Write and pass `data_directory_scan`: set known secret values, run an install-start-stop workflow with the fake SteamCMD, and scan every file under the data and instance directories. Flip the row. Verify: the test passes on Windows CI.
- [ ] 12.2 Run the tests on CI: Windows runs every test not tagged `elevated` or `valheim`; Linux runs every test not tagged `windows`, `elevated` or `valheim`; plus `openspec validate --all --strict`. Verify: all pass, and every test-map row not tagged `elevated` or `valheim` is green.
- [ ] 12.3 Run the `elevated` rows in the `elevated` workflow, and have the user run the `valheim` rows on their machine; record both in `docs/milestones/m2.md`. Verify: every row in the test map is green.
- [ ] 12.4 Write back into `openspec/architecture.md` what this design owns: the component diagram (service mode, admin channel, SteamCMD as `yagura-steam`, ConfinedFs), the secrets row (account passwords, `scope_sid`), the `run_record_rejected` row of the error-reason table, and the resource-bound rows for pairing throttles, the auth-failure aggregation and the firewall reconcile. Verify: each item is present and the ADR index matches task 1.1.
- [ ] 12.5 Remove from `openspec/changes/platform-backlog/` what this change took: groups 10-13 with their test-map rows, design rows D13, D16 and D20, and the M2 parts of its delta specs. Verify: `openspec validate platform-backlog --strict` passes and a search of the backlog finds no M2 requirement left.
- [ ] 12.6 Run the M2 exit criteria from `openspec/roadmap.md` and record the results in `docs/milestones/m2.md`; the user-verified criteria (fresh host paired in under 5 minutes, service stop and upgrade, two daemons and a conflict) are run and recorded by the user. Verify: each criterion has a result line with evidence, and none is marked passed on the user's behalf.

## Workflow follow-up

- This change carries M2 (Secure remote host). After archive, `specwright-roadmap close` walks the exit criteria recorded in `docs/milestones/m2.md`.
- When a task adds a dependency to any workspace package, re-run the dependency skill discovery and update `.claude/skills/UPSTREAM.json`.
- Elevated rows are never run on CI (Actions minutes are budgeted); their evidence is the local run recorded in `docs/milestones/m2.md`.
