import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/daemon_support.dart';

void main() {
  test('default_layout_created', () async {
    final env = TestEnv();
    expect(Directory(env.data).existsSync(), isFalse);

    await env.start();

    expect(File(p.join(env.data, 'yagura.db')).existsSync(), isTrue);
    for (final folder in [
      'steamcmd',
      'content',
      p.join('content', '.staging'),
      'plugins',
      'instances',
      'snapshots',
      'logs',
    ]) {
      expect(
        Directory(p.join(env.data, folder)).existsSync(),
        isTrue,
        reason: folder,
      );
    }
  });

  test('data_directory_not_writable', () async {
    final env = TestEnv();
    // A regular file where a directory is needed: the data directory cannot
    // be created beneath it.
    final blocker = File(p.join(env.root.path, 'blocker'))
      ..writeAsStringSync('');
    final path = p.join(blocker.path, 'data');

    await expectLater(
      env.start(dataPath: path),
      failsWith(
        'data_dir_unwritable',
        messageHas: [path],
        details: {'path': path},
      ),
    );
  });
}
