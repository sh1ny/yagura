import 'dart:async';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/host/migrations.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/temp_support.dart';

void main() {
  test('at_most_four_heavy_steps_run_at_once', () async {
    final dir = createCanonicalTempSync('yagurad_runner_');
    final db = YaguraDatabase.open(
      p.join(dir.path, 'yagura.db'),
      migrations: allMigrations,
    );
    addTearDown(() {
      db.close();
      dir.deleteSync(recursive: true);
    });
    final runner = OperationRunner(database: db);
    var active = 0;
    var peak = 0;
    final release = Completer<void>();
    final ops = [
      for (var i = 0; i < 7; i++)
        runner.enqueue(
          instanceId: 'inst-$i',
          kind: OperationKind.install,
          body: (context) => context.heavy(() async {
            peak = max(peak, ++active);
            await release.future;
            active--;
          }, installation: 'account-$i'),
        ),
    ];

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(peak, 4);
    expect(active, 4);
    release.complete();
    for (final op in ops) {
      expect((await runner.whenDone(op.id)).status, OperationStatus.succeeded);
    }
    expect(peak, 4);
  });
}
