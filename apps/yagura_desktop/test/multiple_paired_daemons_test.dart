import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yagura_desktop/src/providers.dart';
import 'package:yagura_desktop/src/transport.dart';
import 'package:yagura_proto/yagura_proto.dart';

import 'support/fake_daemon.dart';
import 'support/fake_world.dart';

/// Two paired daemons, each with one instance.
Future<(World, FakeHost, FakeHost)> _twoDaemons({
  List<String> alphaVersions = const ['1.0'],
}) async {
  final world = World();
  final alpha = world.addHost(
    'alpha',
    name: 'Alpha host',
    host: '10.0.0.2',
    daemon: FakeDaemon(
      apiVersions: alphaVersions,
      instances: [
        makeInstance(
          id: 'i1',
          name: 'Valheim A',
          state: InstanceState.INSTANCE_STATE_RUNNING,
        ),
      ],
    ),
  );
  final bravo = world.addHost(
    'bravo',
    name: 'Bravo host',
    host: '10.0.0.3',
    daemon: FakeDaemon(
      instances: [makeInstance(id: 'i2', name: 'Valheim B')],
    ),
  );
  await world.prePair(alpha);
  await world.prePair(bravo);
  return (world, alpha, bravo);
}

Finder _inCard(String id, Finder what) =>
    find.descendant(of: daemonCard(id), matching: what);

void main() {
  testWidgets('two_daemons_online', (tester) async {
    final (world, _, _) = await _twoDaemons();
    await world.pump(tester);

    // Both are listed with name, address and state...
    expect(world.stateOf(tester, 'alpha'), 'connected');
    expect(world.stateOf(tester, 'bravo'), 'connected');
    expect(_inCard('alpha', find.text('Alpha host')), findsOneWidget);
    expect(_inCard('alpha', find.text('10.0.0.2:7443')), findsOneWidget);
    expect(_inCard('bravo', find.text('10.0.0.3:7443')), findsOneWidget);
    // ...with their instances grouped under each.
    expect(_inCard('alpha', find.text('Valheim A')), findsOneWidget);
    expect(_inCard('alpha', find.text('Valheim B')), findsNothing);
    expect(_inCard('bravo', find.text('Valheim B')), findsOneWidget);
    expect(_inCard('bravo', find.text('Valheim A')), findsNothing);
    // Each connection checks the server against its own fixed name.
    expect(
      {for (final o in world.dialer.secureOpens) o.authority},
      {'yagurad-alpha', 'yagurad-bravo'},
    );
  });

  testWidgets('daemon_restarted', (tester) async {
    final (world, alpha, bravo) = await _twoDaemons();
    await world.pump(tester);
    expect(_inCard('alpha', find.text('running')), findsOneWidget);

    // The daemon goes away: it is `connecting`, the last state stays.
    alpha.daemon.kill();
    await settleAll(tester);
    expect(world.stateOf(tester, 'alpha'), 'connecting');
    expect(_inCard('alpha', find.text('running')), findsOneWidget);
    expect(world.reconnectDelay.requested, [const Duration(seconds: 1)]);
    expect(world.stateOf(tester, 'bravo'), 'connected');

    // It is back, and the instance stopped while the client was away.
    alpha.daemon.restart(
      instances: [makeInstance(id: 'i1', name: 'Valheim A')],
    );
    world.reconnectDelay.release();
    await settleAll(tester);

    expect(world.stateOf(tester, 'alpha'), 'connected');
    expect(_inCard('alpha', find.text('stopped')), findsOneWidget);
    expect(_inCard('alpha', find.text('running')), findsNothing);
    // A fresh WatchInstances snapshot, on the same connection object.
    expect(
      alpha.daemon.calls.where((c) => c == 'WatchInstances'),
      hasLength(2),
    );
    expect(bravo.daemon.calls.where((c) => c == 'GetInfo'), hasLength(1));
  });

  testWidgets('daemon_offline', (tester) async {
    final (world, alpha, bravo) = await _twoDaemons();
    await world.pump(tester);

    alpha.daemon.kill();
    await settleAll(tester);
    world.reconnectDelay.release();
    await settleAll(tester);

    // Listed offline with the last error and the last-seen time.
    expect(world.stateOf(tester, 'alpha'), 'offline');
    final detail = find.byKey(const ValueKey('daemon:alpha:detail'));
    expect(
      tester.widget<Text>(detail).data,
      allOf(contains('unavailable'), contains('Last seen 12:00:00')),
    );
    // The other daemon stays usable.
    expect(world.stateOf(tester, 'bravo'), 'connected');
    await world.container
        .read(daemonConnectionProvider('bravo'))
        .startInstance(makeInstance(id: 'i2', name: 'Valheim B'));
    expect(bravo.daemon.calls, contains('Start:i2'));
    // Reconnection is retried with growing delays.
    expect(world.reconnectDelay.requested, [
      const Duration(seconds: 1),
      const Duration(seconds: 2),
    ]);
    world.reconnectDelay.release();
    await settleAll(tester);
    expect(world.reconnectDelay.requested.last, const Duration(seconds: 4));
    expect(world.stateOf(tester, 'alpha'), 'offline');

    alpha.daemon.restart();
    world.reconnectDelay.release();
    await settleAll(tester);
    expect(world.stateOf(tester, 'alpha'), 'connected');
  });

  testWidgets('device_revoked', (tester) async {
    final (world, alpha, _) = await _twoDaemons();
    await world.pump(tester);
    expect(world.stateOf(tester, 'alpha'), 'connected');

    const revoked = DaemonCallException(code: 16, reason: 'device_revoked');
    alpha.daemon.failure = revoked;
    alpha.daemon.kill(error: revoked);
    await settleAll(tester);

    expect(world.stateOf(tester, 'alpha'), 'revoked');
    // The client stops reconnecting and offers to pair again.
    expect(world.reconnectDelay.requested, isEmpty);
    expect(alpha.daemon.calls.where((c) => c == 'GetInfo'), hasLength(1));
    expect(world.stateOf(tester, 'bravo'), 'connected');
    await tester.tap(find.byKey(const ValueKey('daemon:alpha:repair')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pair:string')), findsOneWidget);
  });

  testWidgets('no_shared_api_version', (tester) async {
    final (world, alpha, _) = await _twoDaemons(alphaVersions: ['2.0']);
    await world.pump(tester);

    expect(world.stateOf(tester, 'alpha'), 'incompatible');
    // Nothing but the negotiation call is made, and nothing is retried.
    expect(alpha.daemon.calls, ['GetInfo']);
    expect(world.reconnectDelay.requested, isEmpty);
    expect(world.stateOf(tester, 'bravo'), 'connected');
  });
}
