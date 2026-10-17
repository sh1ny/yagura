import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/daemon_support.dart';

void main() {
  test('daemon_killed_while_removing_files', () async {
    final env = TestEnv();
    env.installValheim();
    final removing = Completer<void>();
    final gate = Completer<void>();
    final daemon = await env.start(
      realSnapshots: true,
      // A removal the daemon dies in: part of the tree is gone, the rest not.
      removeDirectory: (directory) async {
        Directory(p.join(directory, 'server')).deleteSync(recursive: true);
        removing.complete();
        await gate.future;
      },
    );
    final instance = await createInstalled(daemon, name: 'Friends');
    File(p.join(instance.directory, 'save', 'world.db'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('world');
    final op = daemon.instances.delete(
      instance.id,
      deleteFiles: true,
      confirmName: 'Friends',
    );
    await removing.future;
    expect(daemon.instances.list(), isEmpty); // the rows are already gone

    await env.kill(daemon);
    gate.completeError(YaguraException('internal_error', 'killed'));
    final restarted = await env.start(realSnapshots: true);

    expect(restarted.instances.list(), isEmpty);
    expect(Directory(instance.directory).existsSync(), isFalse);
    final orphans = restarted.instances.listOrphanSnapshots();
    expect(orphans, hasLength(1));
    expect(orphans.single.reason, 'pre_delete');
    expect(orphans.single.instanceName, 'Friends');
    // The delete itself was recorded as interrupted, not lost.
    expect(
      restarted.operations.get(op.id)!.status,
      OperationStatus.interrupted,
    );
  });
}
