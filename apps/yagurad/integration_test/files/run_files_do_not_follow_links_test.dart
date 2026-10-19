@Tags(['windows'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/files/files.dart';
import 'package:yagurad/src/process/process_host.dart';
import 'package:yagurad/src/process/run_files.dart';

import '../../test/support/temp_support.dart';

// The daemon writes `launch.json` and `cancel.json` into the run directory
// of an instance. A junction planted by the server in place of `.yagura`,
// `.yagura/run` or the run directory must stop the write (design D8).

late Directory temp;

Future<void> junction(String link, String target) async {
  Directory(p.dirname(link)).createSync(recursive: true);
  final made = await Process.run('cmd', ['/c', 'mklink', '/J', link, target]);
  expect(made.exitCode, 0, reason: '${made.stdout}${made.stderr}');
}

Map<String, String> contentsOf(Directory directory) => {
  for (final e in directory.listSync(recursive: true, followLinks: false))
    p.relative(e.path, from: directory.path): e is File
        ? e.readAsStringSync()
        : '<directory>',
};

LaunchRequest launchIn(String instance, String runDirectory) => LaunchRequest(
  instanceId: 'i1',
  runId: 'run1',
  executable: r'C:\server.exe',
  args: const [],
  env: const {},
  workingDirectory: instance,
  instanceDirectory: instance,
  runDirectory: runDirectory,
);

void main() {
  setUp(() {
    temp = createCanonicalTempSync('yagura_runfiles_');
    addTearDown(() {
      // Junctions first: deleting the tree must never reach a target.
      for (final e in temp.listSync(recursive: true, followLinks: false)) {
        if (e is Link) e.deleteSync();
      }
      temp.deleteSync(recursive: true);
    });
  });

  // Which part of the run directory path the server replaced.
  for (final replaced in ['.yagura', '.yagura/run', '.yagura/run/run1']) {
    test('run_files_junction_in_place_of_$replaced', () async {
      final instance = Directory(p.join(temp.path, 'instance'))..createSync();
      final target = Directory(p.join(temp.path, 'target'))..createSync();
      File(p.join(target.path, 'keep.txt')).writeAsStringSync('keep');
      // The levels above the replaced one are real directories.
      final parts = p.split(replaced);
      var parent = instance.path;
      for (final part in parts.take(parts.length - 1)) {
        parent = p.join(parent, part);
        Directory(parent).createSync();
      }
      await junction(p.join(parent, parts.last), target.path);
      final before = contentsOf(target);

      final fs = InstanceFs(instance.path);
      final runDirectory = RunFiles.directoryFor(instance.path, 'run1');
      final files = RunFiles(runDirectory, fs: fs);

      expect(
        () => files.writeLaunch(launchIn(instance.path, runDirectory)),
        throwsA(
          isA<YaguraException>().having(
            (e) => e.reason,
            'reason',
            'sandbox_violation',
          ),
        ),
      );
      expect(
        files.writeCancel,
        throwsA(
          isA<YaguraException>().having(
            (e) => e.reason,
            'reason',
            'sandbox_violation',
          ),
        ),
      );
      expect(contentsOf(target), before);
    });
  }

  test('run_files_plain_directory_is_written', () {
    final instance = Directory(p.join(temp.path, 'instance'))..createSync();
    final runDirectory = RunFiles.directoryFor(instance.path, 'run1');
    final files = RunFiles(runDirectory, fs: InstanceFs(instance.path));

    files.writeLaunch(launchIn(instance.path, runDirectory));
    files.writeCancel();

    expect(files.readLaunch()?.executable, r'C:\server.exe');
    expect(files.isCancelled, isTrue);
    expect(
      Directory(runDirectory).listSync().map((e) => p.basename(e.path)),
      unorderedEquals(['launch.json', 'cancel.json']),
    );
  });
}
