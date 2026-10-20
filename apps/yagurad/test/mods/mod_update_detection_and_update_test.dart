import 'dart:io';

import 'package:test/test.dart';
import 'package:yagurad/src/mods/mod_check_schedule.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/content_support.dart';
import '../support/daemon_support.dart';
import '../support/mods_support.dart';

const oldVersion = '1700000000';
const newVersion = '1700500000';

void main() {
  test('update_available_flagged', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF', updated: 1700000000);
    final instance = await rig.instance();
    await rig.setMods(instance, [ModSpec(cfMod)]);
    expect((await rig.apply(instance)).status, OperationStatus.succeeded);
    expect((await rig.mod(instance, cfMod)).updateAvailable, isFalse);

    // The workshop reports a newer time_updated for the staged mod.
    rig.workshop.items[cfMod]!.timeUpdated = 1700500000;
    final check = await rig.checkUpdates(instance);

    expect(
      check.status,
      OperationStatus.succeeded,
      reason: check.resultMessage,
    );
    expect(check.kind.wireName, 'check_mod_updates');
    final listed = await rig.list(instance);
    final mod = listed.mods.single;
    expect(mod.updateAvailable, isTrue);
    expect(mod.remoteUpdated.seconds.toInt(), 1700500000);
    expect(mod.localUpdated.seconds.toInt(), 1700000000);
    expect(listed.updateCheck, 'ok');
    expect(listed.hasCheckedAt(), isTrue);
    // Flagging changes nothing on disk: the link still points at the old
    // version, and the new one is not downloaded.
    expect(
      linksTo(rig.staged(instance, '@CF'), rig.versionDir(cfMod, oldVersion)),
      isTrue,
    );
    expect(rig.steam.downloaded, hasLength(1));
  });

  test('only_changed_mods_re_staged', () async {
    final rig = await ModsRig.start();
    final ids = [for (var i = 0; i < 12; i++) '${2000000 + i}'];
    for (final (i, id) in ids.indexed) {
      rig.item(id, title: 'Mod $i');
    }
    final instance = await rig.instance();
    await rig.setMods(instance, [for (final id in ids) ModSpec(id)]);
    expect((await rig.apply(instance)).status, OperationStatus.succeeded);
    final before = {
      for (final (i, _) in ids.indexed)
        '@Mod-$i': resolvedTarget(rig.staged(instance, '@Mod-$i')),
    };

    // One of the twelve has a newer version.
    rig.workshop.items[ids[5]]!.timeUpdated = 1700500000;
    await rig.checkUpdates(instance);
    final updated = await rig.updateMods(instance);

    expect(
      updated.status,
      OperationStatus.succeeded,
      reason: updated.resultMessage,
    );
    expect(updated.kind.wireName, 'update_mods');
    // Only that mod was downloaded, and only its link changed.
    expect(rig.steam.downloaded, hasLength(2));
    expect(rig.steam.downloaded.last, [ids[5]]);
    for (final (i, id) in ids.indexed) {
      final name = '@Mod-$i';
      if (id == ids[5]) {
        expect(
          linksTo(rig.staged(instance, name), rig.versionDir(id, newVersion)),
          isTrue,
        );
      } else {
        expect(resolvedTarget(rig.staged(instance, name)), before[name]);
      }
    }
    final mod = await rig.mod(instance, ids[5]);
    expect(mod.updateAvailable, isFalse);
    expect(mod.stagedVersion, newVersion);
    expect(mod.desiredVersion, newVersion);
    // The old version stays next to the new one until nothing uses it.
    expect(Directory(rig.versionDir(ids[5], oldVersion)).existsSync(), isTrue);
  });

  test('update_of_a_running_instance_is_staged_at_the_next_start', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF');
    final instance = await rig.instance();
    await rig.setMods(instance, [ModSpec(cfMod)]);
    await runStart(rig.daemon, instance.id);
    rig.workshop.items[cfMod]!.timeUpdated = 1700500000;
    await rig.checkUpdates(instance);

    final updated = await rig.updateMods(instance, [cfMod]);

    expect(
      updated.status,
      OperationStatus.succeeded,
      reason: updated.resultMessage,
    );
    // The new version is downloaded and desired; the staged one stays linked.
    final mod = await rig.mod(instance, cfMod);
    expect(mod.desiredVersion, newVersion);
    expect(mod.stagedVersion, oldVersion);
    expect(
      linksTo(rig.staged(instance, '@CF'), rig.versionDir(cfMod, oldVersion)),
      isTrue,
    );
    await runStop(rig.daemon, instance.id);
    await runStart(rig.daemon, instance.id);
    expect(
      linksTo(rig.staged(instance, '@CF'), rig.versionDir(cfMod, newVersion)),
      isTrue,
    );
    expect((await rig.mod(instance, cfMod)).stagedVersion, newVersion);
  });

  test('update_check_cannot_reach_steam', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF');
    final instance = await rig.instance();
    await rig.setMods(instance, [ModSpec(cfMod)]);
    await rig.apply(instance);
    rig.workshop.items[cfMod]!.timeUpdated = 1700500000;
    await rig.checkUpdates(instance);
    expect((await rig.mod(instance, cfMod)).updateAvailable, isTrue);

    // The metadata request fails.
    rig.workshop.failWith.add(500);
    final check = await rig.checkUpdates(instance);

    // The mod keeps its previous flag, and the check says it is unknown, with
    // the error.
    expect(check.status, OperationStatus.succeeded);
    expect(check.resultReason, 'update_check_unknown');
    expect(check.resultMessage, contains('500'));
    final listed = await rig.list(instance);
    expect(listed.updateCheck, 'unknown');
    expect(listed.mods.single.updateAvailable, isTrue);
    expect(listed.mods.single.remoteUpdated.seconds.toInt(), 1700500000);

    // The next successful check makes it known again.
    expect(
      (await rig.checkUpdates(instance)).resultReason,
      isNot('update_check_unknown'),
    );
    expect((await rig.list(instance)).updateCheck, 'ok');
  });

  test('failed_scheduled_check_is_retried_with_backoff', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF');
    final instance = await rig.instance();
    await rig.setMods(instance, [ModSpec(cfMod)]);
    await rig.apply(instance);
    final asked = rig.workshop.requests.length;

    // The daemon starts again with the timer on: first check after 50 ms, and
    // after a failure again after 100 ms, 200 ms, then 400 ms (the cap).
    rig.workshop.failWith.addAll(List.filled(100, 500));
    await rig.restart(
      schedule: const ModCheckSchedule(
        first: Duration(milliseconds: 50),
        interval: Duration(hours: 1),
        jitter: Duration.zero,
        backoffStart: Duration(milliseconds: 100),
        backoffMax: Duration(milliseconds: 400),
      ),
    );
    await eventually(
      () => rig.workshop.requests.length >= asked + 4,
      reason: 'four checks',
    );

    final requests = rig.workshop.requests.skip(asked).toList();
    final gaps = [
      for (var i = 1; i < requests.length; i++)
        requests[i].at.difference(requests[i - 1].at),
    ];
    expect(gaps[0], greaterThanOrEqualTo(const Duration(milliseconds: 90)));
    expect(gaps[1], greaterThanOrEqualTo(const Duration(milliseconds: 190)));
    expect(gaps[2], greaterThanOrEqualTo(const Duration(milliseconds: 390)));
    expect((await rig.list(instance)).updateCheck, 'unknown');
  });

  test('schedule_gaps', () {
    const schedule = ModCheckSchedule();
    expect(schedule.first, const Duration(minutes: 10));
    expect(schedule.interval, const Duration(hours: 6));
    expect(schedule.jitter, const Duration(minutes: 30));
    expect(schedule.backoff(1), const Duration(minutes: 5));
    expect(schedule.backoff(2), const Duration(minutes: 10));
    expect(schedule.backoff(3), const Duration(minutes: 20));
    expect(schedule.backoff(20), const Duration(hours: 6));
  });
}
