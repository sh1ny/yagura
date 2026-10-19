import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/instances/instance_roots.dart';
import 'package:yagurad/src/platform/acl_writer.dart';
import 'package:yagurad/src/service/account_purger.dart';
import 'package:yagurad/src/service/install_layout.dart';
import 'package:yagurad/src/service/service_control.dart';
import 'package:yagurad/src/service/service_installer.dart';
import 'package:yagurad/src/service/version_sweeper.dart';
import 'package:yagurad/src/service/winsw_config.dart';

import '../support/admin_support.dart';
import '../support/service_support.dart';

/// An ACL writer that tells [onWrite] what the directory holds when its DACL
/// is written, then lets [inner] record the write.
class _SpyingAclWriter implements AclWriter {
  _SpyingAclWriter(this.inner, this.onWrite);

  final FakeAclWriter inner;
  final void Function(String path) onWrite;

  @override
  ProtectedDirectory open(String path) =>
      _SpyingDirectory(inner.open(path), onWrite);

  @override
  ProtectedDirectory create(
    String path,
    String dacl, {
    required String ownerSid,
  }) => inner.create(path, dacl, ownerSid: ownerSid);
}

class _SpyingDirectory implements ProtectedDirectory {
  _SpyingDirectory(this._real, this._onWrite);

  final ProtectedDirectory _real;
  final void Function(String path) _onWrite;

  @override
  String get path => _real.path;

  @override
  EntrySecurity security() => _real.security();

  @override
  void writeDacl(String sddl, {String? ownerSid}) {
    _onWrite(path);
    _real.writeDacl(sddl, ownerSid: ownerSid);
  }

  @override
  void close() => _real.close();
}

/// Refuses every directory, the way the real writer refuses a link.
class _RefusingAclWriter implements AclWriter {
  _RefusingAclWriter(this.why);

  final String why;

  @override
  ProtectedDirectory open(String path) => throw PathRefused(path, why);

