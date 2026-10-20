import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/config/config_binder.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/files/files.dart';

import '../support/temp_support.dart';

Directory makeRoot() {
  final dir = createCanonicalTempSync('yagura_atomic_test_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

BoundKey maxPlayers(String file, int value) => BoundKey(
  id: 'bindings[0]',
  file: file,
  format: 'dayz-cfg',
  key: 'maxPlayers',
  setting: 'maxPlayers',
  value: () => value,
);

/// Stands for a daemon killed in the middle of an apply.
class _Killed implements Exception {}

void main() {
  test('interrupted_apply', () async {
    final root = makeRoot();
    const oldA = 'hostname = "a";\nmaxPlayers = 10;\n';
    const oldB = 'hostname = "b";\nmaxPlayers = 10;\n';
    final a = File(p.join(root.path, 'a.cfg'))..writeAsStringSync(oldA);
    final b = File(p.join(root.path, 'b.cfg'))..writeAsStringSync(oldB);

    // Killed before anything was moved, then after the first file was.
    for (final killAt in [1, 2]) {
      var renames = 0;
      final binder = ConfigBinder(
        InstanceFs(root.path),
        rename: (temporary, target) {
          if (++renames == killAt) throw _Killed();
          File(p.join(root.path, temporary))
              .renameSync(p.join(root.path, target));
        },
      );

      await expectLater(
        binder.apply(bindings: [maxPlayers('a.cfg', 40), maxPlayers('b.cfg', 40)]),
        throwsA(anything),
      );

      expect(a.readAsStringSync(), oldA, reason: 'killed at rename $killAt');
      expect(b.readAsStringSync(), oldB, reason: 'killed at rename $killAt');
      expect(
        root.listSync().map((e) => p.basename(e.path)).toSet(),
        {'a.cfg', 'b.cfg'},
        reason: 'no temporary file is left behind',
      );
    }

    // The same pass without a kill leaves the new version, whole.
    await ConfigBinder(InstanceFs(root.path)).apply(
      bindings: [maxPlayers('a.cfg', 40), maxPlayers('b.cfg', 40)],
    );
    expect(a.readAsStringSync(), 'hostname = "a";\nmaxPlayers = 40;\n');
    expect(b.readAsStringSync(), 'hostname = "b";\nmaxPlayers = 40;\n');
  });

  test('file_locked_by_a_running_process', () async {
    final root = makeRoot();
    const original = 'hostname = "a";\nmaxPlayers = 10;\n';
    final file = File(p.join(root.path, 'serverDZ.cfg'))
      ..writeAsStringSync(original);
    final waits = <Duration>[];
    final binder = ConfigBinder(
      InstanceFs(root.path),
      // Time does not pass: the binder only has to ask for it.
      delay: (duration) async => waits.add(duration),
    );
    final holder = file.openSync(mode: FileMode.append)
      ..lockSync(FileLock.exclusive);
    addTearDown(() {
      try {
        holder.closeSync();
      } on FileSystemException {
        // Already closed.
      }
    });

    await expectLater(
      binder.apply(bindings: [maxPlayers('serverDZ.cfg', 40)]),
      throwsA(
        isA<YaguraException>()
            .having((e) => e.reason, 'reason', 'file_locked')
            .having((e) => e.message, 'message', contains('serverDZ.cfg')),
      ),
    );

    expect(waits, everyElement(const Duration(milliseconds: 250)));
    expect(
      waits.fold(Duration.zero, (sum, wait) => sum + wait),
      const Duration(seconds: 5),
      reason: 'it retried for 5 s',
    );
    holder.closeSync();
    expect(file.readAsStringSync(), original);
    expect(root.listSync().map((e) => p.basename(e.path)), ['serverDZ.cfg']);
  }, tags: ['windows'], skip: Platform.isWindows ? null : 'needs Windows file locks');
}
