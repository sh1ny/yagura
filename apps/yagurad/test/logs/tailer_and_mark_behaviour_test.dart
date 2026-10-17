import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/host/migrations.dart';
import 'package:yagurad/src/logs/log_offset_store.dart';
import 'package:yagurad/src/logs/logs.dart';

import 'log_test_support.dart';

/// Extra coverage for the log hub beyond the spec rows: truncation, saved
/// offsets and the current-run mark the `log_match` health check (task 7.3)
/// builds on.
void main() {
  group('current-run mark', () {
    test('lines_before_the_mark_are_not_after_it', () async {
      final rig = LogRig();
      rig.appendLines('server.log', ['old run', 'Game server connected']);
      await rig.attach([rig.fileSource('server', 'server.log')]);
      final mark = await rig.hub.markRun(rigInstance);
      final after = <String>[];
      final sub = rig.hub
          .linesAfter(rigInstance, 'server', mark)
          .listen((e) => after.add(e.text));
      addTearDown(sub.cancel);

      await rig.poll();
      expect(after, isEmpty);

      rig.appendLines('server.log', ['Game server connected']);
      await rig.poll();
      await Future<void>.delayed(Duration.zero);
      expect(after, ['Game server connected']);
    });

    test(
      'lines_read_between_the_mark_and_the_subscription_are_replayed',
      () async {
        final rig = LogRig();
        rig.appendLines('server.log', ['old']);
        await rig.attach([rig.fileSource('server', 'server.log')]);
        final mark = await rig.hub.markRun(rigInstance);

        rig.appendLines('server.log', ['first', 'second']);
        await rig.poll();
        final after = <String>[];
        final sub = rig.hub
            .linesAfter(rigInstance, 'server', mark)
            .listen((e) => after.add(e.text));
        addTearDown(sub.cancel);
        rig.appendLines('server.log', ['third']);
        await rig.poll();
        await Future<void>.delayed(Duration.zero);

        expect(after, ['first', 'second', 'third']);
      },
    );

    test('a_rewrite_past_the_old_size_is_read_from_its_start', () async {
      final rig = LogRig();
      final old = StringBuffer('old run\nGame server connected\n');
      while (old.length < 40 * 1024) {
        old.writeln('previous ${old.length}');
      }
      rig.write('server.log', utf8.encode(old.toString()));
      await rig.attach([rig.fileSource('server', 'server.log')]);
      final mark = await rig.hub.markRun(rigInstance);
      expect(mark.fixedFiles['server']!.size, old.length);
      expect(mark.fixedFiles['server']!.hashedBytes, 4096);
      expect(mark.fixedFiles['server']!.sha256, hasLength(64));

      final fresh = StringBuffer('new run\nGame server connected\n');
      while (fresh.length < 50 * 1024) {
        fresh.writeln('current ${fresh.length}');
      }
      final after = <String>[];
      final sub = rig.hub
          .linesAfter(rigInstance, 'server', mark)
          .listen((e) => after.add(e.text));
      addTearDown(sub.cancel);
      rig.write('server.log', utf8.encode(fresh.toString()));
      await rig.poll();
      await Future<void>.delayed(Duration.zero);

      expect(after.take(2), ['new run', 'Game server connected']);
      expect(
        after,
        hasLength(const LineSplitter().convert(fresh.toString()).length),
      );
    });

    test('an_untouched_file_is_not_read_twice', () async {
      final rig = LogRig();
      rig.appendLines('server.log', ['a', 'b']);
      await rig.attach([rig.fileSource('server', 'server.log')]);
      final mark = await rig.hub.markRun(rigInstance);
      final after = <String>[];
      final sub = rig.hub
          .linesAfter(rigInstance, 'server', mark)
          .listen((e) => after.add(e.text));
      addTearDown(sub.cancel);

      await rig.poll();
      await rig.poll();
      rig.appendLines('server.log', ['c']);
      await rig.poll();
      await rig.poll();
      await Future<void>.delayed(Duration.zero);
      expect(after, ['c']);
    });
  });

  test('a_truncated_file_is_read_again_from_its_start', () async {
    final rig = LogRig();
    rig.appendLines('server.log', numberedLines(50));
    await rig.attach([rig.fileSource('server', 'server.log')]);
    final followed = Collector(rig.hub.follow(rigInstance));

    // The game truncates its log and writes less than before.
    rig.write('server.log', utf8.encode('fresh start\n'));
    await rig.poll();
    await followed.settle();
    expect(followed.texts, ['fresh start']);
  });

  test('a_line_split_between_two_polls_is_delivered_whole', () async {
    final rig = LogRig();
    rig.write('server.log', const []);
    await rig.attach([rig.fileSource('server', 'server.log')]);
    final followed = Collector(rig.hub.follow(rigInstance));

    rig.append('server.log', utf8.encode('half of a li'));
    await rig.poll();
    await followed.settle();
    expect(followed.texts, isEmpty);
    rig.append('server.log', utf8.encode('ne\r\n'));
    await rig.poll();
    await followed.settle();
    expect(followed.texts, ['half of a line']);
  });

  test(
    'a_directory_in_place_of_the_file_is_waiting_and_polling_goes_on',
    () async {
      final rig = LogRig();
      // A directory where the file should be: it cannot be read as a file.
      Directory(rig.path('server.log')).createSync();
      await rig.attach([rig.fileSource('server', 'server.log')]);
      final followed = Collector(rig.hub.follow(rigInstance));
      await rig.poll();
      await followed.settle();
      // A directory does not match a `fixed` file source: it is waiting, not
      // failing, and polling goes on.
      expect(rig.hub.sources(rigInstance).single.status, isNot('error'));

      Directory(rig.path('server.log')).deleteSync();
      rig.appendLines('server.log', ['alive']);
      await rig.poll();
      await followed.settle();
      expect(followed.texts, ['alive']);
    },
  );

  group('saved offsets', () {
    late Directory dir;
    late YaguraDatabase database;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('yagurad_offsets_');
      database = YaguraDatabase.open(
        p.join(dir.path, 'yagura.db'),
        migrations: allMigrations,
      );
      addTearDown(() {
        database.close();
        dir.deleteSync(recursive: true);
      });
    });

    LogSourceSpec source() => LogSourceSpec(
      name: 'server',
      kind: LogSourceKind.file,
      pattern: p.join(dir.path, 'server.log'),
      encoding: LogEncoding.utf8,
    );

    test('offsets_are_saved_every_interval', () async {
      final hub = LogHub(
        database: database,
        options: const LogHubOptions(
          pollFollowed: Duration(hours: 1),
          pollIdle: Duration(hours: 1),
          persistInterval: Duration(milliseconds: 20),
        ),
      );
      File(p.join(dir.path, 'server.log')).writeAsStringSync('a\nb\n');
      await hub.attach('i', [source()]);
      File(p.join(dir.path, 'server.log'))
          .writeAsStringSync('c\n', mode: FileMode.append);
      await hub.pollNow('i');

      final store = LogOffsetStore(database);
      for (var i = 0; i < 100 && store.load('i', 'server')?.offset != 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(store.load('i', 'server')?.offset, 6);
      await hub.close();
    });

    test('a_restart_continues_after_the_saved_offset', () async {
      final log = File(p.join(dir.path, 'server.log'))
        ..writeAsStringSync('one\ntwo\n');
      final first = LogHub(
        database: database,
        options: const LogHubOptions.manual(),
      );
      await first.attach('i', [source()]);
      log.writeAsStringSync('three\npar', mode: FileMode.append);
      await first.pollNow('i');
      await first.close();
      // Written while the hub was down; the unfinished line is completed.
      log.writeAsStringSync('tial\nfour\n', mode: FileMode.append);

      final second = LogHub(
        database: database,
        options: const LogHubOptions.manual(),
      );
      addTearDown(second.close);
      await second.attach('i', [source()]);
      final followed = Collector(second.follow('i'));
      await second.pollNow('i');
      await followed.settle();

      expect(followed.texts, ['partial', 'four']);
      expect(second.backlog('i', lines: 10).entries.map((e) => e.text), [
        'one',
        'two',
        'three',
        'partial',
        'four',
      ]);
    });

    test('forgetting_an_instance_drops_its_offsets', () async {
      File(p.join(dir.path, 'server.log')).writeAsStringSync('a\n');
      final hub = LogHub(
        database: database,
        options: const LogHubOptions.manual(),
      );
      await hub.attach('i', [source()]);
      await hub.detach('i');
      final store = LogOffsetStore(database);
      expect(store.load('i', 'server')?.offset, 2);
      await hub.attach('i', [source()]);
      await hub.detach('i', forget: true);
      expect(store.load('i', 'server'), isNull);
      await hub.close();
    });
  });
}
