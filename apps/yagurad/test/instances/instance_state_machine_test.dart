import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';

void main() {
  test('start_from_stopped', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createInstalled(daemon);
    expect(instance.state, InstanceState.stopped);
    final states = <InstanceState>[];
    daemon.instances.events.listen((e) {
      if (e is InstanceChanged && e.instance.id == instance.id) {
        states.add(e.instance.state);
      }
    });

    final op = daemon.instances.start(instance.id);
    final done = await daemon.operations.whenDone(op.id);
    await Future<void>.delayed(Duration.zero);

    expect(done.status, OperationStatus.succeeded);
    expect(states, [InstanceState.starting, InstanceState.running]);
    final running = daemon.instances.get(instance.id);
    expect(running.state, InstanceState.running);
    expect(running.pid, env.process.servers.single.pid);
    final launch = env.process.launches.single;
    expect(launch.instanceId, instance.id);
    expect(launch.executable.endsWith('valheim_server.exe'), isTrue);
    expect(
      launch.args,
      containsAllInOrder(['-name', 'Friends', '-port', '2456']),
    );
  });

  test('start_while_not_installed', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createValheim(daemon);

    expect(
      () => daemon.instances.start(instance.id),
      failsWith('not_installed'),
    );

    expect(daemon.instances.get(instance.id).state, InstanceState.notInstalled);
    expect(daemon.operations.listForInstance(instance.id), isEmpty);
    expect(env.process.launches, isEmpty);
  });

  test('stop_ends_a_running_instance', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createRunning(daemon);

    final op = daemon.instances.stop(instance.id);
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.succeeded);
    expect(done.resultReason, 'stopped_by:graceful');
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
    expect(env.process.stops.single.grace, const Duration(seconds: 30));
  });

  test('a_failed_launch_leaves_the_instance_stopped', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createInstalled(daemon);
    env.process.launchError = YaguraException(
      'launch_failed',
      'CreateProcess failed',
    );

    final op = daemon.instances.start(instance.id);
    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'launch_failed');
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
  });

  test('process_exits_during_the_health_window', () async {
    final env = TestEnv();
    env.installValheimHealth('type: process\n  start_timeout_seconds: 60');
    final daemon = await env.start(
      processHealthSettle: const Duration(milliseconds: 400),
    );
    final instance = await createInstalled(daemon);
    // A bootstrapper: it ends shortly after it started.
    env.process.onLaunch = (server) =>
        Timer(const Duration(milliseconds: 60), () => server.exit(3));
    final crashes = collectNotices(daemon, 'crashed');

    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'launch_failed');
    expect(
      done.resultMessage,
      allOf(contains('exit code 3'), contains('valheim_server.exe')),
    );
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
    // No restart is attempted and the exit is not a crash.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(env.process.launches, hasLength(1));
    expect(crashes, isEmpty);
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
  });

  test('health_check_never_passes', () async {
    final env = TestEnv();
    env.installValheimHealth(
      'type: port\n  port: game\n  start_timeout_seconds: 1',
    );
    final daemon = await env.start();
    final instance = await createValheim(
      daemon,
      ports: {'game': await freePort()},
    );
    await daemon.operations.whenDone(daemon.instances.install(instance.id).id);
    final unknown = collectNotices(daemon, 'health_unknown');
    final started = Stopwatch()..start();

    final done = await runStart(daemon, instance.id);

    // The window is start_timeout (1 s); the process is still alive.
    expect(started.elapsed, greaterThanOrEqualTo(const Duration(seconds: 1)));
    expect(done.status, OperationStatus.succeeded);
    final running = daemon.instances.get(instance.id);
    expect(running.state, InstanceState.running);
    expect(running.health, InstanceHealth.unknown);
    expect(done.warnings, contains(contains('health')));
    await Future<void>.delayed(Duration.zero);
    expect(unknown, hasLength(1));
    expect(env.process.stops, isEmpty, reason: 'the process is not killed');
    expect(env.process.servers.single.pid, running.pid);
  });

  test('port_health_passes_once_the_port_listens', () async {
    final env = TestEnv();
    env.installValheimHealth(
      'type: port\n  port: game\n  start_timeout_seconds: 30',
    );
    env.editValheim(
      'protocol: udp\n    purpose: game',
      'protocol: tcp\n    purpose: game',
    );
    final daemon = await env.start();
    final port = await freePort();
    final instance = await createValheim(daemon, ports: {'game': port});
    await daemon.operations.whenDone(daemon.instances.install(instance.id).id);

    final op = daemon.instances.start(instance.id);
    await eventually(() => env.process.launches.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(
      daemon.instances.get(instance.id).state,
      InstanceState.starting,
      reason: 'nothing listens yet',
    );
    final listener = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      port,
    );
    addTearDown(listener.close);

    final done = await daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.succeeded);
    final running = daemon.instances.get(instance.id);
    expect(running.state, InstanceState.running);
    expect(running.health, InstanceHealth.ok);
  });

  test('settings_edited_while_health_is_pending_need_a_restart', () async {
    final env = TestEnv();
    env.installValheimHealth(
      'type: port\n  port: game\n  start_timeout_seconds: 30',
    );
    env.editValheim(
      'protocol: udp\n    purpose: game',
      'protocol: tcp\n    purpose: game',
    );
    final daemon = await env.start();
    final port = await freePort();
    final instance = await createValheim(daemon, ports: {'game': port});
    await daemon.operations.whenDone(daemon.instances.install(instance.id).id);

    final op = daemon.instances.start(instance.id);
    await eventually(() => env.process.launches.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(daemon.instances.get(instance.id).state, InstanceState.starting);
    daemon.instances.updateSettings(
      UpdateSettingsRequest(
        instanceId: instance.id,
        settings: valheimSettings(name: 'Renamed'),
      ),
    );
    final listener = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      port,
    );
    addTearDown(listener.close);

    await daemon.operations.whenDone(op.id);

    final running = daemon.instances.get(instance.id);
    expect(running.state, InstanceState.running);
    expect(running.restartRequired, isTrue);
  });
}
