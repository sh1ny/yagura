import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/service/account_purger.dart';
import 'package:yagurad/src/service/service_control.dart';
import 'package:yagurad/src/service/winsw_config.dart';

import '../support/service_support.dart';

// The install logic of design D6 against a fake service control manager and
// a temporary install root. The same behaviour against the real manager and
// WinSW is the `elevated` rows in integration_test/service/.
void main() {
  group('install', () {
    test('lays_out_the_version_the_wrapper_and_the_configuration', () async {
      final rig = InstallerRig();
      rig.status = (_) => {
        'mode': 'service',
        'version': '0.1.0',
        'api_port': 7443,
        'service_accounts': 'ready',
        'api_port_rule': 'present',
      };

      await rig.installer.install();

      final layout = rig.layout;
      expect(File(layout.executable('0.1.0')).existsSync(), isTrue);
      expect(
        File(p.join(layout.versionDirectory('0.1.0'), 'lib', 'sqlite3.dll'))
            .existsSync(),
        isTrue,
        reason: 'the whole bundle is copied',
      );
      expect(
        Directory(p.join(layout.versionDirectory('0.1.0'), 'winsw'))
            .existsSync(),
        isFalse,
        reason: 'WinSW is not part of the version',
      );
      expect(File(layout.winswExecutable).existsSync(), isTrue);
      final config = ServiceConfig.parse(rig.configText(), layout)!;
      expect(config.version, '0.1.0');
      expect(config.bind, '0.0.0.0:7443');
      expect(config.dataDirectory, isNull);
      expect(rig.control.calls, ['install', 'start']);
      expect(rig.control.installedConfigs.single, rig.configText());
      expect(rig.control.status('yagurad'), ServiceStatus.running);
      // What the daemon reports and the command to run next.
      expect(rig.output, contains('service_accounts: ready'));
      expect(rig.output, contains('api_port_rule: present'));
      expect(rig.output, contains('yagurad pair'));
    });

    test('bind_and_data_directory_go_into_the_arguments', () async {
      final rig = InstallerRig();

      await rig.installer.install(
        bind: '127.0.0.1:9000',
        dataDirectory: r'D:\Yagura Data\',
      );

      final config = ServiceConfig.parse(rig.configText(), rig.layout)!;
      expect(config.bind, '127.0.0.1:9000');
      expect(config.dataDirectory, r'D:\Yagura Data');
    });

    test('not_elevated_changes_nothing', () async {
      final rig = InstallerRig(elevated: false);

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'elevation_required');
      expect(rig.control.calls, isEmpty);
      expect(rig.control.services, isEmpty);
      expect(rig.rootExists, isFalse, reason: 'nothing was copied');
      expect(rig.adminCalls, isEmpty);
    });

    test('an_invalid_bind_is_refused_before_anything_is_copied', () async {
      final rig = InstallerRig();

      final e = await failureOf(() => rig.installer.install(bind: 'nope'));

      expect(e.reason, 'bind_invalid');
      expect(rig.rootExists, isFalse);
    });

    test('a_bundle_without_the_pinned_winsw_is_refused', () async {
      final rig = InstallerRig();
      File(rig.bundle.winswExecutable).writeAsStringSync('not winsw');

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'bundle_invalid');
      expect(rig.rootExists, isFalse);
      expect(rig.control.calls, isEmpty);
    });

    test('same_version_is_service_exists_and_changes_nothing', () async {
      final rig = InstallerRig();
      await rig.installer.install(bind: '0.0.0.0:7000');
      final before = rig.configText();
      rig.control.calls.clear();

      final again = await failureOf(rig.installer.install);

      expect(again.reason, 'service_exists');
      expect(again.message, contains('0.1.0'));
      expect(rig.configText(), before);
      expect(rig.control.calls, isEmpty, reason: 'the service is untouched');
      expect(rig.control.status('yagurad'), ServiceStatus.running);
    });

    test('an_older_bundle_does_not_replace_a_newer_install', () async {
      final rig = InstallerRig(version: '0.2.0');
      await rig.installer.install();
      rig.useBundle('0.1.0');
      rig.control.calls.clear();

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'service_exists');
      expect(e.message, contains('0.2.0'));
      expect(
        Directory(rig.layout.versionDirectory('0.1.0')).existsSync(),
        isFalse,
      );
      expect(rig.control.calls, isEmpty);
    });

    test(
      'a_registered_service_without_its_configuration_is_service_exists',
      () async {
        final rig = InstallerRig();
        rig.control.services['yagurad'] = ServiceStatus.running;

        final e = await failureOf(rig.installer.install);

        expect(e.reason, 'service_exists');
        expect(rig.control.calls, isEmpty);
        expect(rig.rootExists, isFalse);
      },
    );

    test('a_newer_bundle_upgrades_keeping_bind_and_data_directory', () async {
      final rig = InstallerRig();
      await rig.installer.install(
        bind: '10.0.0.5:9000',
        dataDirectory: r'D:\YaguraData',
      );
      final oldVersion = rig.layout.versionDirectory('0.1.0');
      final oldFiles = Directory(oldVersion)
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .toList();
      rig.control.calls.clear();
      rig.out.clear();
      rig.useBundle('0.2.0');

      await rig.installer.install();

      final config = ServiceConfig.parse(rig.configText(), rig.layout)!;
      expect(config.version, '0.2.0');
      expect(config.bind, '10.0.0.5:9000');
      expect(config.dataDirectory, r'D:\YaguraData');
      expect(File(rig.layout.executable('0.2.0')).existsSync(), isTrue);
      // The old version stays: its relays are still running from it.
      expect(oldFiles, isNotEmpty);
      expect(oldFiles.every((f) => File(f).existsSync()), isTrue);
      // Stop, rewrite, start: the registration is not touched.
      expect(rig.control.calls, ['stop', 'start']);
      expect(rig.control.status('yagurad'), ServiceStatus.running);
      expect(rig.output, contains('upgraded'));
      expect(rig.output, contains('0.1.0'));
      expect(rig.output, contains('0.2.0'));
    });

    test('an_upgrade_takes_no_new_bind', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      rig.useBundle('0.2.0');

      final e = await failureOf(() => rig.installer.install(bind: '1.2.3.4:5'));

      expect(e.reason, 'service_exists');
      expect(e.message, contains('service configure'));
      expect(
        ServiceConfig.parse(rig.configText(), rig.layout)!.version,
        '0.1.0',
      );
    });

    test(
      'an_upgrade_that_cannot_start_restores_the_old_configuration',
      () async {
        final rig = InstallerRig();
        await rig.installer.install();
        final before = rig.configText();
        rig.useBundle('0.2.0');
        rig.control.calls.clear();
        // The first start (of the new version) fails; the second works.
        rig.control.failing.add('start');

        final e = await failureOf(rig.installer.install);

        expect(e.reason, 'service_command_failed');
        expect(rig.configText(), before, reason: 'back to the old version');
        expect(rig.control.calls, ['stop', 'start', 'start']);
        expect(rig.control.status('yagurad'), ServiceStatus.running);
      },
    );

    test('the_ready_poll_waits_for_the_daemon', () async {
      final rig = InstallerRig();
      rig.status = (poll) => poll < 3
          ? throw YaguraException('daemon_not_running', 'not yet')
          : {'mode': 'service', 'api_port': 7443};

      await rig.installer.install();

      expect(rig.adminCalls, ['status', 'status', 'status', 'status']);
      expect(rig.output, contains('mode: service'));
    });

    test('a_daemon_that_never_answers_is_service_not_ready', () async {
      final rig = InstallerRig();
      final started = rig.clock;
      rig.status = (_) =>
          throw YaguraException('daemon_not_running', 'nothing serves');

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'service_not_ready');
      expect(e.message, contains('daemon_not_running'));
      expect(e.message, contains(rig.layout.logDirectory));
      final waited = rig.clock.difference(started);
      expect(waited, greaterThanOrEqualTo(const Duration(seconds: 60)));
      expect(waited, lessThan(const Duration(seconds: 62)));
      // The service stays installed so the logs can be read.
      expect(rig.control.status('yagurad'), ServiceStatus.running);
    });

    test('an_untrusted_admin_channel_ends_the_poll_at_once', () async {
      final rig = InstallerRig();
      rig.status = (_) =>
          throw YaguraException('admin_channel_untrusted', 'squatter');

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'admin_channel_untrusted');
      expect(rig.adminCalls, ['status']);
    });

    test('a_failed_registration_removes_what_install_laid_down', () async {
      final rig = InstallerRig();
      rig.control.failing.add('install');

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'service_command_failed');
      expect(rig.rootExists, isFalse, reason: 'nothing is left behind');
      expect(rig.control.services, isEmpty);
    });
  });

  group('configure', () {
    test('rewrites_the_bind_and_keeps_the_rest', () async {
      final rig = InstallerRig();
      await rig.installer.install(
        bind: '0.0.0.0:7443',
        dataDirectory: r'D:\YaguraData',
      );
      rig.out.clear();
      rig.control.calls.clear();
      rig.other = (command, args) {
        expect(command, 'ports.check');
        expect(args, {'port': 9100});
        return {};
      };

      await rig.installer.configure(bind: '0.0.0.0:9100');

      final config = ServiceConfig.parse(rig.configText(), rig.layout)!;
      expect(config.bind, '0.0.0.0:9100');
      expect(config.version, '0.1.0');
      expect(config.dataDirectory, r'D:\YaguraData');
      expect(rig.control.calls, isEmpty, reason: 'applies at the next start');
      expect(rig.output, contains('next service start'));
    });

    test('a_port_an_instance_uses_is_port_conflict', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      final before = rig.configText();
      rig.other = (_, _) => throw YaguraException(
        'port_conflict',
        'port game of "Friends" uses 9100',
      );

      final e = await failureOf(
        () => rig.installer.configure(bind: '0.0.0.0:9100'),
      );

      expect(e.reason, 'port_conflict');
      expect(e.message, contains('Friends'));
      expect(rig.configText(), before);
    });

    test('a_stopped_daemon_cannot_be_asked_and_is_not', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      // The default `other` answers daemon_not_running.

      await rig.installer.configure(bind: '0.0.0.0:9100');

      expect(
        ServiceConfig.parse(rig.configText(), rig.layout)!.bind,
        '0.0.0.0:9100',
      );
    });

    test('an_unreadable_bind_is_bind_invalid', () async {
      final rig = InstallerRig();
      await rig.installer.install();

      final e = await failureOf(() => rig.installer.configure(bind: 'x'));

      expect(e.reason, 'bind_invalid');
    });

    test('without_a_service_it_is_service_not_installed', () async {
      final rig = InstallerRig();

      final e = await failureOf(
        () => rig.installer.configure(bind: '0.0.0.0:9'),
      );

      expect(e.reason, 'service_not_installed');
    });

    test('not_elevated_changes_nothing', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      final before = rig.configText();
      rig.elevated = false;

      final e = await failureOf(
        () => rig.installer.configure(bind: '0.0.0.0:9'),
      );

      expect(e.reason, 'elevation_required');
      expect(rig.configText(), before);
    });
  });

  group('uninstall', () {
    test('removes_the_service_and_its_files_and_leaves_the_data', () async {
      final rig = InstallerRig();
      final data = Directory(p.join(rig.root.path, 'data'))..createSync();
      File(p.join(data.path, 'yagura.db')).writeAsStringSync('db');
      await rig.installer.install(dataDirectory: data.path);
      File(p.join(rig.layout.logDirectory, 'wrapper.log'))
        ..createSync(recursive: true)
        ..writeAsStringSync('log');
      rig.control.calls.clear();
      rig.out.clear();

      await rig.installer.uninstall();

      expect(rig.control.calls, ['stop', 'uninstall']);
      expect(rig.control.services, isEmpty);
      expect(File(rig.layout.configFile).existsSync(), isFalse);
      expect(File(rig.layout.winswExecutable).existsSync(), isFalse);
      expect(
        Directory(rig.layout.versionDirectory('0.1.0')).existsSync(),
        isFalse,
      );
      expect(File(p.join(data.path, 'yagura.db')).existsSync(), isTrue);
      expect(rig.purger.calls, 0);
      expect(rig.output, contains('data directory'));
    });

    test('an_already_stopped_service_is_not_stopped_again', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      rig.control.services['yagurad'] = ServiceStatus.stopped;
      rig.control.calls.clear();

      await rig.installer.uninstall();

      expect(rig.control.calls, ['uninstall']);
    });

    test('without_a_service_it_is_service_not_installed', () async {
      final rig = InstallerRig();

      final e = await failureOf(rig.installer.uninstall);

      expect(e.reason, 'service_not_installed');
    });

    test('not_elevated_changes_nothing', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      rig.elevated = false;
      rig.control.calls.clear();

      final e = await failureOf(rig.installer.uninstall);

      expect(e.reason, 'elevation_required');
      expect(rig.control.calls, isEmpty);
    });

    test('purge_accounts_is_refused_while_a_server_runs', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      rig.servers.running = ['Friends', 'Raid night'];
      rig.control.calls.clear();

      final e = await failureOf(
        () => rig.installer.uninstall(purgeAccounts: true),
      );

      expect(e.reason, 'servers_running');
      expect(e.message, contains('Friends'));
      expect(e.message, contains('Raid night'));
      // Nothing was changed: not even the service.
      expect(rig.control.calls, isEmpty);
      expect(rig.control.status('yagurad'), ServiceStatus.running);
      expect(File(rig.layout.configFile).existsSync(), isTrue);
      expect(rig.purger.calls, 0);
    });

    test('running_servers_do_not_stop_a_plain_uninstall', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      rig.servers.running = ['Friends'];

      await rig.installer.uninstall();

      expect(rig.control.services, isEmpty);
      expect(rig.purger.calls, 0);
    });

    test('purge_accounts_runs_after_the_service_is_gone', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      rig.control.calls.clear();
      rig.out.clear();

      await rig.installer.uninstall(purgeAccounts: true);

      expect(rig.control.calls, ['stop', 'uninstall']);
      expect(rig.purger.calls, 1);
      expect(rig.output, contains('yagura-srv'));
      expect(rig.output, contains('yagura-steam'));
    });

    test('an_account_kept_for_its_profile_is_reported_and_fails', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      rig.purger.outcomes = const [
        PurgeOutcome('yagura-srv', removed: true),
        PurgeOutcome(
          'yagura-steam',
          removed: false,
          reason: 'its profile is still in use (error 32)',
        ),
      ];

      final e = await failureOf(
        () => rig.installer.uninstall(purgeAccounts: true),
      );

      expect(e.reason, 'profile_in_use');
      expect(e.message, contains('yagura-steam'));
      expect(e.message, contains('--purge-accounts'));
      expect(rig.control.services, isEmpty, reason: 'the service is gone');
    });
  });

  group('status', () {
    test('a_running_service_reports_the_daemon', () async {
      final rig = InstallerRig();
      await rig.installer.install(bind: '127.0.0.1:9000');
      rig.out.clear();
      rig.adminCalls.clear();
      rig.status = (_) => {'mode': 'service', 'version': '0.1.0', 'devices': 2};

      await rig.installer.status();

      expect(rig.output, contains('service: yagurad'));
      expect(rig.output, contains('state: running'));
      expect(rig.output, contains('version: 0.1.0'));
      expect(rig.output, contains('bind: 127.0.0.1:9000'));
      expect(rig.output, contains('devices: 2'));
      expect(rig.adminCalls, ['status']);
    });

    test('a_stopped_service_is_reported_without_asking_the_daemon', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      rig.control.services['yagurad'] = ServiceStatus.stopped;
      rig.out.clear();
      rig.adminCalls.clear();

      await rig.installer.status();

      expect(rig.output, contains('state: stopped'));
      expect(rig.adminCalls, isEmpty);
    });

    test('a_daemon_that_does_not_answer_is_named', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      rig.out.clear();
      rig.status = (_) =>
          throw YaguraException('daemon_not_running', 'nothing serves');

      await rig.installer.status();

      expect(rig.output, contains('daemon: daemon_not_running'));
    });

    test('without_a_service_it_is_service_not_installed', () async {
      final rig = InstallerRig();

      final e = await failureOf(rig.installer.status);

      expect(e.reason, 'service_not_installed');
    });

    test('not_elevated_is_elevation_required', () async {
      final rig = InstallerRig(elevated: false);

      final e = await failureOf(rig.installer.status);

      expect(e.reason, 'elevation_required');
    });
  });
}
