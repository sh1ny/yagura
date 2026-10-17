import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/logs/logs.dart';
import 'package:yagurad/src/logs/source_tailer.dart';

import 'log_test_support.dart';

List<int> utf16(String text) => [
  for (final unit in text.codeUnits) ...[unit & 0xFF, unit >> 8],
];

int diskBytes(String directory) =>
    CaptureWriter.filesIn(directory)
        .fold(0, (sum, f) => sum + File(f).lengthSync());

/// Bounds of the capture writer, the live follower queue and the tailer's
/// restart behaviour that the spec scenarios do not spell out.
void main() {
  group('capture writer', () {
    test('output_without_a_newline_stays_within_the_line_limit', () async {
      final rig = LogRig();
      final directory = p.join(rig.dir.path, 'capture');
      final writer = CaptureWriter.open(
        directory,
        fileBytes: 1024,
        fileCount: 5,
      );
      addTearDown(writer.close);
      await rig.attach([
        LogSourceSpec.stdout(
          name: 'stdout',
          encoding: LogEncoding.utf8,
          directory: directory,
        ),
      ]);
      final chunk = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 0x61);
      for (var i = 0; i < 16; i++) {
        writer.write(chunk); // 1 MiB, never a newline
        await rig.poll();
      }
      // One line is cut where the hub cuts it, the rest is not stored.
      expect(diskBytes(directory), lessThanOrEqualTo(maxLineBytes + 1));

      writer.write('\nnext\n'.codeUnits);
      await rig.poll();
      final entries = rig.hub.backlog(rigInstance).entries;
      expect(entries.map((e) => e.text.length), [maxLineBytes, 4]);
      expect(entries.first.truncated, isTrue);
      expect(entries.last.text, 'next');
    });

    test('utf_16_rotates_only_after_a_whole_newline_unit', () async {
      final rig = LogRig();
      final directory = p.join(rig.dir.path, 'capture');
      final writer = CaptureWriter.open(
        directory,
        fileBytes: 6,
        fileCount: 10,
        encoding: LogEncoding.utf16le,
      );
      addTearDown(writer.close);
      await rig.attach([
        LogSourceSpec.stdout(
          name: 'stdout',
          encoding: LogEncoding.utf16le,
          directory: directory,
        ),
      ]);
      // U+010A and U+0A00 contain a 0x0A byte that is not a line break.
      final bytes = utf16('a\nĊb਀c\nd\n');
      // The writer is handed one byte at a time: every split is exercised.
      for (final byte in bytes) {
        writer.write([byte]);
        await rig.poll();
      }
      writer.close();
      final files = CaptureWriter.filesIn(directory);
      expect(files.length, greaterThan(1));
      final all = <int>[];
      for (final file in files) {
        final data = File(file).readAsBytesSync();
        expect(data.length.isEven, isTrue, reason: p.basename(file));
        expect(data.sublist(data.length - 2), [0x0A, 0x00]);
        all.addAll(data);
      }
      expect(all, bytes);

      await rig.poll();
      expect(rig.hub.backlog(rigInstance).entries.map((e) => e.text), [
        'a',
        'Ċb਀c',
        'd',
      ]);
    });
  });

  group('follower', () {
    test('a_burst_of_wide_latin_1_lines_is_split_into_small_batches', () async {
      final rig = LogRig();
      rig.write('server.log', const []);
      await rig.attach([
        rig.fileSource('server', 'server.log', encoding: LogEncoding.latin1),
      ]);
      final followed = Collector(rig.hub.follow(rigInstance));
      await followed.settle();

      // 300 lines of 64 KiB 0xE9 bytes: each is 2 bytes as UTF-8 on the wire.
      final line = Uint8List(maxLineBytes + 1)
        ..fillRange(0, maxLineBytes, 0xE9);
      line[maxLineBytes] = 0x0A;
      final file = File(rig.path('server.log'));
      final sink = file.openSync(mode: FileMode.append);
      for (var i = 0; i < 300; i++) {
        sink.writeFromSync(line);
      }
      sink.closeSync();
      await rig.poll();
      await followed.settle();

      expect(followed.entries, hasLength(300));
      for (final batch in followed.batches) {
        final wire = batch.entries.fold<int>(
          0,
          (sum, e) => sum + utf8.encode(e.text).length,
        );
        expect(wire, lessThan(5 * 1024 * 1024));
      }
    });

    test(
      'a_paused_subscriber_keeps_a_bounded_number_of_source_events',
      () async {
        final rig = LogRig();
        rig.write('app-000.log', utf8.encode('first\n'));
        await rig.attach([
          rig.fileSource('app', 'app-*.log', rotation: LogRotation.newest),
        ]);
        final slow = Collector(rig.hub.follow(rigInstance));
        await slow.settle();
        slow.subscription.pause();

        for (var i = 1; i <= followMaxEvents * 3; i++) {
          rig.write(
            'app-${i.toString().padLeft(3, '0')}.log',
            utf8.encode('x\n'),
          );
          await rig.poll();
        }
        slow.subscription.resume();
        await slow.settle();

        expect(slow.events.length, lessThanOrEqualTo(followMaxEvents));
        expect(
          slow.events.last,
          'file_switched:app-${followMaxEvents * 3}.log',
        );
      },
    );
  });

  group('tailer', () {
    SourceTailer tailer(
      LogSourceSpec spec,
      List<String> lines, {
      int historyBytes = historyWindowBytes,
    }) => SourceTailer(
      spec: spec,
      sink: (source, line, {required history}) =>
          lines.add(spec.encoding.decode(line.bytes)),
      onEvent: (_) {},
      clock: DateTime.now,
      waitingAfter: const Duration(seconds: 60),
      historyBytes: historyBytes,
    );

    test('a_restart_inside_an_oversized_line_keeps_discarding_it', () async {
      final rig = LogRig();
      final head = utf8.encode('first\n');
      rig.write('server.log', [...head, ...List.filled(300000, 0x78)]);
      final spec = rig.fileSource('server', 'server.log');
      final lines = <String>[];
      final t = tailer(spec, lines, historyBytes: 100000);
      // Saved while the line was already cut: 200,000 bytes in.
      await t.start(LogPosition(rig.path('server.log'), 200000));
      rig.append('server.log', utf8.encode('tail\nnext\n'));
      await t.poll();
      expect(lines, ['next']);
    });

    test('a_bom_split_over_two_reads_is_removed', () async {
      for (final (encoding, bom) in [
        (LogEncoding.utf16le, [0xFF, 0xFE]),
        (LogEncoding.utf8, [0xEF, 0xBB, 0xBF]),
      ]) {
        final rig = LogRig();
        final body = encoding == LogEncoding.utf16le
            ? utf16('Server ready\n')
            : utf8.encode('Server ready\n');
        // The first poll sees a prefix of the BOM, the next the rest.
        rig.write('server.log', bom.sublist(0, 1));
        final lines = <String>[];
        final t = tailer(
          rig.fileSource('server', 'server.log', encoding: encoding),
          lines,
        );
        await t.start(null);
        await t.poll();
        rig.append('server.log', [...bom.sublist(1), ...body]);
        await t.poll();
        expect(lines, ['Server ready'], reason: encoding.name);
      }
    });

    test('a_saved_file_of_another_pattern_is_not_resumed', () async {
      final rig = LogRig();
      rig.appendLines('old-1.log', ['from the old declaration']);
      rig.appendLines('new-1.log', ['from the new declaration']);
      final lines = <String>[];
      final t = tailer(
        rig.fileSource('app', 'new-*.log', rotation: LogRotation.newest),
        lines,
      );
      await t.start(
        LogPosition(
          rig.path('old-1.log'),
          File(rig.path('old-1.log')).lengthSync(),
        ),
      );
      expect(p.basename(t.status.currentFile), 'new-1.log');
      expect(lines, ['from the new declaration']);
    });
  });
}
