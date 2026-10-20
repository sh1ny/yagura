import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/instances/instance.dart';

import '../support/daemon_support.dart';
import 'log_test_support.dart';

/// The instance's `logs/server.log`, where the Valheim fixture logs.
File serverLog(Instance instance) =>
    File(p.join(instance.directory, 'logs', 'server.log'));

/// Sets the Valheim `password` secret of [instance] to [value].
void setPassword(Daemon daemon, Instance instance, String value) {
  daemon.instances.setSecret(instance.id, 'password', value);
}

/// An instance whose `server` log source is attached.
Future<Instance> loggingInstance(Daemon daemon) async {
  final instance = await createValheim(daemon);
  await eventually(
    () => logSourcesOf(daemon, instance.id).isNotEmpty,
    reason: 'the log source to attach',
  );
  return instance;
}

void main() {
  test('password_echoed_by_the_server', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await loggingInstance(daemon);
    setPassword(daemon, instance, 'hunter22secret');
    final followed = Collector(daemon.logs.follow(instance.id));

    serverLog(instance)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        'Server password is hunter22secret (do not share)\n'
        'a line without it\n',
      );
    await daemon.logs.pollNow(instance.id);
    await followed.settle();

    expect(followed.texts, [
      'Server password is *** (do not share)',
      'a line without it',
    ]);
  });

  test('backlog_and_crash_lines_masked', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createRunning(daemon);
    setPassword(daemon, instance, 'hunter22secret');
    final crashed = collectNotices(daemon, 'crashed');
    serverLog(instance).writeAsStringSync(
      'RCON password hunter22secret loaded\n',
      mode: FileMode.append,
    );

    env.process.servers.single.exit(1);
    await eventually(() => crashed.isNotEmpty, reason: 'the crash notice');

    expect(crashed.single.lastLogLines, contains('RCON password *** loaded'));
    expect(
      crashed.single.lastLogLines.where((l) => l.contains('hunter22secret')),
      isEmpty,
    );
    final backlog = daemon.logs.backlog(instance.id);
    expect([
      for (final e in backlog.entries) e.text,
    ], contains('RCON password *** loaded'));
    expect(
      backlog.entries.where((e) => e.text.contains('hunter22secret')),
      isEmpty,
    );
  });

  test('replaced_secret_still_masked', () async {
    final env = TestEnv();
    env.installValheim();
    var now = DateTime.utc(2026, 10, 17, 12);
    final daemon = await env.start(clock: () => now);
    final instance = await loggingInstance(daemon);
    setPassword(daemon, instance, 'oldpassword1');
    setPassword(daemon, instance, 'newpassword2');
    now = now.add(const Duration(hours: 2));
    final followed = Collector(daemon.logs.follow(instance.id));

    serverLog(instance)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('old oldpassword1 and new newpassword2\n');
    await daemon.logs.pollNow(instance.id);
    await followed.settle();

    expect(followed.texts, ['old *** and new ***']);
  });

  test('short_secret_inside_a_word', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await loggingInstance(daemon);
    setPassword(daemon, instance, 'ab12');
    final followed = Collector(daemon.logs.follow(instance.id));

    serverLog(instance)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('inside xab12y and alone ab12, then (ab12)\n');
    await daemon.logs.pollNow(instance.id);
    await followed.settle();

    expect(followed.texts, ['inside xab12y and alone ***, then (***)']);
  });

  test('no_secrets_set', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await loggingInstance(daemon);
    final followed = Collector(daemon.logs.follow(instance.id));

    serverLog(instance)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('ab12 hunter22secret ***\n');
    await daemon.logs.pollNow(instance.id);
    await followed.settle();

    expect(followed.texts, ['ab12 hunter22secret ***']);
  });

  test('replaced_secrets_pruned_after_24_hours', () async {
    final env = TestEnv();
    env.installValheim();
    var now = DateTime.utc(2026, 10, 17, 12);
    final daemon = await env.start(clock: () => now);
    final instance = await loggingInstance(daemon);
    setPassword(daemon, instance, 'firstpassword');
    setPassword(daemon, instance, 'secondpassword');
    setPassword(daemon, instance, 'thirdpassword');
    final followed = Collector(daemon.logs.follow(instance.id));
    final log = serverLog(instance)..parent.createSync(recursive: true);

    // Both replaced values are hidden, not only the latest one.
    log.writeAsStringSync('firstpassword secondpassword thirdpassword\n');
    await daemon.logs.pollNow(instance.id);

    // A day later the hourly prune drops them; the current one stays hidden.
    now = now.add(const Duration(hours: 25));
    daemon.instances.pruneReplacedSecrets();
    log.writeAsStringSync(
      'firstpassword secondpassword thirdpassword\n',
      mode: FileMode.append,
    );
    await daemon.logs.pollNow(instance.id);
    await followed.settle();

    expect(followed.texts, ['*** *** ***', 'firstpassword secondpassword ***']);
  });
}
