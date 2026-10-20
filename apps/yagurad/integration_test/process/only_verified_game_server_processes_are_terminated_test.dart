@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/platform/win32_process.dart';
import 'package:yagurad/src/process/process.dart';
import 'package:yagurad/src/process/relay_run_files.dart';

import '../../test/support/daemon_support.dart';
import '../../test/support/process_support.dart';

// Design D9: the run files are written by the account the server runs as, so
// the daemon trusts none of them. Before it signals, ends or re-attaches a
// process it checks the token user, the parentage and the start order. These
// rows run in development mode, where the account is the current user, so
// the "system process" of the spec is a process of this user that is not the
// relay's child: the parentage check is what refuses it. The token check has
// its own unit tests with a fake process table.

/// A process that does nothing for a while and is not a child of any relay.
Future<Process> _decoy() async {
  final process = await Process.start('ping', ['-n', '120', '127.0.0.1']);
  unawaited(process.stdout.drain<void>());
  unawaited(process.stderr.drain<void>());
  addTearDown(() => process.kill());
  return process;
}

ProcessIdentity _identityOf(int pid) {
  final identity = identityOfPid(pid);
  expect(identity, isNotNull, reason: 'process $pid is running');
  return identity!;
}

/// Rewrites the database while no daemon has it open.
void _edit(TestEnv env, void Function(YaguraDatabase db) change) {
  final db = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
  try {
    change(db);
  } finally {
    db.close();
  }
}

/// Makes the run of [instance] look as if the daemon died before it recorded
/// the server: `pending`, with only the relay recorded.
void _forgetServer(TestEnv env, Instance instance) {
  _edit(env, (db) {
    db.sqlite.execute(
      'UPDATE runs SET state = ?, server_pid = 0, server_created = 0, '
      "executable = '' WHERE instance_id = ?",
      ['pending', instance.id],
    );
  });
}

String _runDirectory(Instance instance) {
  final root = Directory(RunFiles.rootFor(instance.directory));
  return root.listSync().whereType<Directory>().single.path;
}

/// `relay.json` as a game-server account could rewrite it.
void _forgeRelayFile(
  Instance instance,
  ProcessIdentity relay,
  ProcessIdentity server,
) {
  RunFiles(_runDirectory(instance)).writeRelayAndServer(relay, server);
}

void main() {
  test('forged_run_file', () async {
    final rig = await ProcessRig.create();
    final first = await rig.start();
    final instance = await rig.createRunning(first);
    final genuine = instance.pid;
    await rig.env.kill(first);
    _forgetServer(rig.env, instance);
    final decoy = await _decoy();
    final recorded = RunFiles(_runDirectory(instance)).readRelay()!.relay;
    _forgeRelayFile(instance, recorded, _identityOf(decoy.pid));

    final second = await rig.start();

    // The decoy is not the relay's child: it is not touched, and the genuine
    // server, the relay's child, is found instead.
    final after = second.instances.get(instance.id);
    expect(after.state, InstanceState.running);
    expect(after.pid, genuine);
    expect(
      second.instances.recoveryNotices.map((n) => n.kind),
      contains('run_record_rejected'),
    );
    final done = await runStop(second, instance.id);
    expect(done.status, OperationStatus.succeeded);
    expect(processAlive(genuine), isFalse);
    expect(processAlive(decoy.pid), isTrue, reason: 'the decoy was left alone');
  }, tags: ['windows']);

  test('forged_run_file_and_no_verified_server', () async {
    final rig = await ProcessRig.create();
    final first = await rig.start();
    final instance = await rig.createInstalledFake(first);
    await rig.env.kill(first);
    // A relay that has no server: a stand-in process the daemon recorded as
    // the relay of a run that died before the server was recorded.
    final standIn = await _decoy();
    final foreign = await _decoy();
    final runId = 'forged-run';
    final directory = RunFiles.directoryFor(instance.directory, runId);
    Directory(directory).createSync(recursive: true);
    final relay = _identityOf(standIn.pid);
    RunFiles(directory).writeRelayAndServer(relay, _identityOf(foreign.pid));
    _edit(rig.env, (db) {
      db.sqlite.execute(
        'INSERT INTO runs (run_id, instance_id, directory, state, relay_pid, '
        'relay_created, relay_executable, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          runId,
          instance.id,
          directory,
          'pending',
          relay.pid,
          relay.created,
          relay.executable,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      db.sqlite.execute(
        'UPDATE instances SET state = ?, state_reason = ? WHERE id = ?',
        ['running', '', instance.id],
      );
    });

    final second = await rig.start();

    // Nothing was terminated, and the instance is in error.
    final after = second.instances.get(instance.id);
    expect(after.state, InstanceState.error);
    expect(after.stateReason, 'run_record_rejected');
    expect(after.warning, contains('${relay.pid}'));
    expect(processAlive(standIn.pid), isTrue);
    expect(processAlive(foreign.pid), isTrue);

    final stop = await runStop(second, instance.id);
    expect(stop.status, OperationStatus.failed);
    expect(stop.resultReason, 'run_record_rejected');
    expect(stop.resultMessage, contains('${relay.pid}'));
    expect(processAlive(standIn.pid), isTrue);
    expect(processAlive(foreign.pid), isTrue);

    // Acknowledge leaves error: stopped, the run cleared, the warning kept.
    final acknowledged = second.instances.acknowledge(instance.id);
    expect(acknowledged.state, InstanceState.stopped);
    expect(acknowledged.warning, contains('${relay.pid}'));
    expect(second.instances.runs.unresolvedFor(instance.id), isEmpty);
  }, tags: ['windows']);

  test('genuine_server', () async {
    final rig = await ProcessRig.create();
    final first = await rig.start();
    final instance = await rig.createRunning(first);
    final pid = instance.pid;
    await rig.env.kill(first);

    final second = await rig.start();

    // The recorded server is the relay's child, running as the account:
    // re-attached without a notice, and stop acts on it normally.
    final after = second.instances.get(instance.id);
    expect(after.state, InstanceState.running);
    expect(after.pid, pid);
    expect(
      second.instances.recoveryNotices.map((n) => n.kind),
      isNot(contains('run_record_rejected')),
    );
    final done = await runStop(second, instance.id);
    expect(done.resultReason, 'stopped_by:graceful');
    expect(processAlive(pid), isFalse);
  }, tags: ['windows']);
}
