import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/files/files.dart';

Directory makeRoot() {
  final dir = Directory.systemTemp.createTempSync('yagura_writer_test_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

File put(Directory root, String relative, String content) {
  final file = File(p.join(root.path, relative));
  file.parent.createSync(recursive: true);
  return file..writeAsStringSync(content);
}

Matcher failsWith(String reason) =>
    throwsA(isA<YaguraException>().having((e) => e.reason, 'reason', reason));

FileEdit json(String path, Object? patch) =>
    FileEdit(path: path, format: 'json', patch: patch);

void main() {
  group('FileEditWriter', () {
    test('patches a file keeping key order and formatting', () {
      final root = makeRoot();
      const original = '{\n  "b": 1,\n  "a": {"x": 1, "y": 2},\n  "c": 3\n}\n';
      final file = put(root, 'cfg.json', original);

      FileEditWriter(InstanceRoot(root.path)).apply([
        json('cfg.json', {
          'a': {'y': 20},
          'd': true,
        }),
      ]);

      expect(
        file.readAsStringSync(),
        '{\n  "b": 1,\n  "a": {"x": 1, "y": 20},\n  "c": 3,\n  "d": true\n}\n',
      );
    });

    test('creates a missing file, and its directory, pretty printed', () {
      final root = makeRoot();
      FileEditWriter(InstanceRoot(root.path)).apply([
        json('new/dir/cfg.json', {
          'a': 1,
          'b': {'c': 2},
        }),
      ]);
      final content = File(p.join(root.path, 'new', 'dir', 'cfg.json'))
          .readAsStringSync();
      expect(content, '{\n  "a": 1,\n  "b": {\n    "c": 2\n  }\n}\n');
    });

    test('applies several edits of one file in order', () {
      final root = makeRoot();
      final file = put(root, 'cfg.json', '{"a": 1}');
      FileEditWriter(InstanceRoot(root.path)).apply([
        json('cfg.json', {'b': 2}),
        json('./cfg.json', {'a': null, 'c': 3}),
      ]);
      expect(jsonDecode(file.readAsStringSync()), {'b': 2, 'c': 3});
    });

    test('leaves no temporary files behind', () {
      final root = makeRoot();
      put(root, 'cfg.json', '{}');
      FileEditWriter(InstanceRoot(root.path)).apply([
        json('cfg.json', {'a': 1}),
      ]);
      expect(root.listSync().map((e) => p.basename(e.path)), ['cfg.json']);
    });

    test('refuses a path outside the root and changes nothing', () {
      final root = makeRoot();
      final file = put(root, 'cfg.json', '{"a": 1}');
      expect(
        () => FileEditWriter(InstanceRoot(root.path)).apply([
          json('cfg.json', {'a': 2}),
          json('../escape.json', {'x': 1}),
        ]),
        failsWith('sandbox_violation'),
      );
      expect(file.readAsStringSync(), '{"a": 1}');
      expect(File(p.join(root.parent.path, 'escape.json')).existsSync(), false);
    });

    test('refuses a format other than json and changes nothing', () {
      final root = makeRoot();
      final file = put(root, 'cfg.json', '{"a": 1}');
      expect(
        () => FileEditWriter(InstanceRoot(root.path)).apply([
          json('cfg.json', {'a': 2}),
          const FileEdit(path: 'server.ini', format: 'ini', patch: {'a': 1}),
        ]),
        throwsA(
          isA<YaguraException>()
              .having((e) => e.reason, 'reason', 'unsupported_in_this_version')
              .having((e) => e.message, 'message', contains('server.ini'))
              .having((e) => e.message, 'message', contains('ini')),
        ),
      );
      expect(file.readAsStringSync(), '{"a": 1}');
      expect(File(p.join(root.path, 'server.ini')).existsSync(), false);
    });

    test('applies all edits or none when a later file is not valid JSON', () {
      final root = makeRoot();
      final first = put(root, 'a.json', '{"a": 1}');
      final second = put(root, 'b.json', '{broken');
      expect(
        () => FileEditWriter(InstanceRoot(root.path)).apply([
          json('a.json', {'a': 2}),
          json('b.json', {'b': 1}),
        ]),
        failsWith('config_parse_error'),
      );
      expect(first.readAsStringSync(), '{"a": 1}');
      expect(second.readAsStringSync(), '{broken');
    });

    test('restores replaced files when a later rename fails', () {
      final root = makeRoot();
      final first = put(root, 'a.json', '{"a": 1}');
      final second = put(root, 'b.json', '{"b": 1}');
      var renames = 0;
      final writer = FileEditWriter(
        InstanceRoot(root.path),
        rename: (temporary, target) {
          if (++renames == 2) throw const FileSystemException('locked');
          File(temporary).renameSync(target);
        },
      );
      expect(
        () => writer.apply([
          json('a.json', {'a': 2}),
          json('b.json', {'b': 2}),
        ]),
        failsWith('internal_error'),
      );
      expect(first.readAsStringSync(), '{"a": 1}');
      expect(second.readAsStringSync(), '{"b": 1}');
      expect(root.listSync().map((e) => p.basename(e.path)).toSet(), {
        'a.json',
        'b.json',
      }, reason: 'temporary files are cleaned up');
    });

    test('refuses an edit through a link to outside the root', () {
      final root = makeRoot();
      final outside = makeRoot();
      final target = put(outside, 'server.json', '{"a": 1}');
      final link = p.join(root.path, 'cfg');
      try {
        Link(link).createSync(outside.path);
      } on FileSystemException {
        markTestSkipped('this account cannot create links');
        return;
      }
      expect(
        () => FileEditWriter(InstanceRoot(root.path)).apply([
          json('cfg/server.json', {'a': 2}),
        ]),
        throwsA(
          isA<YaguraException>()
              .having((e) => e.reason, 'reason', 'sandbox_violation')
              .having((e) => e.message, 'message', contains('cfg/server.json')),
        ),
      );
      expect(target.readAsStringSync(), '{"a": 1}');
    });
  });

  group('InstanceRoot', () {
    test('resolves paths inside the root, existing or not', () {
      final root = makeRoot();
      put(root, 'keys/a.bikey', 'x');
      final instance = InstanceRoot(root.path);
      expect(instance.resolve('keys/a.bikey'), endsWith('a.bikey'));
      expect(instance.resolve('keys/missing/deep.json'), contains('missing'));
      expect(instance.resolve('.'), instance.resolvedPath);
      expect(instance.resolve(''), instance.resolvedPath);
    });

    test('refuses parent escapes and absolute paths elsewhere', () {
      final root = makeRoot();
      final instance = InstanceRoot(root.path);
      for (final path in [
        '..',
        '../x',
        'a/../../x',
        Platform.isWindows ? r'C:\Windows\win.ini' : '/etc/passwd',
      ]) {
        expect(() => instance.resolve(path), failsWith('sandbox_violation'));
      }
    });

    test('accepts an absolute path that lies inside the root', () {
      final root = makeRoot();
      final file = put(root, 'a.txt', 'x');
      final instance = InstanceRoot(root.path);
      expect(
        p.equals(instance.resolve(file.path), file.resolveSymbolicLinksSync()),
        isTrue,
      );
    });
  });
}
