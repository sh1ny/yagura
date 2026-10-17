import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/steam/steam.dart';

import '../support/daemon_support.dart';
import '../support/steam_support.dart';

SteamAppRequest requestFor(TestEnv env) => SteamAppRequest(
  appId: valheimAppId,
  installDirectory: p.join(env.root.path, 'server'),
);

void main() {
  test('known_failure_classified', () async {
    final env = TestEnv();
    final steam = SteamHarness(
      env,
      fakeEnvironment: {
        'FAKE_STEAMCMD_TRANSCRIPT': 'no_subscription.txt',
        'FAKE_STEAMCMD_EXIT': '8',
      },
    );

    await expectLater(
      steam.service.installApp(
        requestFor(env),
        RecordingReporter(),
        CancelToken(),
      ),
      failsWith(
        'steam_no_subscription',
        messageHas: ['does not own the required app', '$valheimAppId'],
      ),
    );
    expect(steam.appRuns(), hasLength(1), reason: 'no retry');
  });

  test('unknown_failure_surfaced', () async {
    final env = TestEnv();
    final steam = SteamHarness(
      env,
      fakeEnvironment: {
        'FAKE_STEAMCMD_TRANSCRIPT': 'unknown_failure.txt',
        'FAKE_STEAMCMD_EXIT': '5',
      },
    );

    await expectLater(
      steam.service.installApp(
        requestFor(env),
        RecordingReporter(),
        CancelToken(),
      ),
      throwsA(
        isA<YaguraException>()
            .having((e) => e.reason, 'reason', 'steam_unknown_error')
            .having(
              (e) => e.details['lines'],
              'the last output lines',
              isA<List<Object?>>()
                  .having((l) => l, 'last 50', hasLength(50))
                  .having(
                    (l) => l.first,
                    'first of the 50',
                    'unrecognised chatter line 12',
                  )
                  .having(
                    (l) => l.last,
                    'last',
                    'ERROR! Something nobody has seen before (code 0x1234)',
                  ),
            )
            .having(
              (e) => e.message,
              'message',
              contains('Something nobody has seen before'),
            ),
      ),
    );
    expect(steam.appRuns(), hasLength(1), reason: 'no retry');
  });

  test('runs_with_arguments_only_and_stdin_closed', () async {
    final env = TestEnv();
    final steam = SteamHarness(env);

    await steam.service.installApp(
      requestFor(env),
      RecordingReporter(),
      CancelToken(),
    );

    final run = steam.appRuns().single;
    final args = (run['args']! as List).cast<String>();
    expect(args.last, '+quit');
    expect(args, isNot(contains('+runscript')));
    expect(run['stdinClosed'], isTrue);
  });

  test('validate_adds_the_validate_flag', () async {
    final env = TestEnv();
    final steam = SteamHarness(env);

    await steam.service.installApp(
      SteamAppRequest(
        appId: valheimAppId,
        installDirectory: p.join(env.root.path, 'server'),
        validate: true,
      ),
      RecordingReporter(),
      CancelToken(),
    );

    expect(steam.appRuns().single['validate'], isTrue);
  });
}
