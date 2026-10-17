import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';

/// The `last_requested_state` column of an instance row.
String lastRequestedState(TestEnv env, String id) {
  final db = YaguraDatabase.open(p.join(env.data, 'yagura.db'));
  try {
    final rows = db.sqlite.select(
      'SELECT last_requested_state FROM instances WHERE id = ?',
      [id],
    );
    return rows.single['last_requested_state']! as String;
  } finally {
    db.close();
  }
}

void main() {
  test('cancelled_update_not_autostarted', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createRunning(daemon);
    expect(lastRequestedState(env, instance.id), 'running');
    env.steam.hold = Completer<void>();

    final op = daemon.instances.update(instance.id);
    await eventually(
      () => daemon.instances.get(instance.id).state == InstanceState.updating,
      reason: 'the update to pass its stop step',
    );
    // The internal stop of an update keeps the last requested state (D14)...
    expect(lastRequestedState(env, instance.id), 'running');
    daemon.operations.cancel(op.id);
    final done = await daemon.operations.whenDone(op.id);

    // ...and an update that ends with the server stopped clears it.
    expect(done.status, OperationStatus.cancelled);
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
    expect(lastRequestedState(env, instance.id), isEmpty);

    await env.kill(daemon);
    final restarted = await env.start();
    expect(restarted.instances.get(instance.id).state, InstanceState.stopped);
    expect(lastRequestedState(env, instance.id), isEmpty);
  });
}
