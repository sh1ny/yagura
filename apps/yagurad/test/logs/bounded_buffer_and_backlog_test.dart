import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yagurad/src/logs/logs.dart';

import '../support/daemon_support.dart';
import 'log_test_support.dart';

void main() {
  test('backlog_after_restart', () async {
    final env = TestEnv();
    env.installValheim();
    final first = await env.start();
    final instance = await createInstalled(first);
    final log = '${instance.directory}/logs/server.log';
    final lines = numberedLines(2000);
    final file = File(log)..parent.createSync(recursive: true);
    file.writeAsStringSync('${lines.join('\n')}\n');
    await first.logs.pollNow(instance.id);
    expect(first.logs.backlog(instance.id, lines: 10).entries, hasLength(10));
    await env.kill(first);

    // The daemon was down; nothing refilled the ring but the file.
    final second = await env.start();
    final backlog = second.logs.backlog(instance.id, lines: 500);

    expect(backlog.truncated, isFalse);
    expect(backlog.entries.map((e) => e.text), lines.sublist(1500));
    expect(backlog.entries.map((e) => e.source), everyElement('server'));
    final sequences = backlog.entries.map((e) => e.sequence).toList();
    expect(sequences, orderedEquals([...sequences]..sort()));
    expect(file.existsSync(), isTrue);
  });

  test('request_above_the_limit', () async {
    final rig = LogRig();
    rig.appendLines('server.log', numberedLines(6000));
    await rig.attach([rig.fileSource('server', 'server.log')]);

    final over = rig.hub.backlog(rigInstance, lines: 50000);
    expect(over.entries, hasLength(5000));
    expect(over.truncated, isTrue);
    expect(over.entries.first.text, 'line 01001');
    expect(over.entries.last.text, 'line 06000');

    final within = rig.hub.backlog(rigInstance, lines: 500);
    expect(within.entries, hasLength(500));
    expect(within.truncated, isFalse);
  });

  test('line_without_a_newline', () async {
    final rig = LogRig();
    rig.write('server.log', const []);
    await rig.attach([rig.fileSource('server', 'server.log')]);
    final followed = Collector(rig.hub.follow(rigInstance));

    rig.append('server.log', List.filled(1024 * 1024, 0x78));
    await rig.poll();
    await followed.settle();

    expect(followed.entries, hasLength(1));
    expect(followed.entries.single.text, 'x' * 64 * 1024);
    expect(followed.entries.single.truncated, isTrue);
    final stats = rig.hub.bufferStats(rigInstance, 'server');
    expect(stats.lines, 1);
    expect(stats.bytes, lessThanOrEqualTo(ringMaxBytes));

    // The rest of the long line is discarded up to the next newline.
    rig.append('server.log', utf8.encode('tail of the long line\nnext line\n'));
    await rig.poll();
    await followed.settle();
    expect(followed.texts.skip(1), ['next line']);
    expect(followed.entries.skip(1).single.truncated, isFalse);
  });

  test('the_ring_keeps_the_last_10000_lines', () async {
    final rig = LogRig();
    rig.write('server.log', const []);
    await rig.attach([rig.fileSource('server', 'server.log')]);
    rig.appendLines('server.log', numberedLines(12000));
    await rig.poll();

    final stats = rig.hub.bufferStats(rigInstance, 'server');
    expect(stats.lines, ringMaxLines);
    expect(
      rig.hub.backlog(rigInstance, lines: 1).entries.single.text,
      'line 12000',
    );
  });

  test('the_ring_keeps_at_most_4_mib', () async {
    final rig = LogRig();
    rig.write('server.log', const []);
    await rig.attach([rig.fileSource('server', 'server.log')]);
    final long = 'y' * (60 * 1024);
    rig.appendLines('server.log', List.filled(150, long));
    await rig.poll();

    final stats = rig.hub.bufferStats(rigInstance, 'server');
    expect(stats.bytes, lessThanOrEqualTo(ringMaxBytes));
    expect(stats.lines, lessThan(150));
    expect(stats.lines, greaterThan(60));
  });

  test('limits_match_the_documented_bounds', () {
    expect(ringMaxLines, 10000);
    expect(ringMaxBytes, 4 * 1024 * 1024);
    expect(backlogMaxLines, 5000);
    expect(maxLineBytes, 64 * 1024);
    expect(followMaxLagLines, 1000);
    expect(followMaxLagBytes, 4 * 1024 * 1024);
    expect(captureFileBytes, 10 * 1024 * 1024);
    expect(captureFileCount, 5);
  });
}
