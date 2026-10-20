# Tasks

Parked backlog: never applied. Group numbers continue from `init-core-platform` (groups 1-9, M1) so references in the design stay valid. Groups 10-13 (M2) went to `m2-secure-remote-host` and groups 14-17 (M3) to `m3-steam-accounts-and-mods`. Each milestone change taken out of this backlog copies its groups and rows, renumbers them from 1, and adds `green` re-run rows for the earlier milestones' scenarios that ride along unchanged inside its MODIFIED requirements (those rows are not listed here).

## Test map

Every scenario of this backlog maps to a Dart test at the boundary it crosses: daemon behaviour against an in-process daemon with fake SteamCMD, fake process host and fake firewall where the real one is not needed; process, service and firewall rows against the real OS on Windows (and Linux for M5) CI runners (`integration_test/`, tagged `windows`/`linux`); desktop rows as Flutter widget tests against a fake daemon connection. The group column says which task group turns the row green; groups are tagged by milestone below.

| Requirement | Scenario | Test file | Test name | Group | State |
|---|---|---|---|---|---|
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
| plugin-manifest → Stop and health declarations | Bindings and mods sections accepted | packages/yagura_plugin/test/stop_and_health_declarations_test.dart | bindings_and_mods_sections_accepted | 18 (M4) | red |
| plugin-hooks → Sandboxed host API | Edit in an unsupported format | apps/yagurad/test/hooks/sandboxed_host_api_test.dart | edit_in_an_unsupported_format | 19 (M4) | red |
| config-bindings → Supported formats | Repeated UE keys from a list setting | packages/yagura_formats/test/supported_formats_test.dart | repeated_ue_keys_from_a_list_setting | 19 (M4) | red |
| desktop-client → Forms rendered from plugin schemas | Repeatable list as a table | apps/yagura_desktop/test/forms_rendered_from_plugin_schemas_test.dart | repeatable_list_as_a_table | 19 (M4) | red |
| instance-lifecycle → Import and export instances | Import a copied instance | apps/yagurad/test/instances/import_and_export_instances_test.dart | import_a_copied_instance | 19 (M4) | red |
| instance-lifecycle → Import and export instances | Import with unknown plugin version | apps/yagurad/test/instances/import_and_export_instances_test.dart | import_with_unknown_plugin_version | 19 (M4) | red |
| host-service → Linux service | Unit installed | apps/yagurad/integration_test/linux/linux_service_test.dart | unit_installed | 20 (M5) | red |
| host-service → Linux service | systemd not available | apps/yagurad/integration_test/linux/linux_service_test.dart | systemd_not_available | 20 (M5) | red |
| host-service → Linux service | Stopping the unit keeps servers | apps/yagurad/integration_test/linux/linux_service_test.dart | stopping_the_unit_keeps_servers | 20 (M5) | red |

## 18. [M4] RCON

Covers: instance-lifecycle → Graceful stop per plugin strategy; plugin-manifest → Stop and health declarations; desktop-client → Logs and console views (console); rcon → Plugin-declared RCON protocol; rcon → One-shot commands; rcon → Shared session and console stream; rcon → Protocol keep-alives.

- [ ] 18.1 Write the failing tests for this group's rows against fake BattlEye (UDP), Source RCON (TCP) and WebRCON (WebSocket) servers in `apps/yagurad/test/fixtures/`.
- [ ] 18.2 Implement the three adapters with keep-alives, the shared session per instance, `Execute`, the `Console` stream with command echo and 8 subscribers, reconnect backoff, auth-failure stop, and the `rcon` stop strategy. Relax the manifest's `rcon` section and `rcon` stop rejection (M3 rejects them with `unsupported_in_this_version`), and add the `rcon` section and stop to `plugins/dayz/`. Add the console view to the client. Verify: this group's rows are green; flip them.

## 19. [M4] Complex configs, more games, import/export and M4 exit

Covers: config-bindings → Supported formats; plugin-hooks → Sandboxed host API; desktop-client → Forms rendered from plugin schemas; instance-lifecycle → Import and export instances.

- [ ] 19.1 Add `ue-ini`, `xml` and `vdf` parsers to the M3 config binder and hook API, with corpora (ARK:SA `GameUserSettings.ini`/`Game.ini`); write the failing tests for this group's rows.
- [ ] 19.2 Implement `list` bindings with `repeat` mode, import/export, and the client's table editor for `list` settings. Verify: rows green; flip them.
- [ ] 19.3 Write `plugins/ark_sa/` (anonymous 2430930, `-mods=` server-managed, Source RCON, `game_writes: true` bindings), `plugins/scum/` (UTF-16LE logs, signal stop verified on Windows), `plugins/rust/` (WebRCON). Verify each with `yagura plugin lint` and a manual run recorded in `docs/milestones/m4.md`.

## 20. [M5] Linux agent

Covers: host-service → Linux service.

- [ ] 20.1 Write the failing integration tests for this group's rows (Linux runner).
- [ ] 20.2 Implement the POSIX `ProcessHost` (posix_spawn + setsid, servers in transient systemd scopes, SIGTERM for `signal`), the systemd unit install, the Linux secret store, a firewalld/ufw adapter behind the firewall interface, and Linux executables in the reference plugins. Verify: this group's rows are green; flip them, and record the M5 run in `docs/milestones/m5.md`.

## 21. [M4-M5] Integration

- [ ] 21.1 Run every package's tests on Windows and Linux CI and `openspec validate --all --strict`. Verify: all pass and every test-map row is green.
- [ ] 21.2 Re-run the secret scan of `apps/yagurad/integration_test/secrets_data_directory_scan_test.dart` over a full install-start-update-stop workflow that also sets the secrets added after M3 (RCON passwords), and extend it to the snapshot directories and logs. Verify: no secret value found outside the accepted exceptions.
- [ ] 21.3 Write back into `openspec/architecture.md` the decisions and Resource Bounds rows of this design that the baseline lacks (RCON, Linux agent). Verify: each is present in `openspec/architecture.md`.

## Workflow follow-up

- This change is never applied or archived. At each milestone, `specwright-roadmap next` creates the milestone's change (for example `m2-secure-remote-host`) from its groups here: the requirements as ADDED, or MODIFIED where this backlog lists them so, the decisions and table rows its groups depend on, and its test-map rows. That change gets its own design review. The moved material is then deleted here, and this change is deleted when nothing is left.
- When a task adds a dependency to any workspace package, re-run the dependency skill discovery and update `.claude/skills/UPSTREAM.json`.
- Milestone exit criteria that are user-verified are run by the user, never marked passed on their behalf.
