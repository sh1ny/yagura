import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/files/confined_fs.dart';
import 'package:yagurad/src/files/confined_fs_portable.dart';
import 'package:yagurad/src/files/instance_fs.dart';

import '../support/temp_support.dart';

Directory makeRoot() {
  final dir = createCanonicalTempSync('yagura_confined_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

Matcher failsWith(String reason) =>
    throwsA(isA<YaguraException>().having((e) => e.reason, 'reason', reason));

/// Plants a link at [link]; null when the account cannot create one.
bool tryLink(String link, String target) {
  try {
    Link(link).createSync(target);
    return true;
  } on FileSystemException {
    return false;
  }
}

void main() {
  // The platform's own backend, and the portable one (which is what the
  // Linux host uses until M5).
  final backends = <String, ConfinedFs Function(String)>{
    'platform': InstanceFs.new,
    if (Platform.isWindows)
      'portable': (root) => ConfinedFs.withBackend(
        root,
        PortableConfinedBackend(p.normalize(p.absolute(root))),
      ),
  };

  for (final MapEntry(key: name, value: open) in backends.entries) {
    group('ConfinedFs ($name)', () {
      test('refuses paths that leave the root', () {
        final fs = open(makeRoot().path);
        for (final path in [
          '..',
          '../x',
          'a/../../x',
          r'a\..\..\x',
          Platform.isWindows ? r'C:\Windows\win.ini' : '/etc/passwd',
          '/abs',
          'file.txt:stream',
          'nul\u0000.txt',
        ]) {
          expect(
            () => fs.stat(path),
            failsWith('sandbox_violation'),
            reason: path,
          );
        }
      });

      test('reads, lists and writes plain files', () {
        final root = makeRoot();
        final fs = open(root.path);

        fs.createDirectory('a/b');
        fs.writeBytes('a/b/one.txt', [1, 2, 3]);
        fs.writeAtomic('a/two.txt', [4, 5]);

        expect(fs.readBytes('a/b/one.txt'), [1, 2, 3]);
        expect(fs.readBytes(r'a\two.txt'), [4, 5]);
        expect(fs.stat('a/b/one.txt')!.size, 3);
        expect(fs.stat('a/b')!.isDirectory, isTrue);
        expect(fs.stat('missing/deep.txt'), isNull);
        expect(fs.stat('')!.isDirectory, isTrue);
        expect(fs.list('a').map((e) => e.name).toSet(), {'b', 'two.txt'});
        expect(fs.treeSize('a'), 5);
        // Overwriting truncates.
        fs.writeBytes('a/b/one.txt', [9]);
        expect(fs.readBytes('a/b/one.txt'), [9]);
        // Nothing is left over from the atomic write.
        expect(fs.list('a').map((e) => e.name).toSet(), {'b', 'two.txt'});
        expect(File(p.join(root.path, 'a', 'two.txt')).readAsBytesSync(), [
          4,
          5,
        ]);
      });

      test('reads a range and refuses a file over the limit', () {
        final fs = open(makeRoot().path);
        fs.writeBytes('big.bin', List.filled(1000, 7));

        final reader = fs.openRead('big.bin');
        expect(reader.length, 1000);
        expect(reader.readAt(990, 100), List.filled(10, 7));
        expect(reader.readAt(1000, 10), isEmpty);
        reader.close();
        expect(
          () => fs.readBytes('big.bin', maxBytes: 999),
          failsWith('file_too_large'),
        );
        expect(fs.readBytes('big.bin', maxBytes: 1000), hasLength(1000));
      });

      test('fails exclusively created files that exist', () {
        final fs = open(makeRoot().path);
        fs.writeBytes('x.txt', [1]);
        expect(
          () => fs.openWrite('x.txt', exclusive: true),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('renames over a file and deletes', () {
        final fs = open(makeRoot().path);
        fs.writeBytes('a.txt', [1]);
        fs.writeBytes('b.txt', [2]);

        fs.rename('a.txt', 'b.txt');

        expect(fs.exists('a.txt'), isFalse);
        expect(fs.readBytes('b.txt'), [1]);
        fs.delete('b.txt');
        expect(fs.exists('b.txt'), isFalse);
        expect(() => fs.delete('b.txt'), throwsA(isA<FileSystemException>()));
        expect(
          () => fs.readBytes('b.txt'),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('deletes a tree, read-only files included, and the root', () {
        final root = makeRoot();
        final fs = open(root.path);
        fs.createDirectory('t/a/b');
        fs.writeBytes('t/a/one.txt', [1]);
        fs.writeBytes('t/a/b/two.txt', [2]);
        fs.writeBytes('t/ro.txt', [3]);
        File(p.join(root.path, 't', 'ro.txt'))
            .setLastModifiedSync(DateTime.now());
        if (Platform.isWindows && name == 'platform') {
          Process.runSync('attrib', ['+R', p.join(root.path, 't', 'ro.txt')]);
        }

        fs.deleteTree('missing');
        fs.deleteTree('t');
        expect(fs.exists('t'), isFalse);
        fs.deleteTree('');
        expect(root.existsSync(), isFalse);
      });

      test('copies a tree out and back in', () {
        final root = makeRoot();
        final elsewhere = makeRoot();
        final fs = open(root.path);
        fs.createDirectory('save/chars');
        fs.writeBytes('save/world.db', [1, 2, 3]);
        fs.writeBytes('save/chars/one', [4]);

        final bytes = fs.copyOut('save', p.join(elsewhere.path, 'copy'));

        expect(bytes, 4);
        expect(
          File(p.join(elsewhere.path, 'copy', 'chars', 'one'))
              .readAsBytesSync(),
          [4],
        );
        fs.deleteTree('save');
        expect(fs.copyIn(p.join(elsewhere.path, 'copy'), 'restored'), 4);
        expect(fs.readBytes('restored/world.db'), [1, 2, 3]);
        expect(
          () => fs.copyOut('nothing', elsewhere.path),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('relative turns an absolute path inside the root into one', () {
        final root = makeRoot();
        final fs = open(root.path);
        expect(
          fs.relative(p.join(root.path, 'a', 'b.txt')),
          p.join('a', 'b.txt'),
        );
        expect(fs.relative(root.path), '');
        expect(
          () => fs.relative(p.dirname(root.path)),
          failsWith('sandbox_violation'),
        );
      });

      test('a missing root has no entries and fails writes', () {
        final fs = open(p.join(makeRoot().path, 'gone'));
        expect(fs.stat('a'), isNull);
        expect(fs.stat(''), isNull);
        fs.deleteTree('');
        expect(
          () => fs.writeBytes('a', [1]),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('refuses a link in a path, and reports one in a listing', () {
        final root = makeRoot();
        final outside = makeRoot();
        File(p.join(outside.path, 'secret.txt')).writeAsStringSync('secret');
        final fs = open(root.path);
        fs.createDirectory('real');
        if (!tryLink(p.join(root.path, 'cfg'), outside.path)) {
          markTestSkipped('this account cannot create links');
          return;
        }

        expect(
          () => fs.readBytes('cfg/secret.txt'),
          failsWith('sandbox_violation'),
        );
        expect(() => fs.stat('cfg'), failsWith('sandbox_violation'));
        expect(
          () => fs.writeBytes('cfg/new.txt', [1]),
          failsWith('sandbox_violation'),
        );
        expect(
          () => fs.createDirectory('cfg/sub'),
          failsWith('sandbox_violation'),
        );
        expect(() => fs.list('cfg'), failsWith('sandbox_violation'));
        expect(() => fs.treeSize(''), failsWith('sandbox_violation'));
        expect(
          () => fs.copyOut('', p.join(makeRoot().path, 'copy')),
          failsWith('sandbox_violation'),
        );
        final listed = {for (final e in fs.list('')) e.name: e.isLink};
        expect(listed, {'real': false, 'cfg': true});
        expect(outside.listSync().map((e) => p.basename(e.path)), [
          'secret.txt',
        ]);

        // Deleting removes the link and nothing behind it.
        fs.deleteTree('cfg');
        expect(fs.stat('cfg'), isNull);
        expect(
          File(p.join(outside.path, 'secret.txt')).readAsStringSync(),
          'secret',
        );
      });

      test('a root that is a link is refused', () {
        final base = makeRoot();
        final target = Directory(p.join(base.path, 'target'))..createSync();
        final link = p.join(base.path, 'link');
        if (!tryLink(link, target.path)) {
          markTestSkipped('this account cannot create links');
          return;
        }
        final fs = open(link);
        expect(() => fs.stat(''), failsWith('sandbox_violation'));
        expect(() => fs.writeBytes('a', [1]), failsWith('sandbox_violation'));
        expect(target.listSync(), isEmpty);
      });
    });
  }

  test('a root spelled with 8.3 short names is accepted', () {
    // The GitHub runner's temp directory is `C:\Users\RUNNER~1\...`.
    final root = Directory(p.join(makeRoot().path, 'a long directory name'))
      ..createSync();
    final short = Process.runSync('powershell', [
      '-NoProfile',
      '-Command',
      '(New-Object -ComObject Scripting.FileSystemObject)'
          ".GetFolder('${root.path}').ShortPath",
    ]).stdout.toString().trim();
    if (p.equals(short, root.path)) {
      markTestSkipped('8.3 names are disabled on this volume');
      return;
    }
    final fs = InstanceFs(short);
    fs.writeBytes('a.txt', [1]);
    expect(File(p.join(root.path, 'a.txt')).readAsBytesSync(), [1]);
    expect(fs.readBytes('a.txt'), [1]);
  }, testOn: 'windows');
}