  @override
  ProtectedDirectory create(
    String path,
    String dacl, {
    required String ownerSid,
  }) => throw PathRefused(path, why);
}

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

    // ---- the install root is protected (G8-01) ----

    test(
      'creates_the_install_root_protected_before_anything_is_copied',
      () async {
        final rig = InstallerRig();
        // What each directory (by its name) held when its DACL was written.
        final inRootWhenProtected = <String, List<String>>{};
        rig.aclWriter = _SpyingAclWriter(
          rig.acl,
          (path) => inRootWhenProtected[p.basename(path)] = [
            for (final e in Directory(path).listSync()) p.basename(e.path),
          ],
        );

        await rig.installer.install();

        // The root came into being with its owner and DACL (one call), and its
        // DACL was never written afterwards.
        expect(rig.acl.created.single, rig.layout.root);
        final root = rig.acl.calls.first;
        expect(p.equals(root.path, rig.layout.root), isTrue, reason: '$root');
        expect(root.ownerSid, administratorsSid);
        expect(root.sddl, installRootDaclSddl);
        expect(
          rig.acl.calls.where((c) => p.equals(c.path, rig.layout.root)),
          hasLength(1),
        );
        // Protected (no inheritance from the parent), SYSTEM and
        // Administrators full control, Users read and execute only.
        expect(installRootDaclSddl, startsWith('D:P'));
        expect(installRootDaclSddl, contains('(A;OICI;FA;;;SY)'));
        expect(installRootDaclSddl, contains('(A;OICI;FA;;;BA)'));
        expect(installRootDaclSddl, contains('(A;OICI;0x1200a9;;;BU)'));
        // The version directory is protected too, before its files go in.
        expect(rig.acl.calls.map((c) => p.basename(c.path)), contains('0.1.0'));
        expect(inRootWhenProtected['0.1.0'], isEmpty);
      },
    );

    test('a_root_the_acl_writer_refuses_is_install_failed', () async {
      final rig = InstallerRig();
      rig.aclWriter = _RefusingAclWriter('it is a link, not a directory');

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'install_failed');
      expect(e.message, contains(rig.layout.root));
      expect(e.message, contains('it is a link'));
      expect(rig.control.calls, isEmpty);
      expect(rig.rootExists, isFalse, reason: 'nothing is left behind');
    });

    test('a_root_whose_dacl_cannot_be_written_is_install_failed', () async {
      final rig = InstallerRig();
      rig.acl.failure = Exception('the volume has no ACLs');

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'install_failed');
      expect(e.message, contains('the volume has no ACLs'));
      expect(rig.control.calls, isEmpty);
      expect(rig.rootExists, isFalse);
    });

    test('a_root_that_exists_keeps_its_files_when_it_is_refused', () async {
      final rig = InstallerRig();
      File(p.join(rig.layout.root, 'mine.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('keep');
      rig.acl.failure = Exception('no');

      await failureOf(rig.installer.install);

      expect(File(p.join(rig.layout.root, 'mine.txt')).existsSync(), isTrue);
    });

    test('a_refused_root_keeps_the_files_of_an_earlier_install', () async {
      final rig = InstallerRig();
      final theirs = [
        for (final name in ['yagurad.xml', 'yagurad.xml.tmp', 'yagurad.exe'])
          File(p.join(rig.layout.root, name))
            ..createSync(recursive: true)
            ..writeAsStringSync('theirs'),
        File(rig.layout.executable('0.1.0'))
          ..createSync(recursive: true)
          ..writeAsStringSync('theirs'),
      ];

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'install_dir_not_protected');
      for (final file in theirs) {
        expect(file.readAsStringSync(), 'theirs', reason: file.path);
      }
    });

    test(
      'a_root_that_is_a_junction_is_refused_and_its_target_untouched',
      () async {
        final rig = InstallerRig();
        final target = Directory(p.join(rig.root.path, 'Tools'))..createSync();
        final files = [
          for (final name in ['yagurad.xml', 'yagurad.exe', 'mine.txt'])
            File(p.join(target.path, name))..writeAsStringSync('theirs'),
        ];
        final made = Process.runSync('cmd', [
          '/c',
          'mklink',
          '/J',
          rig.layout.root,
          target.path,
        ]);
        expect(made.exitCode, 0, reason: '${made.stdout}${made.stderr}');
        addTearDown(() => Link(rig.layout.root).deleteSync());

        final e = await failureOf(rig.installer.install);

        expect(e.reason, 'install_dir_not_protected');
        expect(e.message, contains('link'));
        for (final file in files) {
          expect(file.readAsStringSync(), 'theirs', reason: file.path);
        }
        expect(target.listSync(), hasLength(3));
        expect(rig.acl.calls, isEmpty);
      },
    );

    test('a_network_install_dir_is_refused', () async {
      final rig = InstallerRig();
      final other = ServiceInstaller(
        layout: InstallLayout(root: r'\\server\share\Yagura'),
        control: rig.control,
        bundle: rig.bundle,
        admin: (c, [a = const {}]) async => {},
        out: rig.out,
        isElevated: () => true,
        servers: rig.servers,
        purger: rig.purger,
        aclWriter: rig.acl,
        inspector: rig.inspector,
        delay: (d) async {},
      );

      final e = await failureOf(other.install);

      expect(e.reason, 'install_dir_not_protected');
      expect(e.message, contains('drive'));
      expect(rig.control.calls, isEmpty);
      expect(rig.acl.calls, isEmpty);
    });

    test('an_upgrade_checks_the_root_and_protects_the_new_version', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      rig.acl.calls.clear();
      rig.useBundle('0.2.0');

      await rig.installer.install();

      final protected = rig.acl.calls.map((c) => p.basename(c.path)).toList();
      expect(protected, ['0.2.0'], reason: 'the root is only checked');
    });

    // ---- what is above and inside the root is checked (G8-R2-01/02) ----

    test('a_root_below_a_folder_a_user_owns_is_refused', () async {
      final rig = InstallerRig();
      rig.inspector.overrides[p.dirname(rig.layout.root)] = const EntrySecurity(
        isLink: false,
        sddl: userFolderSddl,
      );

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'install_dir_not_protected');
      expect(e.message, contains(p.dirname(rig.layout.root)));
      expect(rig.control.calls, isEmpty);
      expect(rig.rootExists, isFalse, reason: 'nothing was created');
      expect(rig.acl.calls, isEmpty);
    });

    test('a_root_below_a_link_is_refused', () async {
      final rig = InstallerRig();
      rig.inspector.overrides[p.dirname(rig.layout.root)] = const EntrySecurity(
        isLink: true,
        sddl: trustedFolderSddl,
      );

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'install_dir_not_protected');
      expect(e.message, contains('link'));
      expect(rig.rootExists, isFalse);
    });

    test('an_upgrade_checks_the_ancestors_too', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      rig.useBundle('0.2.0');
      rig.inspector.overrides[p.dirname(rig.layout.root)] = const EntrySecurity(
        isLink: false,
        sddl: userFolderSddl,
      );
      final before = rig.configText();

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'install_dir_not_protected');
      expect(rig.configText(), before);
      expect(rig.control.calls, ['install', 'start']);
    });

    test('a_root_with_files_nobody_protected_is_refused', () async {
      final rig = InstallerRig();
      final theirs = File(p.join(rig.layout.root, 'logs', 'x.log'))
        ..createSync(recursive: true);

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'install_dir_not_protected');
      expect(e.message, contains(rig.layout.root));
      expect(theirs.existsSync(), isTrue, reason: 'nothing is deleted');
      expect(rig.control.calls, isEmpty);
      expect(File(rig.layout.winswExecutable).existsSync(), isFalse);
    });

    for (final (name, sddl) in [
      ('owned_by_a_user', userFolderSddl),
      ('owned_by_the_system_but_not_protected', trustedFolderSddl),
    ]) {
      test('an_empty_root_that_exists_is_refused_when_$name', () async {
        // Its creator may hold a handle with WRITE_DAC across the install.
        final rig = InstallerRig();
        Directory(rig.layout.root).createSync(recursive: true);
        rig.acl.overrides[rig.layout.root] = EntrySecurity(
          isLink: false,
          sddl: sddl,
        );

        final e = await failureOf(rig.installer.install);

        expect(e.reason, 'install_dir_not_protected');
        expect(rig.acl.calls, isEmpty, reason: 'nothing was written');
        expect(rig.control.calls, isEmpty);
        expect(Directory(rig.layout.root).listSync(), isEmpty);
      });
    }

    test('an_empty_root_nobody_protected_is_refused_by_default', () async {
      final rig = InstallerRig();
      Directory(rig.layout.root).createSync(recursive: true);

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'install_dir_not_protected');
      expect(rig.acl.calls, isEmpty);
    });

    test('a_missing_root_is_created_with_its_protection', () async {
      final rig = InstallerRig();

      await rig.installer.install();

      expect(rig.acl.created, [rig.layout.root]);
      expect(rig.acl.calls.first.ownerSid, administratorsSid);
      expect(rig.acl.calls.first.sddl, installRootDaclSddl);
    });

    test('a_root_someone_made_during_the_install_is_refused', () async {
      final rig = InstallerRig();
      rig.acl.createFailure = PathExists(rig.layout.root);

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'install_dir_not_protected');
      expect(rig.control.calls, isEmpty);
      expect(rig.acl.calls, isEmpty);
    });

    test('a_root_that_cannot_be_created_is_install_failed', () async {
      final rig = InstallerRig();
      rig.acl.createFailure = PathRefused(rig.layout.root, 'access is denied');

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'install_failed');
      expect(e.message, contains('access is denied'));
    });

    test('a_created_root_that_reads_back_unprotected_is_refused', () async {
      final rig = InstallerRig();
      rig.acl.overrides[rig.layout.root] = const EntrySecurity(
        isLink: false,
        sddl: userFolderSddl,
      );

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'install_dir_not_protected');
      expect(rig.control.calls, isEmpty);
    });

    test('a_root_this_install_protected_earlier_is_trusted', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      rig.control.services.remove(rig.serviceName);
      // What the wrapper left is still there; the root was protected.
      File(p.join(rig.layout.root, 'yagurad.wrapper.log'))
          .writeAsStringSync('x');

      await rig.installer.install();

      expect(rig.control.status(rig.serviceName), ServiceStatus.running);
    });

    test('the_configuration_is_written_as_a_new_file', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      // A leftover temporary file is replaced, not written into.
      final temporary = File('${rig.layout.configFile}.tmp')
        ..writeAsStringSync('leftover that is longer than the xml ' * 400);

      await rig.installer.configure(bind: '127.0.0.1:9000');

      expect(temporary.existsSync(), isFalse, reason: 'renamed away');
      expect(rig.configText(), isNot(contains('leftover')));
      expect(rig.configText(), contains('127.0.0.1:9000'));
    });

    // ---- the version directory is reused, never deleted (G8-03) ----

    /// Installs and removes the service by hand, leaving the version
    /// directory as `uninstall` leaves it while a relay runs from it.
    Future<void> leaveVersionDirectoryBehind(InstallerRig rig) async {
      await rig.installer.install();
      rig.control.services.remove(rig.serviceName);
      File(rig.layout.configFile).deleteSync();
      File(rig.layout.winswExecutable).deleteSync();
      rig.control.calls.clear();
    }

    test('reinstalling_a_kept_version_directory_reuses_it', () async {
      final rig = InstallerRig();
      await leaveVersionDirectoryBehind(rig);
      final sentinel = File(
        p.join(rig.layout.versionDirectory('0.1.0'), 'bin', 'in-use.dll'),
      )..writeAsStringSync('a relay maps this');
      // A relay of a running server executes this file.
      final relay = File(rig.layout.executable('0.1.0')).openSync();
      addTearDown(relay.closeSync);

      await rig.installer.install();

      expect(sentinel.existsSync(), isTrue, reason: 'nothing was deleted');
      expect(File(rig.layout.configFile).existsSync(), isTrue);
      expect(rig.control.status(rig.serviceName), ServiceStatus.running);
      expect(rig.control.calls, ['install', 'start']);
    });

    test('a_file_that_differs_in_a_kept_directory_is_replaced', () async {
      final rig = InstallerRig();
      await leaveVersionDirectoryBehind(rig);
      File(p.join(rig.layout.versionDirectory('0.1.0'), 'lib', 'sqlite3.dll'))
          .writeAsStringSync('partial copy');
      final extra = File(
        p.join(rig.layout.versionDirectory('0.1.0'), 'lib', 'extra.dll'),
      )..writeAsStringSync('x');

      await rig.installer.install();

      expect(
        File(p.join(rig.layout.versionDirectory('0.1.0'), 'lib', 'sqlite3.dll'))
            .readAsStringSync(),
        'native',
      );
      expect(extra.existsSync(), isTrue, reason: 'only the bundle is written');
    });

    test(
      'a_locked_file_that_differs_fails_install_and_deletes_nothing',
      () async {
        final rig = InstallerRig();
        await leaveVersionDirectoryBehind(rig);
        final locked = File(
          p.join(rig.layout.versionDirectory('0.1.0'), 'lib', 'sqlite3.dll'),
        )..writeAsStringSync('other bytes');
        final handle = locked.openSync(mode: FileMode.append)
          ..lockSync(FileLock.exclusive);
        addTearDown(handle.closeSync);

        final e = await failureOf(rig.installer.install);

        expect(e.reason, 'install_failed');
        expect(e.message, contains('sqlite3.dll'));
        expect(
          File(rig.layout.executable('0.1.0')).existsSync(),
          isTrue,
          reason: 'the failed install leaves the directory it did not create',
        );
        expect(locked.existsSync(), isTrue);
        expect(rig.control.services, isEmpty);
      },
    );

    test('a_directory_of_another_service_is_not_taken_over', () async {
      final rig = InstallerRig()..preprotect();
      Directory(rig.layout.versionDirectory('0.1.0'))
          .createSync(recursive: true);
      File(rig.layout.markerFile('0.1.0')).writeAsStringSync('yagurad-b');
      File(rig.layout.executable('0.1.0'))
        ..createSync(recursive: true)
        ..writeAsStringSync('b');

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'install_failed');
      expect(e.message, contains('yagurad-b'));
      expect(File(rig.layout.executable('0.1.0')).readAsStringSync(), 'b');
    });

    test('a_directory_nobody_marked_is_not_taken_over', () async {
      final rig = InstallerRig()..preprotect();
      File(rig.layout.executable('0.1.0'))
        ..createSync(recursive: true)
        ..writeAsStringSync('other product');

      final e = await failureOf(rig.installer.install);

      expect(e.reason, 'install_failed');
      expect(
        File(rig.layout.executable('0.1.0')).readAsStringSync(),
        'other product',
      );
    });

    test('a_failed_install_keeps_a_directory_it_did_not_create', () async {
      final rig = InstallerRig();
      await leaveVersionDirectoryBehind(rig);
      rig.control.failing.add('install');

      await failureOf(rig.installer.install);

      expect(File(rig.layout.executable('0.1.0')).existsSync(), isTrue);
    });

    // ---- the command line (G8-09) ----

    test('a_relative_data_directory_is_made_absolute', () async {
      final rig = InstallerRig();

      await rig.installer.install(dataDirectory: p.join('data', 'yagura'));

      final config = ServiceConfig.parse(rig.configText(), rig.layout)!;
      expect(p.isAbsolute(config.dataDirectory!), isTrue);
      expect(config.dataDirectory, p.absolute(p.join('data', 'yagura')));
    });

    test('a_drive_root_data_directory_reads_back_as_the_root', () async {
      final rig = InstallerRig();

      await rig.installer.install(dataDirectory: r'D:\');

      final config = ServiceConfig.parse(rig.configText(), rig.layout)!;
      expect(config.dataDirectory, r'D:\');
    });

    test('a_percent_sign_in_a_path_is_path_invalid', () async {
      final rig = InstallerRig();

      final data = await failureOf(
        () => rig.installer.install(dataDirectory: r'D:\100%\data'),
      );

      expect(data.reason, 'path_invalid');
      expect(data.message, contains('%'));
      expect(rig.rootExists, isFalse);
      expect(rig.control.calls, isEmpty);
    });

    test('a_percent_sign_in_the_install_root_is_path_invalid', () async {
      final rig = InstallerRig();
      final other = ServiceInstaller(
        layout: InstallLayout(root: p.join(rig.root.path, 'p%PATH%')),
        control: rig.control,
        bundle: rig.bundle,
        admin: (c, [a = const {}]) async => {},
        out: rig.out,
        isElevated: () => true,
        servers: rig.servers,
        purger: rig.purger,
        aclWriter: rig.acl,
        inspector: rig.inspector,
        delay: (d) async {},
      );

      final e = await failureOf(other.install);

      expect(e.reason, 'path_invalid');
      expect(rig.control.calls, isEmpty);
    });

    test('a_bind_with_whitespace_or_a_quote_is_bind_invalid', () async {
      final rig = InstallerRig();

      for (final bind in ['127.0.0.1:80 --x', '127.0.0.1:80"', '%X%:80']) {
        final e = await failureOf(() => rig.installer.install(bind: bind));
        expect(e.reason, 'bind_invalid', reason: bind);
      }
      expect(rig.rootExists, isFalse);
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
      File(p.join(rig.layout.root, 'yagurad.wrapper.log'))
          .writeAsStringSync('w');
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
      // The wrapper's logs go too, and with them the install folder.
      expect(rig.rootExists, isFalse);
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

    // ---- the purge reads the configuration before it is deleted (G8-02) ----

    test('purge_uses_the_data_directory_the_service_runs_with', () async {
      final rig = InstallerRig();
      final data = Directory(p.join(rig.root.path, 'data'))..createSync();
      await rig.installer.install(dataDirectory: data.path);

      await rig.installer.uninstall(purgeAccounts: true);

      expect(File(rig.layout.configFile).existsSync(), isFalse);
      expect(rig.purger.dataDirectories, [data.path]);
    });

    test(
      'purge_without_a_configured_data_directory_uses_the_default',
      () async {
        final rig = InstallerRig();
        await rig.installer.install();

        await rig.installer.uninstall(purgeAccounts: true);

        expect(rig.purger.dataDirectories, [null]);
      },
    );

    // ---- a server that starts while the service stops (G8-04) ----

    test(
      'a_server_that_starts_before_the_service_stops_refuses_the_purge',
      () async {
        final rig = InstallerRig();
        await rig.installer.install();
        rig.servers.answers.addAll([
          [],
          ['Friends'],
        ]);
        rig.control.calls.clear();

        final e = await failureOf(
          () => rig.installer.uninstall(purgeAccounts: true),
        );

        expect(e.reason, 'servers_running');
        expect(e.message, contains('Friends'));
        // The service is back, and nothing was removed or purged.
        expect(rig.control.calls, ['stop', 'start']);
        expect(rig.control.status(rig.serviceName), ServiceStatus.running);
        expect(File(rig.layout.configFile).existsSync(), isTrue);
        expect(rig.purger.calls, 0);
      },
    );

    test('a_probe_that_fails_after_the_stop_restarts_the_service', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      rig.servers.failAt.add(2);
      rig.control.calls.clear();

      final e = await failureOf(
        () => rig.installer.uninstall(purgeAccounts: true),
      );

      expect(e.reason, 'admin_connection_closed');
      expect(rig.control.calls, ['stop', 'start']);
      expect(rig.control.status(rig.serviceName), ServiceStatus.running);
      expect(File(rig.layout.configFile).existsSync(), isTrue);
      expect(rig.purger.calls, 0);
    });

    test('a_configuration_that_does_not_parse_fails_the_purge', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      File(rig.layout.configFile)
          .writeAsStringSync('<service>not ours</service>');
      rig.control.calls.clear();

      final e = await failureOf(
        () => rig.installer.uninstall(purgeAccounts: true),
      );

      expect(e.reason, 'service_config_invalid');
      expect(e.message, contains(rig.layout.configFile));
      expect(rig.control.calls, isEmpty);
      expect(rig.purger.calls, 0);
    });

    test('a_plain_uninstall_does_not_look_at_the_servers', () async {
      final rig = InstallerRig();
      await rig.installer.install();

      await rig.installer.uninstall();

      expect(rig.servers.calls, 0);
    });

    // ---- only this service's version directories (G8-05) ----

    test('uninstall_deletes_only_the_directories_of_its_own_service', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      // Another service's version, and another product's versioned folder.
      File(p.join(rig.layout.root, '0.9.0', 'bin', 'yagurad.exe'))
        ..createSync(recursive: true)
        ..writeAsStringSync('b');
      File(rig.layout.markerFile('0.9.0')).writeAsStringSync('yagurad-b');
      File(p.join(rig.layout.root, '3.5.0', 'tool.exe'))
        ..createSync(recursive: true)
        ..writeAsStringSync('other');

      await rig.installer.uninstall();

      expect(
        Directory(rig.layout.versionDirectory('0.1.0')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(rig.layout.root, '0.9.0', 'bin', 'yagurad.exe'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(rig.layout.root, '3.5.0', 'tool.exe')).existsSync(),
        isTrue,
      );
    });

    // ---- uninstall is best effort about files (G8-06) ----

    test('a_wrapper_that_is_locked_for_a_moment_is_deleted_on_retry', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      final held = File(rig.layout.winswExecutable).openSync();
      var released = false;
      addTearDown(() {
        if (!released) held.closeSync();
      });
      rig.onDelay = () {
        if (!released) held.closeSync();
        released = true;
      };

      await rig.installer.uninstall();

      expect(File(rig.layout.winswExecutable).existsSync(), isFalse);
      expect(rig.rootExists, isFalse);
      expect(rig.output, isNot(contains('kept')));
    });

    test(
      'a_wrapper_that_stays_locked_is_reported_and_the_purge_still_runs',
      () async {
        final rig = InstallerRig();
        await rig.installer.install();
        final held = File(rig.layout.winswExecutable).openSync();
        addTearDown(held.closeSync);

        await rig.installer.uninstall(purgeAccounts: true);

        expect(rig.control.services, isEmpty);
        expect(rig.output, contains('kept ${rig.layout.winswExecutable}'));
        expect(
          rig.purger.calls,
          1,
          reason: 'the purge does not wait for files',
        );
      },
    );

    test('a_version_directory_a_relay_holds_stays_marked', () async {
      final rig = InstallerRig();
      await rig.installer.install();
      // A relay of a running server executes this file.
      final relay = File(rig.layout.executable('0.1.0')).openSync();
      var closed = false;
      void release() {
        if (!closed) relay.closeSync();
        closed = true;
      }

      addTearDown(release);

      await rig.installer.uninstall();

      expect(
        rig.output,
        contains('kept ${rig.layout.versionDirectory('0.1.0')}'),
      );
      expect(rig.layout.ownsVersionDirectory('0.1.0'), isTrue);
      expect(File(rig.layout.executable('0.1.0')).existsSync(), isTrue);
      // The sweeper of another version deletes it once the relay is gone.
      release();
      final deleted = VersionSweeper(
        layout: rig.layout,
        currentVersion: '0.2.0',
      ).sweep(const []);
      expect(deleted, ['0.1.0']);
    });

    test(
      'files_left_by_an_interrupted_uninstall_can_still_be_purged',
      () async {
        final rig = InstallerRig();
        final data = Directory(p.join(rig.root.path, 'data'))..createSync();
        await rig.installer.install(dataDirectory: data.path);
        // The service is gone from the manager; its files and accounts remain.
        rig.control.services.remove(rig.serviceName);
        rig.control.calls.clear();

        final plain = await failureOf(rig.installer.uninstall);
        expect(plain.reason, 'service_not_installed');

        await rig.installer.uninstall(purgeAccounts: true);

        expect(rig.control.calls, isEmpty, reason: 'nothing to stop or remove');
        expect(rig.purger.dataDirectories, [data.path]);
        expect(rig.rootExists, isFalse);
      },
    );

    test('purge_with_nothing_left_at_all_is_service_not_installed', () async {
      final rig = InstallerRig();

      final e = await failureOf(
        () => rig.installer.uninstall(purgeAccounts: true),
      );

      expect(e.reason, 'service_not_installed');
      expect(rig.purger.calls, 0);
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
