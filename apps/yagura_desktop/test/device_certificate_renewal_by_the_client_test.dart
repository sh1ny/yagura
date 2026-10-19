import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yagura_desktop/src/credentials.dart';
import 'package:yagura_desktop/src/transport.dart';
import 'package:yagura_pki/yagura_pki.dart';

import 'support/fake_world.dart';

Future<DeviceCredentials> _stored(World world, String id) async =>
    (await CredentialStore(world.keychain).load(id))!;

void main() {
  testWidgets('renewal_on_connect', (tester) async {
    final world = World();
    final host = world.addHost('alpha');
    await world.prePair(host, validFor: const Duration(days: 20));
    final before = await _stored(world, 'alpha');
    await world.pump(tester);

    // It renewed and kept the connection (one GetInfo, one stream).
    expect(host.daemon.renewals, hasLength(1));
    expect(world.stateOf(tester, 'alpha'), 'connected');
    expect(host.daemon.calls.where((c) => c == 'GetInfo'), hasLength(1));
    expect(host.daemon.calls.where((c) => c == 'WatchInstances'), hasLength(1));
    // The new certificate and its new key replaced the old ones together.
    final after = await _stored(world, 'alpha');
    expect(after.certificateDer, isNot(before.certificateDer));
    expect(
      after.certificateNotAfter.difference(world.now).inDays,
      greaterThan(300),
    );
    expect(
      EcKeyPair.fromPrivateKeyPem(after.keyPem).publicKey.Q,
      host.renewedKeys.single.Q,
    );
    expect(after.keyPem, isNot(before.keyPem));
    expect(after.caDer, host.caDer);
    // No key is left half-written.
    expect(
      world.keychain.entries.keys.where((k) => k.contains('pending')),
      isEmpty,
    );
  });

  testWidgets('certificate_already_expired', (tester) async {
    final world = World();
    final host = world.addHost('alpha');
    await world.prePair(
      host,
      validFor: const Duration(days: 365),
      issuedAt: world.now.subtract(const Duration(days: 400)),
    );
    await world.pump(tester);

    // Listed expired without a single call to the daemon, no retry, and
    // re-pairing is offered.
    expect(world.stateOf(tester, 'alpha'), 'expired');
    expect(world.dialer.opened, isEmpty);
    expect(host.daemon.calls, isEmpty);
    expect(world.reconnectDelay.requested, isEmpty);
    expect(find.byKey(const ValueKey('daemon:alpha:repair')), findsOneWidget);
  });

  testWidgets('no_renewal_while_more_than_thirty_days_remain', (tester) async {
    final world = World();
    final host = world.addHost('alpha');
    await world.prePair(host, validFor: const Duration(days: 90));
    await world.pump(tester);

    expect(world.stateOf(tester, 'alpha'), 'connected');
    expect(host.daemon.renewals, isEmpty);
  });

  testWidgets('a_refused_renewal_marks_the_daemon_expired', (tester) async {
    final world = World();
    final host = world.addHost('alpha');
    host.daemon.onRenew = (_) async =>
        throw const DaemonCallException(code: 16, reason: 'unauthenticated');
    await world.prePair(host, validFor: const Duration(days: 20));
    await world.pump(tester);

    expect(world.stateOf(tester, 'alpha'), 'expired');
    expect(world.reconnectDelay.requested, isEmpty);
    expect(find.byKey(const ValueKey('daemon:alpha:repair')), findsOneWidget);
  });

  testWidgets('renewal_is_checked_daily_while_connected', (tester) async {
    final world = World();
    final host = world.addHost('alpha');
    await world.prePair(host, validFor: const Duration(days: 40));
    await world.pump(tester);
    expect(host.daemon.renewals, isEmpty);
    expect(world.renewalDelay.requested, [const Duration(hours: 24)]);

    // Eleven days later fewer than 30 remain, and the daily check renews.
    world.now = world.now.add(const Duration(days: 11));
    world.renewalDelay.release();
    await settleAll(tester);

    expect(host.daemon.renewals, hasLength(1));
    expect(world.stateOf(tester, 'alpha'), 'connected');
  });
}
