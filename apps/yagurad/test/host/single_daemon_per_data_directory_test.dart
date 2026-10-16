import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/host/data_dir_lock.dart';

import '../support/daemon_support.dart';

void main() {
  test('second_instance_refused', () async {
    final env = TestEnv();
    await env.start();

    await expectLater(
      env.start(),
      failsWith('data_dir_locked', messageHas: ['$pid'], details: {'pid': pid}),
    );
  });

  test('a second process is refused with the holder PID', () async {
    final env = TestEnv();
    await env.start();

    // Run from the temp directory, outside any package, so `dart run` builds
    // no native assets (the test process holds them open on Windows).
    final script = File('test/support/lock_probe.dart')
        .copySync(p.join(env.root.path, 'lock_probe.dart'));
    final probe = await Process.run(Platform.resolvedExecutable, [
      'run',
      script.path,
      p.join(env.data, 'yagurad.lock'),
      '${DataDirLock.lockOffset}',
    ], workingDirectory: env.root.path);

    expect(probe.exitCode, 3, reason: '${probe.stdout}${probe.stderr}');
    expect((probe.stdout as String).trim(), 'locked $pid');
  });

  test('lock_file_left_by_a_crashed_daemon', () async {
    final env = TestEnv();
    // The lock file of a daemon that crashed: nobody holds the lock, and the
    // recorded PID now belongs to an unrelated live process (this one).
    Directory(env.data).createSync(recursive: true);
    File(p.join(env.data, 'yagurad.lock')).writeAsStringSync('$pid\n');

    final daemon = await env.start();

    expect(daemon.instances.list(), isEmpty);
    expect(
      File(p.join(env.data, 'yagurad.lock')).readAsStringSync().trim(),
      '$pid',
    );
  });
}
