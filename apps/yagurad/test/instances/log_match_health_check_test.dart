import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/instances/instance.dart';

import '../support/daemon_support.dart';

// Both rows are task 7.3: the start-time health evaluator of task 5.3 is not
// built yet, so a Start reaches `running` as soon as the server is launched.
// They use only what the log hub offers the evaluator: the hub marks the run
// before each Start (`markRun`) and `linesAfter` hands over the lines read
// after the mark.

const _skip = 'task 7.3: needs the start-time health evaluator from task 5.3';

const _matchLine = 'Game server connected';

/// Starts the instance and waits until the fake server was launched.
Future<String> _startAndWaitForLaunch(
  TestEnv env,
  Daemon daemon,
  String id,
) async {
  final launched = env.process.launches.length;
  final op = daemon.instances.start(id);
  await eventually(
    () => env.process.launches.length > launched,
    reason: 'the server to be launched',
  );
  // Give a health evaluator the chance to poll the log.
  await daemon.logs.pollNow(id);
  return op.id;
}

void main() {
  test('log_match_health_check', skip: _skip, () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createInstalled(daemon);
    // The file still holds the line from the previous run.
    final log = File('${instance.directory}/logs/server.log')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('old run\n$_matchLine\nshutting down\n');
    await daemon.logs.pollNow(instance.id);

    final operation = await _startAndWaitForLaunch(env, daemon, instance.id);
    expect(
      daemon.instances.get(instance.id).state,
      InstanceState.starting,
      reason: 'the old line must not make the instance healthy',
    );

    // The server writes the line during this run.
    log.writeAsStringSync('new run\n$_matchLine\n', mode: FileMode.append);
    await daemon.logs.pollNow(instance.id);
    await daemon.operations.whenDone(operation);
    expect(daemon.instances.get(instance.id).state, InstanceState.running);
  });

  test('log_file_rewritten_past_its_old_size', skip: _skip, () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createInstalled(daemon);
    // The previous run's log is 40 KiB and holds the match line.
    final log = File('${instance.directory}/logs/server.log')
      ..parent.createSync(recursive: true);
    final oldRun = StringBuffer('old run\n$_matchLine\n');
    while (oldRun.length < 40 * 1024) {
      oldRun.writeln('previous run line ${oldRun.length}');
    }
    log.writeAsStringSync(oldRun.toString());
    await daemon.logs.pollNow(instance.id);

    final operation = await _startAndWaitForLaunch(env, daemon, instance.id);
    expect(daemon.instances.get(instance.id).state, InstanceState.starting);

    // The new run rewrites the file from the start, past 40 KiB, before the
    // next poll; the match line is within the part the old offset skipped.
    final newRun = StringBuffer('new run starts\nbooting\n$_matchLine\n');
    while (newRun.length < 50 * 1024) {
      newRun.writeln('new run line ${newRun.length}');
    }
    log.writeAsBytesSync(utf8.encode(newRun.toString()));
    await daemon.logs.pollNow(instance.id);
    await daemon.operations.whenDone(operation);
    expect(daemon.instances.get(instance.id).state, InstanceState.running);
  });
}
