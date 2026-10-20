import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/content/content.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/steam/steam.dart';

import '../support/content_support.dart';
import '../support/daemon_support.dart';

void main() {
  group('who holds the lock and the slot', () {
    test(
      'a_waiting_operation_reports_its_position_and_holds_nothing',
      () async {
        final rig = await ContentRig.start(heavySlots: 1);
        rig.item(cfMod);
        // Someone else uses the anonymous installation.
        final release = await rig.runner.acquireHeavy(slot: false);

        final op = rig.acquire('inst-a', [cfMod], requireAll: true);
        await eventually(
          () => rig.runner.get(op.id)!.currentStep == 'waiting_for_steamcmd',
          reason: 'the operation waits for the installation',
        );
        final view = rig.runner.get(op.id)!;
        expect(view.status, OperationStatus.running);
        expect(view.queuePosition, 1);
        // The only heavy slot is free: the waiting operation took none.
        final other = await rig.runner
            .acquireHeavy(installation: 'someone-else')
            .timeout(const Duration(seconds: 2));
        other();

        release();
        expect((await rig.finished(op)).status, OperationStatus.succeeded);
        expect(rig.workshopRuns(), hasLength(1));
      },
    );

    test('runs_of_different_installations_use_the_host_slots', () async {
      final rig = await ContentRig.start(
        heavySlots: 1,
        fakeEnvironment: {
          'FAKE_STEAMCMD_DELAY_MS': '100',
          'FAKE_STEAMCMD_WORKSHOP_PROGRESS': '1',
        },
      );
      rig.installAccount('acct_aaaaaaaaaaaa');
      rig.item('601');
      rig.item('602');
      SteamAccountUse use(String id) => SteamAccountUse(id, 'user', () => null);

      final a = rig.acquire('inst-a', ['601']);
      final b = rig.acquire('inst-b', [
        '602',
      ], account: use('acct_aaaaaaaaaaaa'));
      await eventually(
        () => rig.workshopRuns().isNotEmpty,
        reason: 'the first run started',
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        rig.workshopRuns(),
        hasLength(1),
        reason: 'one host slot: the second run waits for it',
      );
      expect(
        rig.runner.get(b.id)!.currentStep,
        'waiting_for_steamcmd',
        reason: 'and its operation shows the wait',
      );

      await rig.finished(a);
      await rig.finished(b);
      expect(rig.workshopRuns(), hasLength(2));
    });
  });

  group('disk', () {
    test('items_that_fit_are_downloaded_when_the_next_does_not', () async {
      // 2 x 4096 fits in 9000 free bytes; 2 x 8192 does not.
      final rig = await ContentRig.start(freeBytes: 9000);
      rig.item('701', size: 4096);
      rig.item('702', size: 4096);

      final op = rig.acquire('inst-a', ['701', '702']);
      await rig.finished(op);

      final result = rig.results[op.id]!;
      expect(result['701'].ok, isTrue);
      expect(result['702'].error!.reason, 'insufficient_disk');
      expect(
        (rig.workshopRuns().single['args']! as List).cast<String>(),
        allOf(contains('701'), isNot(contains('702'))),
      );
    });
  });

  group('prompts in pipeline runs', () {
    /// A SteamCMD that asks for a Steam Guard code before it downloads.
    Future<(ContentRig, ScriptedWorkshopSteam, List<CancelToken>)>
    promptingRig() async {
      final seen = <CancelToken>[];
      late ScriptedWorkshopSteam steam;
      final rig = await ContentRig.start(
        steamFactory: (root) => steam = ScriptedWorkshopSteam(root, (
          request,
          reporter,
          cancel,
        ) async {
          seen.add(cancel);
          reporter.step('steam_login');
          final ticket = reporter.prompt(
            const PromptSpec(
              kind: 'email',
              message: 'Enter the code',
              steamAccount: 'srvadmin',
              wait: Duration(minutes: 15),
            ),
          );
          final result = await Future.any([
            ticket.result,
            cancel.whenCancelled.then(
              (_) => const PromptResult(PromptOutcome.cancelled),
            ),
          ]);
          if (result.outcome != PromptOutcome.answered) {
            ticket.close(PromptOutcome.cancelled);
            throw const OperationCancelled();
          }
          for (final item in request.items) {
            steam.writeItem('anonymous', request.workshopAppId, item);
          }
          return [
            for (final item in request.items) SteamWorkshopItemResult(item),
          ];
        }),
      );
      return (rig, steam, seen);
    }

    test('one_prompt_serves_every_waiter_of_the_run', () async {
      final (rig, steam, _) = await promptingRig();
      rig.item(cfMod);
      final a = rig.acquire('inst-a', [cfMod], requireAll: true);
      final b = rig.acquire('inst-b', [cfMod], requireAll: true);

      await eventually(
        () => rig.runner.prompts.snapshot().any((s) => s.subjects.length == 2),
        reason: 'both operations are attached to the one prompt',
      );
      final pending = rig.runner.prompts.snapshot();
      expect(pending, hasLength(1), reason: 'published once');
      final promptId = pending.single.prompt.id;
      expect(rig.runner.prompts.pendingFor(a.id)!.id, promptId);
      expect(rig.runner.prompts.pendingFor(b.id)!.id, promptId);
      for (final op in [a, b]) {
        final view = rig.runner.get(op.id)!;
        expect(view.status, OperationStatus.waitingForInput);
        expect(view.pendingPrompt!.id, promptId);
      }
      expect(steam.runs, hasLength(1));

      // Either operation id answers it; the first answer wins.
      rig.runner.respondToPrompt(b.id, promptId, '12345', 'device-2');
      await expectLater(
        () => rig.runner.respondToPrompt(a.id, promptId, '67890', 'device-1'),
        throwsA(
          isA<Object>().having(
            (e) => '$e',
            'reason',
            contains('prompt_resolved'),
          ),
        ),
      );
      expect((await rig.finished(a)).status, OperationStatus.succeeded);
      expect((await rig.finished(b)).status, OperationStatus.succeeded);
      expect(rig.runner.prompts.snapshot(), isEmpty);
    });

    test('a_cancelled_waiter_only_detaches_from_the_prompt', () async {
      final (rig, _, seen) = await promptingRig();
      rig.item(cfMod);
      final a = rig.acquire('inst-a', [cfMod], requireAll: true);
      final b = rig.acquire('inst-b', [cfMod], requireAll: true);
      await eventually(
        () => rig.runner.prompts.snapshot().any((s) => s.subjects.length == 2),
        reason: 'both are attached',
      );
      final promptId = rig.runner.prompts.snapshot().single.prompt.id;

      rig.runner.cancel(a.id);
      expect((await rig.finished(a)).status, OperationStatus.cancelled);

      final left = rig.runner.prompts.snapshot();
      expect(left, hasLength(1), reason: 'the prompt is still pending');
      expect(left.single.prompt.id, promptId);
      expect([for (final s in left.single.subjects) s.operationId], [b.id]);
      expect(seen.single.isCancelled, isFalse, reason: 'the run goes on');

      rig.runner.respondToPrompt(b.id, promptId, '12345', 'device-1');
      expect((await rig.finished(b)).status, OperationStatus.succeeded);
    });

    test('the_prompt_is_cancelled_with_the_run', () async {
      final (rig, _, seen) = await promptingRig();
      rig.item(cfMod);
      final a = rig.acquire('inst-a', [cfMod]);
      final b = rig.acquire('inst-b', [cfMod]);
      await eventually(
        () => rig.runner.prompts.snapshot().any((s) => s.subjects.length == 2),
        reason: 'both are attached',
      );
      final events = <PromptBrokerEvent>[];
      final sub = rig.runner.prompts.events.listen(events.add);
      addTearDown(sub.cancel);

      rig.runner.cancel(a.id);
      await rig.finished(a);
      rig.runner.cancel(b.id);
      await rig.finished(b);

      expect(seen.single.isCancelled, isTrue, reason: 'the last waiter left');
      expect(rig.runner.prompts.snapshot(), isEmpty);
      expect(events.whereType<PromptResolved>().map((e) => e.outcome), [
        PromptOutcome.cancelled,
      ], reason: 'resolved once, cancelled, when the run ended');
      expect(rig.publishedVersions(cfMod), isEmpty);
    });

    test('a_waiter_that_joins_a_pending_prompt_sees_it', () async {
      final (rig, _, _) = await promptingRig();
      rig.item(cfMod);
      final a = rig.acquire('inst-a', [cfMod], requireAll: true);
      await eventually(
        () => rig.runner.prompts.snapshot().isNotEmpty,
        reason: 'the prompt is raised',
      );
      final b = rig.acquire('inst-b', [cfMod], requireAll: true);
      await eventually(
        () => rig.runner.prompts.pendingFor(b.id) != null,
        reason: 'the late waiter is attached to the same prompt',
      );
      expect(rig.runner.prompts.snapshot(), hasLength(1));
      final events = await Future.any([
        rig.runner
            .watch(b.id)
            .firstWhere((e) => e is PromptRaisedEvent)
            .then((_) => true),
        Future<bool>.delayed(const Duration(seconds: 3), () => false),
      ]);
      expect(events, isTrue, reason: 'its own watchers get the prompt');

      final promptId = rig.runner.prompts.snapshot().single.prompt.id;
      rig.runner.respondToPrompt(a.id, promptId, 'ABCDE', 'device-1');
      await rig.finished(a);
      await rig.finished(b);
    });
  });

  group('store', () {
    test('startup_deletes_the_staging_area_and_collects', () async {
      final rig = await ContentRig.start();
      rig.item('801');
      final op = rig.acquire('inst-a', ['801'], requireAll: true);
      await rig.finished(op);
      Directory(p.join(rig.data.contentStagingPath, 'run-dead', 'x'))
          .createSync(recursive: true);

      rig.store.startup();
      expect(rig.stagingLeftovers(), isEmpty);
      rig.clock.advance(const Duration(days: 8));
      rig.store.collect();
      expect(rig.publishedVersions('801'), isEmpty);
    });

    test('collection_runs_again_on_its_own', () async {
      final rig = await ContentRig.start();
      rig.item('802');
      await rig.finished(rig.acquire('inst-a', ['802'], requireAll: true));
      final store = ContentStore(
        database: rig.db,
        contentPath: rig.data.contentPath,
        clock: rig.clock.call,
        collectionInterval: const Duration(milliseconds: 50),
      );
      addTearDown(store.close);
      store.startup();
      expect(rig.publishedVersions('802'), isNotEmpty);

      rig.clock.advance(const Duration(days: 8));
      await eventually(
        () => rig.publishedVersions('802').isEmpty,
        reason: 'the timer collected it',
      );
    });

    test('a_published_version_is_never_overwritten', () async {
      final rig = await ContentRig.start();
      rig.item('803');
      final first = rig.acquire('inst-a', ['803'], requireAll: true);
      await rig.finished(first);
      final path = rig.results[first.id]!['803'].path;
      final marker = File(p.join(path, 'marker.txt'))
        ..writeAsStringSync('mine');
      // The row is lost (a crash after the rename, before the insert).
      rig.db.sqlite.execute('DELETE FROM content_versions');

      final second = rig.acquire('inst-b', ['803'], requireAll: true);
      await rig.finished(second);

      expect(marker.readAsStringSync(), 'mine');
      expect(rig.rows(), ['803/1700000000'], reason: 'adopted, not replaced');
      expect(rig.stagingLeftovers(), isEmpty);
    });
  });
}
