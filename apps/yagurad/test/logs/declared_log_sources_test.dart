import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/logs/logs.dart';

import '../support/daemon_support.dart';
import 'log_test_support.dart';

void main() {
  test('newest_file_followed_after_rotation', () async {
    final rig = LogRig();
    const previous = 'DayZServer_x64_2026-10-16_10-00-00.RPT';
    const created = 'DayZServer_x64_2026-10-16_18-00-00.RPT';
    rig.appendLines('profiles/$previous', ['old line 1', 'old line 2']);
    await rig.attach([
      rig.fileSource('rpt', 'profiles/*.RPT', rotation: LogRotation.newest),
    ]);
    expect(
      p.basename(rig.hub.sources(rigInstance).single.currentFile),
      previous,
    );
    final followed = Collector(rig.hub.follow(rigInstance));

    // DayZ starts and creates a new RPT; the previous one still exists.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    rig.appendLines('profiles/$created', ['new line 1']);
    await rig.poll();
    rig.appendLines('profiles/$created', ['new line 2']);
    await rig.poll();
    await followed.settle();

    expect(followed.events, ['file_switched:$created']);
    expect(followed.texts, ['new line 1', 'new line 2']);
    final status = rig.hub.sources(rigInstance).single;
    expect(p.basename(status.currentFile), created);
    expect(status.status, 'following');
  });

  test('pattern_matches_nothing', () async {
    final env = TestEnv();
    env.installValheim();
    var now = DateTime.utc(2026, 10, 17, 12);
    final daemon = await env.start(clock: () => now);
    final instance = await createRunning(daemon);
    final followed = Collector(daemon.logs.follow(instance.id));

    // No `logs/server.log` appears.
    now = now.add(const Duration(seconds: 30));
    await daemon.logs.pollNow(instance.id);
    expect(daemon.logs.sources(instance.id).single.status, isNot('waiting'));

    now = now.add(const Duration(seconds: 31));
    await daemon.logs.pollNow(instance.id);
    await followed.settle();

    final source = daemon.logs.sources(instance.id).single;
    expect(source.name, 'server');
    expect(source.status, 'waiting');
    expect(source.pattern, contains('server.log'));
    expect(followed.events, ['waiting']);
    // No error stops the instance.
    expect(daemon.instances.get(instance.id).state, InstanceState.running);
  });
}
