import 'dart:async';

import 'package:test/test.dart';
import 'package:yagurad/src/logs/logs.dart';

import 'log_test_support.dart';

void main() {
  test('live_lines_delivered', () async {
    final at = DateTime.utc(2026, 10, 17, 12);
    // Real polling: 20 ms while followed, an hour otherwise, so the line can
    // only arrive in time if following speeds the poll up.
    final rig = LogRig(
      clock: () => at,
      options: const LogHubOptions(
        pollFollowed: Duration(milliseconds: 20),
        pollIdle: Duration(hours: 1),
        persistInterval: Duration(hours: 1),
      ),
    );
    rig.write('profiles/server.RPT', const []);
    await rig.attach([rig.fileSource('rpt', 'profiles/server.RPT')]);

    final arrived = rig.hub.follow(rigInstance).first;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    rig.appendLines('profiles/server.RPT', ['Player connected']);

    final batch = await arrived.timeout(const Duration(seconds: 1));
    final entry = batch.entries.single;
    expect(entry.source, 'rpt');
    expect(entry.text, 'Player connected');
    expect(entry.receivedAt, at);
    expect(entry.sequence, greaterThan(0));
  });

  test('slow_subscriber', () async {
    final rig = LogRig();
    rig.write('server.log', const []);
    await rig.attach([rig.fileSource('server', 'server.log')]);
    final slow = Collector(rig.hub.follow(rigInstance));
    final other = Collector(rig.hub.follow(rigInstance));
    await slow.settle();

    // The slow client stops reading while 3,000 lines arrive.
    slow.subscription.pause();
    final lines = numberedLines(3000);
    rig.appendLines('server.log', lines);
    await rig.poll();
    await other.settle();

    expect(slow.batches, isEmpty);
    slow.subscription.resume();
    await slow.settle();

    // On resuming: a `dropped: 2000` marker, then the newest 1,000 lines.
    expect(slow.dropped, 2000);
    expect(slow.batches.first.dropped, 2000);
    expect(slow.texts, lines.sublist(2000));
    // The other subscriber saw everything and no marker.
    expect(other.texts, lines);
    expect(other.dropped, 0);
  });

  test('a_subscriber_behind_by_4_mib_is_dropped_too', () async {
    final rig = LogRig();
    rig.write('server.log', const []);
    await rig.attach([rig.fileSource('server', 'server.log')]);
    final slow = Collector(rig.hub.follow(rigInstance));
    await slow.settle();
    slow.subscription.pause();

    // 100 lines of 60 KiB are 6 MiB, which is more than 4 MiB behind.
    rig.appendLines('server.log', [
      for (var i = 0; i < 100; i++)
        '${i.toString().padLeft(3, '0')}${'z' * (60 * 1024)}',
    ]);
    await rig.poll();
    slow.subscription.resume();
    await slow.settle();

    expect(slow.dropped, greaterThan(0));
    expect(slow.entries.length + slow.dropped, 100);
    expect(slow.entries.last.text, startsWith('099'));
    final bytes = slow.entries.fold<int>(0, (sum, e) => sum + e.sizeBytes);
    expect(bytes, lessThanOrEqualTo(followMaxLagBytes));
  });
}
