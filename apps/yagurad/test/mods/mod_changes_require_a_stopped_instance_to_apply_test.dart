import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/api_support.dart';
import '../support/content_support.dart';
import '../support/daemon_support.dart';
import '../support/mods_support.dart';

/// The names of the entries of `<instance>/server`, sorted.
List<String> serverEntries(Instance instance) {
  final dir = Directory(p.join(instance.directory, 'server'));
  return [for (final e in dir.listSync()) p.basename(e.path)]..sort();
}

void main() {
  test('mods_applied_by_start', () async {
    final rig = await ModsRig.start();
    final ids = [for (var i = 0; i < 12; i++) '${2000000 + i}'];
    for (final (i, id) in ids.indexed) {
      rig.item(id, title: 'Mod $i');
    }
    final instance = await rig.instance();
    // Twelve newly added workshop mods, none staged.
    await rig.setMods(instance, [for (final id in ids) ModSpec(id)]);
    expect(serverEntries(instance), isEmpty);

    final op = rig.daemon.instances.start(instance.id);
    final done = await rig.daemon.operations.whenDone(op.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    final steps = await rig.steps(done);
    expect(steps, contains('stage_mods'));
    expect(
      steps.indexOf('stage_mods'),
      lessThan(steps.indexOf('spawn')),
      reason: 'the mods are staged before the server starts',
    );
    // The 12 items were downloaded, and each is linked under its name.
    expect(rig.steam.downloaded.expand((run) => run), unorderedEquals(ids));
    for (final (i, id) in ids.indexed) {
      expect(
        linksTo(
          rig.staged(instance, '@Mod-$i'),
          rig.versionDir(id, '1700000000'),
        ),
        isTrue,
        reason: 'mod $i is linked to its version',
      );
    }
    // The keys of the mods are in place, and the arguments follow the order.
    expect(rig.keys(instance), hasLength(12));
    expect(
      rig.launchArgs,
      contains('-mod=${[for (var i = 0; i < 12; i++) '@Mod-$i'].join(';')}'),
    );
    expect(rig.current(instance).state, InstanceState.running);
    final listed = (await rig.list(instance)).mods;
    expect(listed.map((m) => m.status).toSet(), {'staged'});
  });

  test('add_while_running', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF');
    final instance = await rig.instance();
    await runStart(rig.daemon, instance.id);
    final before = serverEntries(instance);

    await rig.setMods(instance, [ModSpec(cfMod)]);

    // The mod list shows it as pending, and the instance directory is as it
    // was: nothing is downloaded or staged.
    final listed = await rig.mod(instance, cfMod);
    expect(listed.status, 'pending');
    expect(serverEntries(instance), before);
    expect(rig.steam.downloaded, isEmpty);
    expect(rig.current(instance).state, InstanceState.running);

    // It is staged on the next start.
    await runStop(rig.daemon, instance.id);
    final start = await runStart(rig.daemon, instance.id);
    expect(
      start.status,
      OperationStatus.succeeded,
      reason: start.resultMessage,
    );
    expect(isLink(rig.staged(instance, '@CF')), isTrue);
    expect(rig.launchArgs, contains('-mod=@CF'));
    expect((await rig.mod(instance, cfMod)).status, 'staged');
  });

  test('applymods_while_running', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF');
    final instance = await rig.instance();
    await rig.setMods(instance, [ModSpec(cfMod)]);
    await runStart(rig.daemon, instance.id);
    final operations = rig.daemon.operations
        .listForInstance(instance.id)
        .length;

    final error = await failureOf(rig.apply(instance));

    expect(error.code, StatusCode.failedPrecondition);
    expect(errorDetailOf(error)?.reason, 'instance_running');
    // No operation was created.
    expect(
      rig.daemon.operations.listForInstance(instance.id),
      hasLength(operations),
    );
  });

  test('apply_mods_stages_a_stopped_instance', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF');
    final instance = await rig.instance();
    await rig.setMods(instance, [ModSpec(cfMod)]);

    final done = await rig.apply(instance);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(done.kind.wireName, 'apply_mods');
    expect(await rig.steps(done), contains('stage_mods'));
    expect(isLink(rig.staged(instance, '@CF')), isTrue);
    expect(rig.current(instance).state, InstanceState.stopped);
    expect(rig.env.process.launches, isEmpty);
  });
}
