import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/logs/logs.dart';

import '../support/daemon_support.dart';
import 'log_test_support.dart';
import '../support/temp_support.dart';

/// Valheim with its log source on the server's standard output.
String stdoutValheim(TestEnv env) => env.installValheim(
  from:
      '    path: "logs/server.log"\n    encoding: utf-8\n    rotation: fixed\n',
  to: '    stdout: true\n    encoding: utf-8\n',
);

void main() {
  test('stdout_survives_daemon_restart', () async {
    final env = TestEnv();
    stdoutValheim(env);
    final first = await env.start();
    final instance = await createInstalled(first);

    // The relay owns the pipes and writes the capture; here a writer plays
    // it, independently of the daemon, for the whole test.
    final writer = CaptureWriter.open(
      CaptureWriter.directoryFor(instance.directory),
    );
    addTearDown(writer.close);
    writer.write('boot 1\nboot 2\n'.codeUnits);
    await first.logs.pollNow(instance.id);
    expect(
      first.logs.backlog(instance.id, lines: 10).entries.map((e) => e.text),
      ['boot 1', 'boot 2'],
    );

    // The daemon goes down; the server keeps writing.
    await env.kill(first);
    writer.write('while down 1\nwhile down 2\n'.codeUnits);

    // After re-attach the clients get the lines written in the meantime.
    final second = await env.start();
    final followed = Collector(second.logs.follow(instance.id));
    await second.logs.pollNow(instance.id);
    await followed.settle();

    expect(followed.texts, ['while down 1', 'while down 2']);
    expect(
      second.logs.backlog(instance.id, lines: 10).entries.map((e) => e.text),
      ['boot 1', 'boot 2', 'while down 1', 'while down 2'],
    );
    expect(second.logs.sources(instance.id).single.kind, LogSourceKind.stdout);
  });

  test('capture_file_rotation', () async {
    final rig = LogRig();
    final directory = p.join(rig.dir.path, 'capture');
    final writer = CaptureWriter.open(directory, fileBytes: 1024, fileCount: 5);
    addTearDown(writer.close);
    await rig.attach([
      LogSourceSpec.stdout(
        name: 'stdout',
        encoding: LogEncoding.utf8,
        directory: directory,
      ),
    ]);
    final followed = Collector(rig.hub.follow(rigInstance));

    // 300 lines of 40 bytes cross the 1 KiB limit about 12 times; the
    // writer is handed arbitrary slices, so slices end mid-line.
    final lines = [
      for (var i = 0; i < 300; i++)
        'out ${i.toString().padLeft(4, '0')} ${'#' * 28}',
    ];
    final bytes = '${lines.join('\n')}\n'.codeUnits;
    for (var at = 0; at < bytes.length; at += 97) {
      writer.write(bytes.sublist(at, (at + 97).clamp(0, bytes.length)));
      if (at % 485 < 97) await rig.poll();
    }
    await rig.poll();
    await followed.settle();

    // At most 5 files are kept, and no line is split across a rotation: every
    // kept file holds only whole lines.
    final files = Directory(directory).listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(files.length, lessThanOrEqualTo(5));
    expect(files.length, greaterThan(1));
    final kept = <String>[];
    for (final file in files) {
      final text = file.readAsStringSync();
      expect(text, endsWith('\n'), reason: p.basename(file.path));
      kept.addAll(text.trimRight().split('\n'));
    }
    expect(kept.every(lines.contains), isTrue);
    expect(kept, lines.sublist(lines.length - kept.length));
    expect(files.first.lengthSync(), greaterThanOrEqualTo(1024));

    // The stream carries every line once, whole and in order.
    expect(followed.texts, lines);
  });

  test('the_capture_writer_rotates_at_10_mib_by_default', () {
    final dir = createCanonicalTempSync('yagurad_capture_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final writer = CaptureWriter.open(dir.path);
    addTearDown(writer.close);
    // 10,241 lines of 1 KiB in one write: the first 10,240 fill a file.
    final bytes = Uint8List(10241 * 1024)..fillRange(0, 10241 * 1024, 0x61);
    for (var i = 1023; i < bytes.length; i += 1024) {
      bytes[i] = 0x0A;
    }
    writer.write(bytes);
    final files = dir.listSync().whereType<File>().toList();
    expect(files, hasLength(2));
    expect(files.map((f) => f.lengthSync()).toList()..sort(), [
      1024,
      10 * 1024 * 1024,
    ]);
  });

  test('a_new_writer_continues_in_the_instance_capture_directory', () {
    final dir = createCanonicalTempSync('yagurad_capture_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final directory = CaptureWriter.directoryFor(dir.path);
    expect(p.isWithin(dir.path, directory), isTrue);
    expect(p.split(p.relative(directory, from: dir.path)), ['.yagura', 'logs']);

    CaptureWriter.open(directory)
      ..write('one\ntw'.codeUnits)
      ..close();
    // A restarted writer finishes the line the old one left open.
    CaptureWriter.open(directory)
      ..write('o\nthree\n'.codeUnits)
      ..close();
    final text = Directory(directory)
        .listSync()
        .whereType<File>()
        .map((f) => f.readAsStringSync())
        .join();
    expect(text, 'one\ntwo\nthree\n');
  });
}
