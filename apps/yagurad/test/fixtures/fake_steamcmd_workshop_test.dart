import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/temp_support.dart';

final _script = p.absolute(
  'test',
  'fixtures',
  'fake_steamcmd',
  'fake_steamcmd.dart',
);

Future<(int, List<String>)> _run(
  List<String> args,
  Directory cwd, [
  Map<String, String> env = const {},
]) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    [_script, ...args],
    workingDirectory: cwd.path,
    environment: env,
    stdoutEncoding: utf8,
  );
  return (
    result.exitCode,
    const LineSplitter().convert(result.stdout as String),
  );
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('fake_steamcmd_ws_'));
  tearDown(() => deleteWithRetry(root));

  String content(String app, String id, [Directory? base]) =>
      p.join((base ?? root).path, 'steamapps', 'workshop', 'content', app, id);

  test('downloads several items into the working directory', () async {
    final (code, out) = await _run(
      [
        '+login',
        'anonymous',
        '+workshop_download_item',
        '107410',
        '111',
        '+workshop_download_item',
        '107410',
        '222',
        '+quit',
      ],
      root,
      {'FAKE_STEAMCMD_ITEM_222_BYTES': '50'},
    );
    expect(code, 0);
    expect(out, contains('Downloading item 111 ...'));
    expect(out, contains('Downloading item 222 ...'));
    expect(
      File(p.join(content('107410', '111'), 'meta.cpp')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(content('107410', '111'), 'keys', '111.bikey')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(content('107410', '222'), 'addons', '222.pbo')).lengthSync(),
      50,
    );
    final success = out.firstWhere(
      (l) => l.startsWith('Success. Downloaded item 222'),
    );
    expect(success, contains('"${content('107410', '222')}"'));
    expect(success, matches(RegExp(r'\(\d+ bytes\)$')));
  });

  test('+force_install_dir sets where the content goes', () async {
    final forced = Directory(p.join(root.path, 'forced'))..createSync();
    final cwd = Directory(p.join(root.path, 'cwd'))..createSync();
    await _run([
      '+force_install_dir',
      forced.path,
      '+login',
      'anonymous',
      '+workshop_download_item',
      '107410',
      '5',
      '+quit',
    ], cwd);
    expect(Directory(content('107410', '5', forced)).existsSync(), isTrue);
    expect(Directory(content('107410', '5', cwd)).existsSync(), isFalse);
  });

  test('per-item failures print error lines and write nothing', () async {
    final (_, out) = await _run(
      [
        '+workshop_download_item',
        '1',
        '10',
        '+workshop_download_item',
        '1',
        '11',
        '+workshop_download_item',
        '1',
        '12',
        '+workshop_download_item',
        '1',
        '13',
        '+quit',
      ],
      root,
      {
        'FAKE_STEAMCMD_ITEM_10': 'failure',
        'FAKE_STEAMCMD_ITEM_11': 'not_found',
        'FAKE_STEAMCMD_ITEM_12': 'timeout',
      },
    );
    expect(out, contains('ERROR! Download item 10 failed (Failure).'));
    expect(out, contains('ERROR! Download item 11 failed (File Not Found).'));
    expect(out, contains('ERROR! Download item 12 failed (Timeout).'));
    expect(out.any((l) => l.startsWith('Success. Downloaded item 13')), isTrue);
    expect(Directory(content('1', '10')).existsSync(), isFalse);
  });

  test('copies a source directory instead of generating files', () async {
    final src = Directory(p.join(root.path, 'src', 'nested'))
      ..createSync(recursive: true);
    File(p.join(src.path, 'a.txt')).writeAsStringSync('hello');
    await _run(
      ['+workshop_download_item', '1', '7', '+quit'],
      root,
      {'FAKE_STEAMCMD_ITEM_7_SOURCE': p.join(root.path, 'src')},
    );
    expect(
      File(p.join(content('1', '7'), 'nested', 'a.txt')).readAsStringSync(),
      'hello',
    );
    expect(File(p.join(content('1', '7'), 'meta.cpp')).existsSync(), isFalse);
  });

  test('plants a reparse point inside the item', () async {
    final target = Directory(p.join(root.path, 'outside'))..createSync();
    await _run(
      ['+workshop_download_item', '1', '8', '+quit'],
      root,
      {'FAKE_STEAMCMD_ITEM_8_JUNCTION': target.path},
    );
    expect(
      FileSystemEntity.typeSync(
        p.join(content('1', '8'), 'linked'),
        followLinks: false,
      ),
      FileSystemEntityType.link,
    );
  });

  test('progress lines and argv echo are opt-in', () async {
    final plain = await _run([
      '+workshop_download_item',
      '1',
      '9',
      '+quit',
    ], root);
    expect(
      plain.$2.any((l) => l.contains('progress:') || l.startsWith('Command')),
      isFalse,
    );
    final (_, out) = await _run(
      ['+workshop_download_item', '1', '9', '+quit'],
      root,
      {'FAKE_STEAMCMD_WORKSHOP_PROGRESS': '1', 'FAKE_STEAMCMD_ECHO_ARGV': '1'},
    );
    expect(out.first, startsWith('Command line: +workshop_download_item 1 9'));
    expect(out.where((l) => l.contains('progress:')), hasLength(3));
  });

  test('a stalled item hangs until killed', () async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      [_script, '+workshop_download_item', '1', '3', '+quit'],
      workingDirectory: root.path,
      environment: {'FAKE_STEAMCMD_ITEM_3': 'stall'},
    );
    final lines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    unawaited(process.stderr.drain<void>());
    await lines.firstWhere((l) => l == 'Downloading item 3 ...');
    var exited = false;
    unawaited(process.exitCode.then((_) => exited = true));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(exited, isFalse);
    process.kill();
    await process.exitCode;
  });

  group('login script', () {
    test('prints the matching rule and exits with its code', () async {
      final script = File(p.join(root.path, 'login.json'))
        ..writeAsStringSync(
          jsonEncode({
            'rules': [
              {
                'argc': 2,
                'user': 'bob',
                'lines': ['line one', 'line two'],
                'exit': 5,
              },
            ],
            'default': {
              'lines': ['fallback'],
              'exit': 9,
            },
          }),
        );
      final env = {'FAKE_STEAMCMD_LOGIN_SCRIPT': script.path};
      final miss = await _run(
        ['+login', 'bob', 'pw', 'code', '+quit'],
        root,
        env,
      );
      expect(miss.$1, 9, reason: 'argc 3 does not match, default applies');
      expect(miss.$2, ['fallback']);
      final exact = await _run(['+login', 'bob', 'pw', '+quit'], root, env);
      expect(exact.$1, 5);
      expect(exact.$2, ['line one', 'line two']);
    });

    test('without the variable nothing changes', () async {
      final (code, out) = await _run([
        '+login',
        'bob',
        'pw',
        '+workshop_download_item',
        '1',
        '2',
        '+quit',
      ], root);
      expect(code, 0);
      expect(out.any((l) => l.startsWith('Success.')), isTrue);
    });
  });
}
