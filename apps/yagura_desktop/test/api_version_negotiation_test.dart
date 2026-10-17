import 'package:flutter_test/flutter_test.dart';
import 'package:yagura_desktop/src/api_version.dart';
import 'package:yagura_desktop/src/connection.dart';
import 'package:yagura_desktop/src/providers.dart';
import 'package:yagura_desktop/src/ui/connection_banner.dart';

import 'support/fake_daemon.dart';

void main() {
  testWidgets('compatible_versions', (tester) async {
    final harness = Harness(
      daemon: FakeDaemon(apiVersions: ['1.5']),
      clientVersion: const ApiVersion(1, 3),
    );
    await pumpApp(
      tester,
      harness,
      const ConnectionBanner(daemonId: kDevDaemonId),
    );

    final status = harness.connection.status;
    expect(status, isA<Connected>());
    final negotiated = (status as Connected).negotiated;
    expect(negotiated.effective, const ApiVersion(1, 3));
    expect(negotiated.supports(const ApiVersion(1, 3)), isTrue);
    expect(negotiated.supports(const ApiVersion(1, 4)), isFalse);
    expect(find.textContaining('Connected'), findsOneWidget);
    expect(find.textContaining('API 1.3'), findsOneWidget);
    expect(harness.daemon.calls, contains('WatchInstances'));
  });

  testWidgets('incompatible_major', (tester) async {
    final harness = Harness(
      daemon: FakeDaemon(apiVersions: ['2.0']),
      clientVersion: const ApiVersion(1, 3),
    );
    await pumpApp(
      tester,
      harness,
      const ConnectionBanner(daemonId: kDevDaemonId),
    );

    expect(harness.connection.status, isA<IncompatibleDaemon>());
    expect(find.textContaining('Incompatible'), findsOneWidget);
    expect(find.textContaining('1.3'), findsOneWidget);
    expect(find.textContaining('2.0'), findsOneWidget);
    // Nothing but the negotiation call is made.
    expect(harness.daemon.calls, ['GetInfo']);
    expect(harness.delay.requested, isEmpty);
  });

  testWidgets('overlap_during_a_migration', (tester) async {
    final harness = Harness(
      daemon: FakeDaemon(apiVersions: ['1.9', '2.0']),
      clientVersion: const ApiVersion(1, 10),
    );
    await pumpApp(
      tester,
      harness,
      const ConnectionBanner(daemonId: kDevDaemonId),
    );

    final status = harness.connection.status;
    expect(status, isA<Connected>());
    final negotiated = (status as Connected).negotiated;
    expect(negotiated.effective, const ApiVersion(1, 9));
    expect(negotiated.daemonVersion, const ApiVersion(1, 9));
    expect(find.textContaining('API 1.9'), findsOneWidget);
  });

  test('the client API version is 1.0 in M1', () {
    expect(kClientApiVersion, const ApiVersion(1, 0));
    expect(ApiVersion.tryParse('1.5'), const ApiVersion(1, 5));
    expect(ApiVersion.tryParse('one'), isNull);
  });
}
