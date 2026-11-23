@Tags(['windows'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/config/config_binder.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/files/files.dart';
import 'package:yagurad/src/hooks/hooks.dart';
import 'package:yagurad/src/platform/disk_space.dart';
import 'package:yagurad/src/snapshots/snapshots.dart';

import '../../test/hooks/hook_test_support.dart';
import '../../test/support/temp_support.dart';

// Real NTFS junctions and symbolic links, planted the way a game server
// would plant them, against the daemon's file operations (design D8).
//
// Junctions need no privilege. A symbolic link needs the right to create one
// (an elevated account or Developer Mode); where the account lacks it the
// symbolic-link variant of a test is skipped with a message, and the
// junction variant has run.

late Directory temp;
final _planted = <String>[];

/// Plants a junction (kind `junction`) or a symbolic link (kind `symlink`) at
/// [link] pointing to the directory [target]. False when the account cannot
/// create that kind of link.
Future<bool> plant(String kind, String link, String target) async {
  Directory(p.dirname(link)).createSync(recursive: true);
  if (kind == 'junction') {
    final made = await Process.run('cmd', ['/c', 'mklink', '/J', link, target]);
    expect(made.exitCode, 0, reason: '${made.stdout}${made.stderr}');
  } else {
    try {
      Link(link).createSync(target);
    } on FileSystemException {
      return false;
    }
  }
  _planted.add(link);
  return true;
}

/// Removes [link] itself; never what it points to.
void unplant(String link) {
  if (FileSystemEntity.typeSync(link, followLinks: false) ==
      FileSystemEntityType.link) {
    Link(link).deleteSync();
  }
  _planted.remove(link);
}

/// Every file under [directory] with its content, to compare before and after.
Map<String, String> contentsOf(String directory) => {
  for (final entity in Directory(
    directory,
  ).listSync(recursive: true, followLinks: false))
    p.relative(entity.path, from: directory): entity is File
        ? entity.readAsStringSync()
        : '<directory>',
};

Directory makeDirectory(String name, [Map<String, String> files = const {}]) {
  final directory = Directory(p.join(temp.path, name))
    ..createSync(recursive: true);
  for (final MapEntry(:key, :value) in files.entries) {
    final file = File(p.join(directory.path, key));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(value);
  }
  return directory;
}

Matcher sandboxViolation(String naming) => throwsA(
  isA<YaguraException>()
      .having((e) => e.reason, 'reason', 'sandbox_violation')
      .having((e) => e.message, 'message', contains(naming)),
);

const _linkKinds = ['junction', 'symlink'];

const _noSymlinks =
    'this account cannot create symbolic links; the junction case ran';

DirectorySnapshotter snapshotterIn(String root) => DirectorySnapshotter(
  root: root,
  diskSpace: (_) async => const DiskSpace(volume: r'V:\', freeBytes: 1 << 40),
);

void main() {
  setUp(() {
    temp = createCanonicalTempSync('yagura_links_');
    addTearDown(() {
      // Links first: deleting the temporary tree must never reach a target.
      for (final link in _planted.toList()) {
        try {
          unplant(link);
        } on FileSystemException {
          // Already gone.
        }
      }
      temp.deleteSync(recursive: true);
    });
  });

  test('junction_planted_in_a_config_folder', () async {
    var skippedSymlink = false;
    for (final kind in _linkKinds) {
      final instance = makeDirectory('instance-$kind', {
        'server/start.cfg': 'ok',
      });
      final standIn = makeDirectory('system32-$kind', {
        'win.ini': 'system file',
      });
      final before = contentsOf(standIn.path);
      // The server replaces its `yagura/` folder with a link to a folder of
      // the host.
      if (!await plant(kind, p.join(instance.path, 'yagura'), standIn.path)) {
        skippedSymlink = true;
        continue;
      }

      // Starting the instance: the pre-start hook edits `yagura/mod.json`.
      await expectLater(
        Future.sync(() async {
          final hook = await HookHost().run(
            invocationFor(instance, '''
exports.onPreStart = () => ({files: [
  {path: 'yagura/mod.json', format: 'json', patch: {planted: true}}]});
'''),
          );
          await ConfigBinder(InstanceFs(instance.path))
              .apply(edits: hook.files);
        }),
        sandboxViolation('yagura/'),
      );
      // A hook reading through the link is refused the same way.
      final read = await HookHost().run(
        invocationFor(instance, '''
exports.onPreStart = () => {
  try { return {args: [yagura.fs.readText('yagura/win.ini')]}; }
  catch (e) { return {args: [e.code]}; }
};
'''),
      );
      expect(read.result.args, ['sandbox_violation']);

      expect(contentsOf(standIn.path), before, reason: kind);
    }
    if (skippedSymlink) markTestSkipped(_noSymlinks);
  });

  test('instance_directory_replaced_by_a_junction', () async {
    var skippedSymlink = false;
    for (final kind in _linkKinds) {
      // A root created before M2: the server renamed the real directory away
      // and put a link in its place.
      final elsewhere = makeDirectory('elsewhere-$kind', {
        'a.txt': 'not yours',
        'save/world.db': 'world',
      });
      final directory = p.join(temp.path, 'instances', 'valheim-$kind');
      if (!await plant(kind, directory, elsewhere.path)) {
        skippedSymlink = true;
        continue;
      }
      final before = contentsOf(elsewhere.path);
      final fs = InstanceFs(directory);

      final operations = <String, void Function()>{
        'stat': () => fs.stat('a.txt'),
        'stat root': () => fs.stat(''),
        'list': () => fs.list(''),
        'read': () => fs.readBytes('a.txt'),
        'write': () => fs.writeBytes('new.txt', [1, 2, 3]),
        'atomic write': () => fs.writeAtomic('a.txt', [1, 2, 3]),
        'create directory': () => fs.createDirectory('x/y'),
        'delete': () => fs.delete('a.txt'),
        'delete tree': () => fs.deleteTree('save'),
        'copy out': () => fs.copyOut('save', p.join(temp.path, 'copy-$kind')),
      };
      for (final MapEntry(:key, :value) in operations.entries) {
        expect(value, sandboxViolation(directory), reason: '$kind: $key');
      }
      await expectLater(
        Future.sync(
          () => ConfigBinder(fs).apply(
            edits: [
              FileEdit(path: 'a.txt', format: 'json', patch: {'a': 1}),
            ],
          ),
        ),
        sandboxViolation(directory),
      );
      await expectLater(
        snapshotterIn(p.join(temp.path, 'snapshots-$kind')).take(
          SnapshotRequest(
            instanceId: 'i1',
            instanceName: 'Valheim',
            instanceDirectory: directory,
            dataPaths: [p.join(directory, 'save')],
            reason: 'pre_update',
          ),
        ),
        sandboxViolation(directory),
      );

      expect(contentsOf(elsewhere.path), before, reason: kind);
    }
    if (skippedSymlink) markTestSkipped(_noSymlinks);
  });

  test('plain_instance_files', () async {
    final instance = makeDirectory('instance', {
      'server/start.cfg': 'ok',
      'save/world.db': 'world',
      'save/chars/one.fch': 'one',
      'logs/server.log': 'hello\n',
    });
    final fs = InstanceFs(instance.path);
    final snapshotter = snapshotterIn(p.join(temp.path, 'snapshots'));
    SnapshotRequest request(String reason) => SnapshotRequest(
      instanceId: 'i1',
      instanceName: 'Valheim',
      instanceDirectory: instance.path,
      dataPaths: [p.join(instance.path, 'save')],
      reason: reason,
    );

    // Start: the pre-start hook reads and edits files.
    final started = await HookHost().run(
      invocationFor(instance, '''
exports.onPreStart = () => ({
  args: [yagura.fs.readText('server/start.cfg'), String(yagura.fs.list('save').length)],
  files: [{path: 'yagura/mod.json', format: 'json', patch: {enabled: true}}]});
'''),
    );
    expect(started.result.args, ['ok', '2']);
    await ConfigBinder(fs).apply(edits: started.files);
    expect(
      File(p.join(instance.path, 'yagura', 'mod.json')).readAsStringSync(),
      contains('"enabled": true'),
    );

    // The operations around a run.
    fs.createDirectory('.yagura/run/run1');
    fs.writeAtomic('instance.json', [0x7b, 0x7d]);
    expect(fs.readBytes('instance.json'), [0x7b, 0x7d]);
    expect(
      fs.list('save').map((e) => e.name),
      unorderedEquals(['chars', 'world.db']),
    );
    expect(fs.treeSize('save'), 'world'.length + 'one'.length);

    // Snapshot, change, restore.
    final id = await snapshotter.take(request('pre_update'));
    File(p.join(instance.path, 'save', 'world.db'))
        .writeAsStringSync('changed');
    await snapshotter.restore(
      RestoreRequest(
        instanceId: 'i1',
        instanceName: 'Valheim',
        instanceDirectory: instance.path,
        dataPaths: request('x').dataPaths,
        snapshotId: id,
      ),
      onStep: (_) {},
      checkCancelled: () {},
    );
    expect(
      File(p.join(instance.path, 'save', 'world.db')).readAsStringSync(),
      'world',
    );

    // Stop: the marker the delete flow writes, then the files go.
    fs.createDirectory('.yagura');
    fs.writeBytes('.yagura/deleting', const []);
    fs.deleteTree('');
    expect(instance.existsSync(), isFalse);
  });

  test('delete_never_descends_into_a_link', () async {
    var skippedSymlink = false;
    for (final kind in _linkKinds) {
      final instance = makeDirectory('instance-$kind', {
        'server/start.cfg': 'ok',
      });
      final target = makeDirectory('target-$kind', {
        'precious.txt': 'keep me',
        'deep/precious2.txt': 'keep me too',
      });
      final before = contentsOf(target.path);
      if (!await plant(
        kind,
        p.join(instance.path, 'server', 'linked'),
        target.path,
      )) {
        skippedSymlink = true;
        continue;
      }

      InstanceFs(instance.path).deleteTree('');

      expect(instance.existsSync(), isFalse, reason: kind);
      expect(contentsOf(target.path), before, reason: kind);
      _planted.clear();
    }
    if (skippedSymlink) markTestSkipped(_noSymlinks);
  });

  group('recorded mod junctions (design D7, ADR 0015)', () {
    late Directory store;
    late Directory instance;
    const staged = 'server/@mod';

    setUp(() {
      // The content store's version directory, and an instance whose staged
      // entry `server/@mod` is recorded as a junction to it.
      store = makeDirectory(p.join('content', 'workshop', '221100', '7', '1'), {
        'mod.pbo': 'addon',
        'keys/a.bikey': 'key',
      });
      instance = makeDirectory('instance', {
        'server/start.cfg': 'ok',
        'save/world.db': 'world',
      });
    });

    InstanceFs recordedFs() =>
        InstanceFs(instance.path, recorded: {staged: store.path});

    /// Stages the junction through the daemon's own call.
    InstanceFs stage() {
      final fs = recordedFs();
      fs.createJunction(staged, store.path);
      _planted.add(p.join(instance.path, staged));
      return fs;
    }

    test('junction_created_and_read_back_relative_to_the_instance_root', () {
      final fs = stage();
      final link = p.join(instance.path, staged);

      // A real junction: the OS sees a link, with the right target.
      expect(
        FileSystemEntity.typeSync(link, followLinks: false),
        FileSystemEntityType.link,
      );
      expect(Link(link).targetSync().toLowerCase(), store.path.toLowerCase());
      expect(
        fs.junctionTarget(staged)?.toLowerCase(),
        store.path.toLowerCase(),
      );
      expect(fs.junctionTarget('server/start.cfg'), isNull);
      expect(fs.junctionTarget('server/nothing'), isNull);

      // A name that is taken is not replaced, and nothing is created below a
      // link.
      expect(() => fs.createJunction(staged, store.path), throwsA(anything));
      expect(
        () => fs.createJunction('$staged/x', store.path),
        sandboxViolation(staged),
      );
      expect(contentsOf(store.path), {
        'mod.pbo': 'addon',
        'keys': '<directory>',
        'keys\\a.bikey': 'key',
      });
    });

    test('read_continues_into_the_content_store', () async {
      final fs = stage();

      expect(fs.readBytes('$staged/mod.pbo'), 'addon'.codeUnits);
      expect(fs.readBytes('$staged/keys/a.bikey'), 'key'.codeUnits);
      expect(
        fs.list(staged).map((e) => e.name),
        unorderedEquals(['mod.pbo', 'keys']),
      );
      expect(fs.stat('$staged/mod.pbo')?.size, 'addon'.length);
      expect(fs.exists('$staged/missing.txt'), isFalse);
      expect(fs.stat(staged)?.isDirectory, isTrue);
      expect(fs.treeSize('$staged/keys'), 'key'.length);

      // The parent lists the junction as the link it is; an unrecorded
      // sibling junction is still refused.
      expect(
        fs.list('server').singleWhere((e) => e.name == '@mod').isLink,
        isTrue,
      );
      final other = makeDirectory('other', {'x.txt': 'x'});
      fs.createJunction('server/@other', other.path);
      _planted.add(p.join(instance.path, 'server', '@other'));
      expect(
        () => fs.readBytes('server/@other/x.txt'),
        sandboxViolation('server/@other'),
      );

      // The store's own links stay refused: the walk inside is a plain
      // confined one.
      final outside = makeDirectory('outside', {'secret.txt': 's'});
      expect(
        await plant('junction', p.join(store.path, 'jump'), outside.path),
        isTrue,
      );
      expect(
        () => fs.readBytes('$staged/jump/secret.txt'),
        sandboxViolation('jump'),
      );
      // Without the recorded map the same junction is refused.
      expect(
        () => InstanceFs(instance.path).readBytes('$staged/mod.pbo'),
        sandboxViolation(staged),
      );
    });

    test('write_below_a_recorded_junction_is_refused', () async {
      final fs = stage();
      final before = contentsOf(store.path);

      final operations = <String, void Function()>{
        'write': () => fs.writeBytes('$staged/new.txt', [1]),
        'overwrite': () => fs.writeBytes('$staged/mod.pbo', [1]),
        'open write': () => fs.openWrite('$staged/mod.pbo'),
        'atomic write': () => fs.writeAtomic('$staged/mod.pbo', [1]),
        'create directory': () => fs.createDirectory('$staged/sub'),
        'delete': () => fs.delete('$staged/mod.pbo'),
        'delete tree': () => fs.deleteTree('$staged/keys'),
        'rename out': () => fs.rename('$staged/mod.pbo', 'server/x'),
        'rename in': () => fs.rename('server/start.cfg', '$staged/x'),
        'set security': () => fs.setSecurity('$staged/mod.pbo', 'D:'),
        'copy in': () => fs.copyIn(instance.path, '$staged/copy'),
      };
      for (final MapEntry(:key, :value) in operations.entries) {
        expect(value, sandboxViolation(staged), reason: key);
      }
      // The binder is an edit like any other.
      await expectLater(
        Future.sync(
          () => ConfigBinder(fs).apply(
            edits: [
              FileEdit(path: '$staged/a.json', format: 'json', patch: {'a': 1}),
            ],
          ),
        ),
        sandboxViolation(staged),
      );

      expect(contentsOf(store.path), before);
    });

    test('recorded_path_with_another_target_is_sandbox_violation', () async {
      var skippedSymlink = false;
      for (final kind in _linkKinds) {
        final elsewhere = makeDirectory('elsewhere-$kind', {
          'mod.pbo': 'not the store',
        });
        final before = contentsOf(elsewhere.path);
        final link = p.join(instance.path, 'server', '@$kind');
        if (!await plant(kind, link, elsewhere.path)) {
          skippedSymlink = true;
          continue;
        }
        final fs = InstanceFs(
          instance.path,
          recorded: {'server/@$kind': store.path},
        );

        final operations = <String, void Function()>{
          'read': () => fs.readBytes('server/@$kind/mod.pbo'),
          'stat': () => fs.stat('server/@$kind/mod.pbo'),
          'stat link': () => fs.stat('server/@$kind'),
          'list': () => fs.list('server/@$kind'),
          'tree size': () => fs.treeSize('server/@$kind/keys'),
          'write': () => fs.writeBytes('server/@$kind/new', [1]),
        };
        for (final MapEntry(:key, :value) in operations.entries) {
          expect(
            value,
            sandboxViolation('server/@$kind'),
            reason: '$kind: $key',
          );
        }
        expect(contentsOf(elsewhere.path), before, reason: kind);
      }
      if (skippedSymlink) markTestSkipped(_noSymlinks);
    });

    test('recorded_path_replaced_by_a_directory_is_an_ordinary_one', () {
      // The server removed the junction and made a real folder: nothing
      // redirects, so the walk is the plain one.
      makeDirectory(p.join('instance', 'server', '@mod'), {'own.txt': 'mine'});
      final fs = recordedFs();

      expect(fs.readBytes('$staged/own.txt'), 'mine'.codeUnits);
      expect(() => fs.writeBytes('$staged/x', [1]), sandboxViolation(staged));
    });

    test('snapshot_walks_skip_recorded_paths', () {
      final fs = stage();
      final destination = p.join(temp.path, 'copy');
      final before = contentsOf(store.path);

      // The walk would otherwise fail on the link.
      expect(
        () => InstanceFs(instance.path).treeSize('server'),
        sandboxViolation(staged),
      );
      expect(fs.treeSize('server'), 'ok'.length);
      expect(fs.copyOut('server', destination), 'ok'.length);
      expect(contentsOf(destination), {'start.cfg': 'ok'});
      expect(contentsOf(store.path), before);
    });

    test('delete_removes_the_recorded_link_only', () {
      final fs = stage();
      final before = contentsOf(store.path);

      fs.delete(staged);

      expect(
        FileSystemEntity.typeSync(
          p.join(instance.path, staged),
          followLinks: false,
        ),
        FileSystemEntityType.notFound,
      );
      expect(contentsOf(store.path), before);
      _planted.clear();

      // Deleting the instance with the link in place leaves the store alone.
      final again = stage();
      again.deleteTree('');
      expect(instance.existsSync(), isFalse);
      expect(contentsOf(store.path), before);
      _planted.clear();
    });
  });
}
