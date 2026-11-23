@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/files/instance_fs.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/process/process.dart';

import '../../test/support/daemon_support.dart';
import '../../test/support/process_support.dart';
import '../../test/support/secret_support.dart';
import '../../test/support/temp_support.dart';

// Design D4: a secret launch argument reaches the server's argv over standard
// input (daemon to launcher, launcher to relay) and no file the daemon, the
// launcher or the relay writes holds it. These rows run console mode with the
// real launcher and relay; service mode is covered by the elevated row of
// game_servers_run_under_a_low_privilege_account_test.dart.

const _token = 'GSLT-7C1D44E0-NEVER-ON-DISK';

/// Every file under [root] whose bytes hold [needle], except [allowed].
List<String> _filesHolding(
  String root,
  String needle, {
  Set<String> allowed = const {},
}) {
  final bytes = utf8.encode(needle);
  bool contains(List<int> haystack) {
    outer:
    for (var i = 0; i + bytes.length <= haystack.length; i++) {
      for (var j = 0; j < bytes.length; j++) {
        if (haystack[i + j] != bytes[j]) continue outer;
      }
      return true;
    }
    return false;
  }

  return [
    for (final entity in Directory(root).listSync(recursive: true))
      if (entity is File && !allowed.contains(p.canonicalize(entity.path)))
        if (contains(_tryRead(entity))) entity.path,
  ];
}

List<int> _tryRead(File file) {
  try {
    return file.readAsBytesSync();
  } on FileSystemException {
    return const [];
  }
}

void main() {
  test('secret_argument_reaches_the_server_and_no_run_file', () async {
    final rig = await ProcessRig.create(serverArgs: ['-gslt={{secrets.gslt}}']);
    rig.addGsltSetting(required: true);
    final daemon = await rig.start(
      secretProtector: FakeSecretProtector(devSid),
    );
    final instance = await rig.createInstalledFake(daemon);
    daemon.instances.setSecret(instance.id, 'gslt', _token);

    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    // The server's argv holds the value, with its prefix.
    final argv = File(rig.stateFile(instance, 'args.txt')).readAsStringSync();
    expect(argv.split('\n'), contains('-gslt=$_token'));

    // No file of the instance holds it: not the run files, not the capture of
    // the server's output. The server's own copy of its argv is the one
    // accepted place.
    final allowed = {p.canonicalize(rig.stateFile(instance, 'args.txt'))};
    expect(
      _filesHolding(instance.directory, _token, allowed: allowed),
      isEmpty,
    );
    final runs = Directory(RunFiles.rootFor(instance.directory));
    final run = runs.listSync().whereType<Directory>().single;
    final launch = jsonDecode(
      File(p.join(run.path, 'launch.json')).readAsStringSync(),
    ) as Map<String, Object?>;
    expect(
      launch['args'],
      contains(equals({'secret': 'gslt', 'prefix': '-gslt=', 'suffix': ''})),
    );
    for (final name in ['launch.json', 'relay.json']) {
      expect(
        File(p.join(run.path, name)).readAsStringSync(),
        isNot(contains(_token)),
      );
    }

    // Nor does the operation history, or any other file under the data
    // directory (the secret store holds it protected, not as text).
    final history = jsonEncode([
      for (final op in daemon.operations.listForInstance(instance.id))
        [op.resultReason, op.resultMessage, op.warnings, op.currentStep],
    ]);
    expect(history, isNot(contains(_token)));
    final stop = await runStop(daemon, instance.id);
    expect(stop.status, OperationStatus.succeeded);
  }, tags: ['windows']);

  test('launcher_without_launch_input', () async {
    requireBreakaway();
    final tools = await processTools();
    final dir = createCanonicalTempSync('yagura_launch_input_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final runDirectory = p.join(dir.path, '.yagura', 'run', 'r1');
    Directory(runDirectory).createSync(recursive: true);

    final launcher = await Process.start(tools.yagurad, [
      'launch',
      '--run-dir',
      runDirectory,
    ]);
    await launcher.stdin.close();
    final stderrText = await launcher.stderr.transform(utf8.decoder).join();
    final code = await launcher.exitCode;

    expect(code, isNot(0));
    expect(stderrText, contains('launch_input_missing'));
    expect(File(p.join(runDirectory, 'relay.json')).existsSync(), isFalse);
  }, tags: ['windows']);

  test('relay_without_its_secrets_starts_no_server', () async {
    requireBreakaway();
    final tools = await processTools();
    final dir = createCanonicalTempSync('yagura_relay_input_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final state = p.join(dir.path, 'state');
    final runDirectory = RunFiles.directoryFor(dir.path, 'r1');
    final files = RunFiles(runDirectory, fs: InstanceFs(dir.path));
    files.writeLaunch(
      LaunchRequest(
        instanceId: 'i',
        runId: 'r1',
        executable: tools.fakeServer,
        args: ['--state-dir', state, '-gslt=***'],
        secretArguments: const [
          SecretArgument(
            index: 2,
            setting: 'gslt',
            prefix: '-gslt=',
            suffix: '',
          ),
        ],
        env: const {},
        workingDirectory: dir.path,
        instanceDirectory: dir.path,
        runDirectory: runDirectory,
      ),
    );

    // The relay's standard input is closed: the launcher never wrote its line.
    final relay = await Process.start(tools.yagurad, [
      'relay',
      '--run-dir',
      runDirectory,
    ]);
    await relay.stdin.close();
    unawaited(relay.stdout.drain<void>());
    unawaited(relay.stderr.drain<void>());
    final code = await relay.exitCode;

    expect(code, isNot(0));
    expect(files.readError(), isNotNull, reason: 'exit.json names the cause');
    expect(files.readError(), contains('secret'));
    expect(files.readRelay()?.server, isNull);
    expect(Directory(state).existsSync(), isFalse, reason: 'no server ran');
  }, tags: ['windows']);
}
