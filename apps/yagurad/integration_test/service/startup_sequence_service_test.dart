@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../test/support/account_support.dart';
import '../../test/support/elevated_support.dart';
import '../../test/support/process_support.dart';

// host-service, "Startup sequence" in service mode (design D6): the data
// directory is opened without following links, owned by Administrators and
// protected before the database opens, then walked. These rows run the daemon
// as LocalSystem (a scheduled task) over data directories that earlier
// daemons, a standard user or a link made, and look at the ACLs and the log.
// They change the machine and so run only in the manual `elevated` workflow.

/// A junction at [link] to [target].
Future<void> _junction(String link, String target) async {
  final made = await runCommand('cmd', ['/c', 'mklink', '/J', link, target]);
  expect(made.exitCode, 0, reason: '${made.stdout}${made.stderr}');
}

/// No entry of [sddl] gives Users, Everyone or Authenticated Users anything.
void _expectNoBroadAccess(String sddl, String reason) {
  for (final alias in ['BU', 'WD', 'AU']) {
    expect(sddl, isNot(contains(';;;$alias)')), reason: '$alias on $reason');
  }
}

void main() {
  test(
    'data_directory_created_by_an_earlier_daemon',
    tags: ['elevated'],
    () async {
      final tools = await processTools();
      late String file;
      late String nested;

      // What a development daemon left: a directory the creating user's ACL
      // (inherited from the temp folder) covers, with files below it.
      final daemon = await SystemDaemon.start(
        tools,
        prepare: (data) async {
          Directory(p.join(data, 'instances', 'old'))
              .createSync(recursive: true);
          file = p.join(data, 'settings.txt');
          File(file).writeAsStringSync('left by an earlier daemon');
          nested = p.join(data, 'instances', 'old', 'save.txt');
          File(nested).writeAsStringSync('save');
        },
      );
      final data = p.join(daemon.dataDir.path, 'data');

      final root = await sddlOf(data);
      expect(root, startsWith('O:BA'));
      expect(root, contains('D:P'));
      _expectNoBroadAccess(root, data);
      // Files that were already there carry the inherited entries, not the
      // user's.
      for (final path in [file, p.join(data, 'yagura.db')]) {
        final sddl = await sddlOf(path);
        _expectNoBroadAccess(sddl, path);
      }
      // The instances folder is not entered: its DACL is explicit and the
      // folder below it was left to the instance migration.
      expect(await sddlOf(p.join(data, 'instances')), startsWith('O:BA'));
    },
  );

  test('data_directory_is_a_link', tags: ['elevated'], () async {
    final tools = await processTools();
    final target = Directory.systemTemp.createTempSync('yagurad_target_');
    addTearDown(() {
      try {
        target.deleteSync(recursive: true);
      } on FileSystemException {
        // Left to the temp cleaner.
      }
    });

    final result = await SystemDaemon.runUntilExit(
      tools,
      prepare: (data) async {
        Directory(p.dirname(data)).createSync(recursive: true);
        await _junction(data, target.path);
      },
    );

    expect(result.log, contains('data_dir_not_protected'));
    expect(result.log, contains(p.join(result.dataDir.path, 'data')));
    // Nothing was written through the link.
    expect(target.listSync(), isEmpty);
  });

  test(
    'layout_marker_planted_by_a_standard_user',
    tags: ['elevated'],
    () async {
      final tools = await processTools();
      final user = await StandardUser.create();

      final daemon = await SystemDaemon.start(
        tools,
        prepare: (data) async {
          Directory(data).createSync(recursive: true);
          // Anyone may write here, as in a shared temp folder.
          await runCommand('icacls', [data, '/grant', '*S-1-1-0:(OI)(CI)F']);
          // `cmd` inside quotes: the redirection is the inner command's.
          final planted = await user.run('cmd.exe', [
            '/c',
            '"echo 1 >${p.join(data, 'acl-layout')} & '
                'echo x >${p.join(data, 'planted.txt')}"',
          ]);
          expect(planted.exitCode, 0, reason: '${planted.out}${planted.err}');
        },
      );
      final data = p.join(daemon.dataDir.path, 'data');

      // The marker is owned by the user, so it counts for nothing: the walk
      // ran and the files the user made lost the Everyone entry.
      final planted = await sddlOf(p.join(data, 'planted.txt'));
      _expectNoBroadAccess(planted, 'planted.txt');
      final database = await sddlOf(p.join(data, 'yagura.db'));
      _expectNoBroadAccess(database, 'yagura.db');
      expect(await sddlOf(data), startsWith('O:BA'));
    },
  );

  test(
    'link_in_the_data_directory_at_first_service_start',
    tags: ['elevated'],
    () async {
      final tools = await processTools();
      final target = Directory.systemTemp.createTempSync('yagurad_target_');
      addTearDown(() {
        try {
          target.deleteSync(recursive: true);
        } on FileSystemException {
          // Left to the temp cleaner.
        }
      });
      File(p.join(target.path, 'keep.txt')).writeAsStringSync('keep');
      final before = await sddlOf(target.path);

      final result = await SystemDaemon.runUntilExit(
        tools,
        prepare: (data) async {
          Directory(data).createSync(recursive: true);
          await _junction(p.join(data, 'snapshots'), target.path);
        },
      );

      expect(result.log, contains('data_dir_not_protected'));
      expect(
        result.log,
        contains(p.join(result.dataDir.path, 'data', 'snapshots')),
      );
      // The database was not opened and the target kept its ACL.
      expect(
        File(p.join(result.dataDir.path, 'data', 'yagura.db')).existsSync(),
        isFalse,
      );
      expect(await sddlOf(target.path), before);
      expect(File(p.join(target.path, 'keep.txt')).existsSync(), isTrue);
    },
  );
}
