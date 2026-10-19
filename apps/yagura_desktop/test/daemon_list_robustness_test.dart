import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yagura_desktop/src/credentials.dart';
import 'package:yagura_desktop/src/daemon_record.dart';
import 'package:yagura_desktop/src/pairing.dart';
import 'package:yagura_desktop/src/providers.dart';

import 'support/fake_world.dart';
import 'support/pairing_ui.dart';

void main() {
  group('a list that cannot be saved', () {
    testWidgets('pairing_is_refused_and_nothing_stays_behind', (tester) async {
      final world = World();
      final host = world.addHost('alpha');
      world.store.saveFailure = const FileSystemException('disk is read-only');
      await world.pump(tester);

      await pairThroughTheUi(tester, host.pairingString());

      // The dialog says so, the daemon is not listed, and the key and
      // certificate that were issued are gone again.
      expect(pairingError(tester), contains('daemon_list_unsaved'));
      expect(pairingError(tester), contains('disk is read-only'));
      expect(daemonCard('alpha'), findsNothing);
      expect(world.store.records, isEmpty);
      expect(world.keychain.entries, isEmpty);
    });

    testWidgets('removing_keeps_the_daemon_when_the_save_fails', (
      tester,
    ) async {
      final world = World();
      final host = world.addHost('alpha');
      await world.prePair(host);
      await world.pump(tester);
      world.store.saveFailure = const FileSystemException('disk is read-only');

      await tester.tap(find.byKey(const ValueKey('daemon:alpha:remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remove:confirm')));
      await settleAll(tester);

      expect(daemonCard('alpha'), findsOneWidget);
      expect(find.textContaining('was not removed'), findsOneWidget);
      expect(await CredentialStore(world.keychain).load('alpha'), isNotNull);
    });
  });

  group('writes of the list', () {
    testWidgets('a_last_seen_write_racing_pairing_loses_nothing', (
      tester,
    ) async {
      final world = World();
      final alpha = world.addHost('alpha');
      final bravo = world.addHost('bravo', host: '10.0.0.3');
      await world.prePair(alpha);
      await world.pump(tester);
      final registry = world.container.read(daemonRegistryProvider.notifier);

      // A last-seen write is in flight (blocked in the store) while a
      // daemon is paired.
      final later = kTestNow.add(const Duration(hours: 3));
      final gate = world.store.saveGate = Completer<void>();
      final seen = registry.markSeen('alpha', later);
      await tester.pump();
      final paired = registry.pair(bravo.pairingString(), 'laptop');
      await settleAll(tester);
      gate.complete();
      world.store.saveGate = null;
      await settleAll(tester);
      await Future.wait([seen, paired]);

      // The saved list has both, with the new last-seen time.
      expect([for (final d in world.store.records) d.id], ['alpha', 'bravo']);
      expect(world.store.records.first.lastSeen, later);
      expect(
        [for (final d in world.container.read(daemonRegistryProvider)) d.id],
        ['alpha', 'bravo'],
      );
      expect(await CredentialStore(world.keychain).load('bravo'), isNotNull);
    });

    testWidgets('a_last_seen_write_racing_removal_does_not_bring_it_back', (
      tester,
    ) async {
      final world = World();
      final alpha = world.addHost('alpha');
      await world.prePair(alpha);
      await world.pump(tester);
      final registry = world.container.read(daemonRegistryProvider.notifier);

      final gate = world.store.saveGate = Completer<void>();
      final seen = registry.markSeen(
        'alpha',
        kTestNow.add(const Duration(hours: 1)),
      );
      await tester.pump();
      final removed = registry.remove('alpha');
      await tester.pump();
      gate.complete();
      world.store.saveGate = null;
      await settleAll(tester);
      await Future.wait([seen, removed]);

      expect(world.store.records, isEmpty);
      expect(world.container.read(daemonRegistryProvider), isEmpty);
    });
  });

  group('leftover key material', () {
    testWidgets('startup_removes_orphans', (tester) async {
      final world = World();
      final host = world.addHost('alpha');
      await world.prePair(host);
      final store = CredentialStore(world.keychain);
      // A renewal interrupted for the listed daemon, and a pairing for a
      // daemon that never got listed.
      await store.writePendingKey('alpha', 'half-done');
      await store.writePendingKey('ghost', 'half-done');
      await store.save('ghost', (await store.load('alpha'))!);

      await world.pump(tester);

      expect(world.keychain.entries.keys, contains('yagura.alpha.device'));
      expect(
        world.keychain.entries.keys.where(
          (k) => k.contains('pending') || k.contains('ghost'),
        ),
        isEmpty,
      );
      expect(world.stateOf(tester, 'alpha'), 'connected');
    });

    testWidgets('nothing_unlisted_is_removed_while_entries_are_unreadable', (
      tester,
    ) async {
      final world = World();
      final host = world.addHost('alpha');
      await world.prePair(host);
      final store = CredentialStore(world.keychain);
      // `ghost` may belong to the entry that could not be read.
      await store.save('ghost', (await store.load('alpha'))!);
      await store.writePendingKey('ghost', 'half-done');
      world.store.unreadable = 1;

      await world.pump(tester);

      expect(world.keychain.entries.keys, contains('yagura.ghost.device'));
      expect(
        world.keychain.entries.keys.where((k) => k.contains('pending')),
        isEmpty,
      );
    });

    testWidgets('a_late_failure_leaves_no_device_entry', (tester) async {
      final world = World();
      final host = world.addHost('alpha');
      // The enrollment and the save succeed; deleting the pending key then
      // fails.
      world.keychain.failDeleteContaining = 'pending-key';
      await world.pump(tester);

      await pairThroughTheUi(tester, host.pairingString());

      expect(pairingError(tester), contains('keychain_unavailable'));
      expect(daemonCard('alpha'), findsNothing);
      expect(
        world.keychain.entries.keys,
        isNot(contains('yagura.alpha.device')),
      );
    });
  });

  group('daemons.json', () {
    late Directory dir;
    late File file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('yagura_list_');
      file = File('${dir.path}/daemons.json');
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    Map<String, Object?> entry(String id) => {
      'id': id,
      'name': 'Host $id',
      'host': '10.0.0.2',
      'port': 7443,
      'ca_fingerprint': 'ab' * 32,
    };

    test('one_malformed_entry_costs_only_itself', () async {
      final bad = {'id': 'broken', 'port': 'seven'};
      file.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'daemons': [entry('alpha'), bad, entry('bravo')],
        }),
      );
      final store = FileDaemonListStore(file);

      final loaded = await store.load();
      expect([for (final d in loaded.daemons) d.id], ['alpha', 'bravo']);
      expect(loaded.unreadable, 1);
      expect(loaded.clean, isFalse);

      // Saving after a change writes the bad entry back, not away.
      await store.save([
        ...loaded.daemons,
        DaemonRecord.fromJson(entry('charlie')),
      ]);
      final saved = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(
        [for (final d in saved['daemons']! as List) (d as Map)['id']],
        ['alpha', 'bravo', 'charlie'],
      );
      expect(saved['unreadable'], [bad]);

      // And the next session still reports it.
      final again = await FileDaemonListStore(file).load();
      expect(again.daemons, hasLength(3));
      expect(again.unreadable, 1);
    });

    test('a_file_that_is_not_json_is_kept_aside', () async {
      file.writeAsStringSync('{"daemons": [');
      final store = FileDaemonListStore(file);

      final loaded = await store.load();

      expect(loaded.damaged, isTrue);
      expect(loaded.daemons, isEmpty);
      expect(File('${file.path}.damaged').readAsStringSync(), '{"daemons": [');
    });

    test('last_seen_round_trips', () async {
      final store = FileDaemonListStore(file);
      final seen = DateTime.utc(2026, 10, 19, 12);
      await store.save([
        DaemonRecord.fromJson(entry('alpha')).copyWith(lastSeen: seen),
      ]);

      final loaded = await FileDaemonListStore(file).load();

      expect(loaded.daemons.single.lastSeen, seen.toLocal());
      expect(loaded.clean, isTrue);
    });

    testWidgets('the_unreadable_entries_are_surfaced', (tester) async {
      final world = World();
      final host = world.addHost('alpha');
      await world.prePair(host);
      world.store.unreadable = 2;
      await world.pump(tester);

      expect(find.byKey(const ValueKey('daemons:problem')), findsOneWidget);
      expect(find.textContaining('2 saved daemon entries'), findsOneWidget);
      // The readable daemon is listed and works.
      expect(world.stateOf(tester, 'alpha'), 'connected');
    });

    test('a_damaged_file_that_cannot_be_copied_is_never_overwritten', () async {
      file.writeAsStringSync('{"daemons": [');
      // The first copy name is taken by something that cannot be written.
      Directory('${file.path}.damaged').createSync();
      final store = FileDaemonListStore(file);

      final loaded = await store.load();

      expect(loaded.damaged, isTrue);
      expect(loaded.copied, isFalse);
      await expectLater(
        store.save([DaemonRecord.fromJson(entry('alpha'))]),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'message',
            contains('could not be copied aside'),
          ),
        ),
      );
      expect(file.readAsStringSync(), '{"daemons": [');
    });

    test('the_copy_exists_before_the_next_save_and_is_not_reused', () async {
      file.writeAsStringSync('{"daemons": [');
      File('${file.path}.damaged').writeAsStringSync('an older copy');
      final store = FileDaemonListStore(file);

      final loaded = await store.load();

      expect(loaded.copied, isTrue);
      expect(File('${file.path}.damaged').readAsStringSync(), 'an older copy');
      expect(
        File('${file.path}.damaged.1').readAsStringSync(),
        '{"daemons": [',
      );
      await store.save([DaemonRecord.fromJson(entry('alpha'))]);
      expect((await FileDaemonListStore(file).load()).daemons, hasLength(1));

      // Loading the same damaged file again reuses its copy.
      file.writeAsStringSync('{"daemons": [');
      await FileDaemonListStore(file).load();
      expect(File('${file.path}.damaged.2').existsSync(), isFalse);
    });

    test('a_locked_file_is_not_treated_as_damaged', () async {
      final text = jsonEncode({
        'version': 1,
        'daemons': [entry('alpha')],
      });
      file.writeAsStringSync(text);
      var locked = true;
      Future<String> read(File f) async {
        if (locked) {
          throw const FileSystemException(
            'The process cannot access the file because it is being used',
          );
        }
        return f.readAsString();
      }

      final store = FileDaemonListStore(file, readText: read);

      final loaded = await store.load();

      // Not damaged: no copy, nothing deleted, and no saving.
      expect(loaded.damaged, isFalse);
      expect(loaded.readError, contains('being used'));
      expect(loaded.clean, isFalse);
      expect(File('${file.path}.damaged').existsSync(), isFalse);
      await expectLater(
        store.save([DaemonRecord.fromJson(entry('bravo'))]),
        throwsA(isA<FileSystemException>()),
      );
      expect(file.readAsStringSync(), text);

      // The next start reads it.
      locked = false;
      final again = await store.load();
      expect(again.readError, isNull);
      expect(again.clean, isTrue);
      expect([for (final d in again.daemons) d.id], ['alpha']);
      await store.save(again.daemons);
    });

    test(
      'unreadable_entries_are_named_and_so_are_those_over_the_cap',
      () async {
        final entries = [
          {'id': 'old', 'name': 'Old NAS', 'port': 'seven'},
          {'nothing': 'known'},
          for (var i = 0; i < kMaxDaemons; i++) entry('d$i'),
          entry('over-cap'),
        ];
        file.writeAsStringSync(jsonEncode({'version': 1, 'daemons': entries}));

        final loaded = await FileDaemonListStore(file).load();

        expect(loaded.daemons, hasLength(kMaxDaemons));
        expect(loaded.unreadable, 2);
        expect(loaded.overCapNames, ['Host over-cap']);
        expect(loaded.unreadableNames, ['Old NAS']);
      },
    );

    test('damaged_copies_are_found_and_deleted_on_request', () async {
      file.writeAsStringSync(
        jsonEncode({'version': 1, 'daemons': <Object?>[]}),
      );
      File('${file.path}.damaged').writeAsStringSync('x');
      File('${file.path}.damaged.1').writeAsStringSync('y');
      final store = FileDaemonListStore(file);

      final loaded = await store.load();
      expect(loaded.damagedCopies, 2);
      expect(loaded.clean, isFalse);

      await store.discardDamagedCopies();
      final again = await store.load();
      expect(again.damagedCopies, 0);
      expect(again.clean, isTrue);
    });

    test('over_cap_daemons_stay_over_the_cap_across_saves', () async {
      file.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'daemons': [for (var i = 0; i < kMaxDaemons + 1; i++) entry('d$i')],
        }),
      );
      final store = FileDaemonListStore(file);
      final first = await store.load();
      expect(first.overCapNames, ['Host d32']);
      expect(first.unreadable, 0);

      await store.save(first.daemons);
      final saved = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(saved.containsKey('unreadable'), isFalse);
      expect(saved['over_cap'], hasLength(1));

      // Still over the cap after a reload, and never "unreadable".
      final again = await FileDaemonListStore(file).load();
      expect(again.overCapNames, ['Host d32']);
      expect(again.unreadable, 0);
      expect(again.clean, isFalse);

      // With a free place it is listed again.
      await store.save(first.daemons.skip(1).toList());
      final room = await FileDaemonListStore(file).load();
      expect(room.daemons, hasLength(kMaxDaemons));
      expect(room.overCapNames, isEmpty);
      expect(room.clean, isTrue);
    });

    test('discarded_entries_leave_the_file', () async {
      final bad = {'id': 'broken'};
      file.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'daemons': [entry('alpha'), bad],
        }),
      );
      final store = FileDaemonListStore(file);
      final loaded = await store.load();
      expect(loaded.unreadable, 1);

      store.discardUnreadable();
      await store.save(loaded.daemons);

      final again = await FileDaemonListStore(file).load();
      expect(again.clean, isTrue);
      expect(again.daemons, hasLength(1));
      expect(file.readAsStringSync(), isNot(contains('unreadable')));
    });

    testWidgets('unreadable_entries_can_be_discarded', (tester) async {
      final world = World();
      final host = world.addHost('alpha');
      await world.prePair(host);
      final store = CredentialStore(world.keychain);
      await store.save('ghost', (await store.load('alpha'))!);
      world.store.unreadable = 1;
      await world.pump(tester);

      // While an entry is unreadable nothing unlisted is swept.
      expect(world.keychain.entries.keys, contains('yagura.ghost.device'));
      expect(find.byKey(const ValueKey('daemons:discard')), findsOneWidget);

      // Cancelling keeps everything.
      await tester.tap(find.byKey(const ValueKey('daemons:discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(world.store.unreadable, 1);

      // Confirming drops the entries, clears the notice and sweeps.
      await tester.tap(find.byKey(const ValueKey('daemons:discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('discard:confirm')));
      await settleAll(tester);
      expect(world.store.unreadable, 0);
      expect(find.byKey(const ValueKey('daemons:problem')), findsNothing);
      expect(
        world.keychain.entries.keys,
        isNot(contains('yagura.ghost.device')),
      );
      expect(world.keychain.entries.keys, contains('yagura.alpha.device'));
      expect(world.stateOf(tester, 'alpha'), 'connected');
    });

    testWidgets('a_pairing_after_a_damaged_file_keeps_the_other_keys', (
      tester,
    ) async {
      final world = await _afterDamageAndPairing(tester, file);

      // After a restart the daemons of the damaged file keep their keys
      // (and the copy can still be restored by hand): only pending keys are
      // swept.
      final keys = world.keychain.entries.keys;
      expect(keys, contains('yagura.alpha.device'));
      expect(keys, contains('yagura.bravo.device'));
      expect(keys, contains('yagura.charlie.device'));
      expect(keys.where((k) => k.contains('pending')), isEmpty);
      expect(world.stateOf(tester, 'charlie'), 'connected');
      expect(find.textContaining('daemons.json.damaged'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('daemons:discard-copy')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('daemons:discard')), findsNothing);
    });

    testWidgets('the_damaged_copy_is_discarded_only_after_confirming', (
      tester,
    ) async {
      final world = await _afterDamageAndPairing(tester, file);

      // Cancelling changes nothing.
      await tester.tap(find.byKey(const ValueKey('daemons:discard-copy')));
      await tester.pumpAndSettle();
      expect(find.textContaining('deleted for good'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(File('${file.path}.damaged').existsSync(), isTrue);
      expect(world.keychain.entries.keys, contains('yagura.alpha.device'));

      // Confirming deletes the copy, and the cleanup runs normally again.
      await tester.tap(find.byKey(const ValueKey('daemons:discard-copy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('discard-copy:confirm')));
      await settleIo(
        tester,
        until: () =>
            !File('${file.path}.damaged').existsSync() &&
            world.stateOf(tester, 'charlie') == 'connected',
      );
      expect(File('${file.path}.damaged').existsSync(), isFalse);
      expect(find.byKey(const ValueKey('daemons:problem')), findsNothing);
      final keys = world.keychain.entries.keys;
      expect(keys, isNot(contains('yagura.alpha.device')));
      expect(keys, isNot(contains('yagura.bravo.device')));
      expect(keys, contains('yagura.charlie.device'));
      expect(world.stateOf(tester, 'charlie'), 'connected');
    });

    testWidgets('a_locked_list_keeps_every_key_and_says_so', (tester) async {
      final world = World();
      final host = world.addHost('alpha');
      await world.prePair(host);
      final store = CredentialStore(world.keychain);
      await store.save('ghost', (await store.load('alpha'))!);
      world.store.readError = 'it is being used by another process';
      await world.pump(tester);

      expect(find.textContaining('could not be read'), findsOneWidget);
      expect(find.byKey(const ValueKey('daemons:discard')), findsNothing);
      expect(find.byKey(const ValueKey('daemons:discard-copy')), findsNothing);
      expect(world.keychain.entries.keys, contains('yagura.ghost.device'));
      expect(world.keychain.entries.keys, contains('yagura.alpha.device'));
    });

    testWidgets('the_discard_confirmation_names_what_is_deleted', (
      tester,
    ) async {
      final world = World();
      world.store
        ..unreadable = 2
        ..unreadableNames = ['Old NAS']
        ..overCapNames = ['Extra A', 'Extra B'];
      await world.pump(tester);

      await tester.tap(find.byKey(const ValueKey('daemons:discard')));
      await tester.pumpAndSettle();

      expect(find.textContaining('keys and certificates'), findsOneWidget);
      expect(find.textContaining('Old NAS'), findsOneWidget);
      expect(find.textContaining('Extra A, Extra B'), findsOneWidget);
      expect(
        find.textContaining('Entries beyond the limit of 32'),
        findsOneWidget,
      );
      expect(find.textContaining('1 without a readable name'), findsOneWidget);
      // Cancelling discards nothing.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(world.store.unreadable, 2);
    });

    testWidgets('pairing_is_refused_up_front_while_the_list_cannot_be_read', (
      tester,
    ) async {
      final world = World();
      final host = world.addHost('alpha');
      world.store.readError = 'it is being used by another process';
      await world.pump(tester);

      // The dialog says why and offers no Pair action.
      await tester.tap(find.byKey(const ValueKey('action:pair')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pair:refused')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('pair:string')),
        host.pairingString(),
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('pair:submit')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // pair() itself refuses before any network call or keychain write.
      await expectLater(
        world.container
            .read(daemonRegistryProvider.notifier)
            .pair(host.pairingString(), 'laptop'),
        throwsA(
          isA<PairingFailure>().having(
            (e) => e.reason,
            'reason',
            'daemon_list_unsaved',
          ),
        ),
      );
      expect(world.dialer.opened, isEmpty);
      expect(host.enrollRequests, isEmpty);
      expect(host.pairingCode, isNotNull, reason: 'the code is not used up');
      expect(world.keychain.entries, isEmpty);
    });

    testWidgets('the_discard_confirmation_lists_over_cap_daemons', (
      tester,
    ) async {
      final world = World();
      world.store.overCapNames = ['Extra A'];
      await world.pump(tester);

      expect(find.textContaining('beyond the limit of 32'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('daemons:discard')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Extra A'), findsOneWidget);
      expect(find.textContaining('not shown'), findsWidgets);
      expect(
        find.textContaining('Entries that could not be read'),
        findsNothing,
      );
    });

    testWidgets('a_damaged_file_without_a_copy_says_so', (tester) async {
      final world = World();
      world.store.damaged = true;
      world.store.copied = false;
      await world.pump(tester);

      expect(
        find.textContaining('no copy of it could be made'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('daemons:discard')), findsNothing);
    });

    testWidgets('a_damaged_file_is_surfaced', (tester) async {
      final world = World();
      world.store.damaged = true;
      await world.pump(tester);

      expect(find.textContaining('daemons.json.damaged'), findsOneWidget);
    });
  });
}

/// Session one reads a damaged list (so lists nothing), pairs charlie, and
/// session two starts from the file that results. Alpha and bravo were in the
/// damaged file; their keys are in the keychain.
Future<World> _afterDamageAndPairing(WidgetTester tester, File file) async {
  file.writeAsStringSync('{"daemons": [');
  final world = World();
  final alpha = world.addHost('alpha');
  final bravo = world.addHost('bravo', host: '10.0.0.3');
  final charlie = world.addHost('charlie', host: '10.0.0.4');
  await world.prePair(alpha);
  await world.prePair(bravo);
  world
    ..store.records = []
    ..fileStore = FileDaemonListStore(file);
  await world.pump(tester);
  await settleIo(tester);
  expect(find.textContaining('is damaged'), findsOneWidget);
  final pairing = world.container
      .read(daemonRegistryProvider.notifier)
      .pair(charlie.pairingString(), 'laptop');
  unawaited(pairing.then((_) {}, onError: (Object _) {}));
  await settleIo(tester, until: () => _lists(file, 'charlie'));

  // The restart.
  await tester.pumpWidget(const SizedBox());
  world.fileStore = FileDaemonListStore(file);
  await world.pump(tester);
  await settleIo(
    tester,
    until: () =>
        find
            .byKey(const ValueKey('daemons:discard-copy'))
            .evaluate()
            .isNotEmpty &&
        world.stateOf(tester, 'charlie') == 'connected',
  );
  return world;
}

/// Whether [file] holds a saved list with the daemon [id].
bool _lists(File file, String id) {
  try {
    return file.readAsStringSync().contains('"id":"$id"');
  } on FileSystemException {
    return false; // mid-save
  }
}

/// Lets real file I/O finish (the fake clock of a widget test does not), then
/// settles the widgets. With [until], it goes on, for up to 10 s, until that
/// holds: a loaded runner can take longer than the 30 rounds.
Future<void> settleIo(WidgetTester tester, {bool Function()? until}) async {
  for (var i = 0; i < 30 || (until != null && !until() && i < 1000); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await settleAll(tester);
  }
}
