import 'package:grpc/grpc.dart';
import 'package:test/test.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/api_support.dart';
import '../support/daemon_support.dart';
import '../support/content_support.dart';
import '../support/mods_support.dart';

void main() {
  test('reorder_changes_launch_order', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF');
    rig.item(vppMod, title: 'VPPAdminTools');
    rig.item(thirdMod, title: 'Dabs');
    final instance = await rig.instance();
    await rig.setMods(instance, [
      ModSpec(cfMod),
      ModSpec(vppMod),
      ModSpec(thirdMod, role: 'server'),
    ]);

    final first = await runStart(rig.daemon, instance.id);

    expect(
      first.status,
      OperationStatus.succeeded,
      reason: first.resultMessage,
    );
    expect(rig.launchArgs, contains('-mod=@CF;@VPPAdminTools'));
    // One list per role: the server role has its own argument.
    expect(rig.launchArgs, contains('-serverMod=@Dabs'));
    await runStop(rig.daemon, instance.id);

    // @VPPAdminTools moves before @CF in the client role.
    final listed = await rig.setMods(instance, [
      ModSpec(vppMod),
      ModSpec(cfMod),
      ModSpec(thirdMod, role: 'server'),
    ]);
    expect(
      [for (final m in listed.mods) m.itemId],
      [vppMod, cfMod, thirdMod],
      reason: 'ListMods keeps the load order',
    );
    final second = await runStart(rig.daemon, instance.id);

    expect(
      second.status,
      OperationStatus.succeeded,
      reason: second.resultMessage,
    );
    expect(rig.launchArgs, contains('-mod=@VPPAdminTools;@CF'));
    expect(rig.launchArgs, contains('-serverMod=@Dabs'));
    // Reordering downloads nothing.
    expect(rig.steam.downloaded, hasLength(1));
  });

  test('unknown_role', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF');
    final instance = await rig.instance();
    await rig.setMods(instance, [ModSpec(cfMod)]);
    final before = await rig.list(instance);
    final revision = rig.current(instance).revision;

    // The plugin declares the roles client and server.
    final error = await failureOf(
      rig.setMods(instance, [ModSpec(cfMod, role: 'both')]),
    );

    expect(error.code, StatusCode.invalidArgument);
    expect(errorDetailOf(error)?.reason, 'mod_role_invalid');
    expect(
      error.message,
      allOf(contains('both'), contains('client'), contains('server')),
    );
    // The mod list and the revision are unchanged.
    expect(
      [for (final m in (await rig.list(instance)).mods) (m.itemId, m.role)],
      [for (final m in before.mods) (m.itemId, m.role)],
    );
    expect(rig.current(instance).revision, revision);
  });

  test('too_many_mods_refused', () async {
    final rig = await ModsRig.start();
    final instance = await rig.instance();
    final revision = rig.current(instance).revision;

    // 256 mods are the most an instance keeps.
    await expectLater(
      rig.setMods(instance, [
        for (var i = 0; i < 257; i++) ModSpec('${3000000 + i}'),
      ]),
      failsWithStatus(StatusCode.invalidArgument, 'too_many_mods'),
    );

    expect(rig.current(instance).revision, revision);
    expect((await rig.list(instance)).mods, isEmpty);
    // The refused call asked the workshop for nothing.
    expect(rig.workshop.requests, isEmpty);
  });

  test('stale_revision_refused', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF');
    final instance = await rig.instance();
    final stale = rig.current(instance).revision;
    await rig.setMods(instance, [ModSpec(cfMod)]);

    await expectLater(
      rig.setMods(instance, [], expectedRevision: stale),
      failsWithStatus(StatusCode.failedPrecondition, 'revision_conflict'),
    );

    expect((await rig.list(instance)).mods, hasLength(1));
    expect(rig.current(instance).revision, stale + 1);
  });
}
