import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yagura_desktop/src/connection.dart';
import 'package:yagura_desktop/src/credentials.dart';
import 'package:yagura_desktop/src/providers.dart';
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

    // It renewed, then reconnected at once with the new certificate (a
    // second GetInfo and stream) without showing the daemon as lost.
    expect(host.daemon.renewals, hasLength(1));
    expect(world.stateOf(tester, 'alpha'), 'connected');
    expect(world.reconnectDelay.requested, isEmpty);
    expect(host.daemon.calls.where((c) => c == 'GetInfo'), hasLength(2));
    expect(host.daemon.calls.where((c) => c == 'WatchInstances'), hasLength(2));
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

  testWidgets('a_renewed_certificate_is_used_at_once', (tester) async {
    final world = World();
    final host = world.addHost('alpha');
    await world.prePair(host, validFor: const Duration(days: 20));
    final before = await _stored(world, 'alpha');
    await world.pump(tester);

    // No restart, no waiting: the next connection already presents the new
    // certificate, so the daemon has seen it used.
    final after = await _stored(world, 'alpha');
    expect(after.certificateDer, isNot(before.certificateDer));
    expect(world.dialer.secureOpens, hasLength(2));
    expect(
      world.dialer.secureOpens.first.credentials.certificateDer,
      before.certificateDer,
    );
    expect(
      world.dialer.secureOpens.last.credentials.certificateDer,
      after.certificateDer,
    );
    expect(host.certificates.last.used, isTrue);
    expect(host.certificates, hasLength(2));
    expect(world.stateOf(tester, 'alpha'), 'connected');
    // It keeps working after the switch.
    expect(
      world.container.read(daemonConnectionProvider('alpha')).status,
      isA<Connected>(),
    );
  });

  testWidgets('certificates_that_come_back_due_are_renewed_once_a_day', (
    tester,
  ) async {
    final world = World();
    final host = world.addHost('alpha');
    // A daemon whose clock is far behind: what it issues is due at once.
    host.renewalValidFor = const Duration(days: 20);
    await world.prePair(host, validFor: const Duration(days: 20));
    await world.pump(tester);

    // One renewal and one reconnect, no loop, no reconnect wait.
    expect(host.daemon.renewals, hasLength(1));
    expect(world.dialer.secureOpens, hasLength(2));
    expect(world.stateOf(tester, 'alpha'), 'connected');
    expect(world.reconnectDelay.requested, isEmpty);
    // The daemon's detail line says its clock may be wrong.
    String detail() => tester
        .widget<Text>(find.byKey(const ValueKey('daemon:alpha:detail')))
        .data!;
    expect(detail(), contains("The daemon's clock may be wrong"));
    // It waits for the next daily check, and the time is kept.
    expect(world.renewalDelay.pending, 1);
    expect(world.store.records.single.lastRenewal, world.now);

    // The check an hour later does not renew again.
    world.now = world.now.add(const Duration(hours: 1));
    world.renewalDelay.release();
    await settleAll(tester);
    expect(host.daemon.renewals, hasLength(1));
    expect(world.dialer.secureOpens, hasLength(2));

    // Neither does a restart.
    await tester.pumpWidget(const SizedBox());
    await world.pump(tester);
    expect(host.daemon.renewals, hasLength(1));
    expect(detail(), contains("The daemon's clock may be wrong"));

    // The next daily check, a day after the renewal, renews once more.
    world.now = world.now.add(const Duration(hours: 24));
    // (The first pending wait belongs to the session before the restart.)
    expect(world.renewalDelay.pending, 2);
    world.renewalDelay.release();
    world.renewalDelay.release();
    await settleAll(tester);
    expect(host.daemon.renewals, hasLength(2));
    expect(world.dialer.secureOpens, hasLength(4));
    expect(world.reconnectDelay.requested, isEmpty);
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
    // No key is left half-written.
    expect(
      world.keychain.entries.keys.where((k) => k.contains('pending')),
      isEmpty,
    );
  });

  testWidgets('renewal_response_lost_after_the_daemon_renewed', (tester) async {
    final world = World();
    final host = world.addHost('alpha');
    final daemonRule = host.daemon.onRenew!;
    var calls = 0;
    host.daemon.onRenew = (csr) async {
      calls++;
      final response = await daemonRule(csr);
      // The first answer never arrives.
      if (calls == 1) {
        throw const DaemonCallException(code: 14, reason: 'unavailable');
      }
      return response;
    };
    await world.prePair(host, validFor: const Duration(days: 20));
    final before = await _stored(world, 'alpha');
    await world.pump(tester);

    // The old pair is intact and the daemon is still connected.
    expect(host.daemon.renewals, hasLength(1));
    expect(world.stateOf(tester, 'alpha'), 'connected');
    expect(
      (await _stored(world, 'alpha')).certificateDer,
      before.certificateDer,
    );
    expect(
      world.keychain.entries.keys.where((k) => k.contains('pending')),
      isEmpty,
    );

    // The next check renews with the old certificate, and the daemon accepts
    // it because the lost certificate was never used.
    world.now = world.now.add(const Duration(days: 1));
    world.renewalDelay.release();
    await settleAll(tester);
    expect(host.daemon.renewals, hasLength(2));
    expect(world.stateOf(tester, 'alpha'), 'connected');
    final after = await _stored(world, 'alpha');
    expect(after.certificateDer, isNot(before.certificateDer));
    expect(
      after.certificateNotAfter.difference(world.now).inDays,
      greaterThan(300),
    );
    expect(
      EcKeyPair.fromPrivateKeyPem(after.keyPem).publicKey.Q,
      host.renewedKeys.last.Q,
    );

    // The new certificate is already the one the connection presents.
    expect(world.stateOf(tester, 'alpha'), 'connected');
    expect(host.certificates.last.used, isTrue);
    expect(
      world.dialer.secureOpens.last.credentials.certificateDer,
      after.certificateDer,
    );
  });

  testWidgets('renewal_whose_keychain_write_failed', (tester) async {
    final world = World();
    final host = world.addHost('alpha');
    final daemonRule = host.daemon.onRenew!;
    var calls = 0;
    host.daemon.onRenew = (csr) async {
      final response = await daemonRule(csr);
      // The keychain locks while the answer is on its way, once.
      if (++calls == 1) world.keychain.failWrites = true;
      return response;
    };
    await world.prePair(host, validFor: const Duration(days: 20));
    final before = await _stored(world, 'alpha');
    await world.pump(tester);
    world.keychain.failWrites = false;

    expect(world.stateOf(tester, 'alpha'), 'connected');
    expect(
      (await _stored(world, 'alpha')).certificateDer,
      before.certificateDer,
    );

    // The retry with the old pair succeeds.
    world.now = world.now.add(const Duration(days: 1));
    world.renewalDelay.release();
    await settleAll(tester);
    expect(host.daemon.renewals, hasLength(2));
    expect(world.stateOf(tester, 'alpha'), 'connected');
    expect(
      (await _stored(world, 'alpha')).certificateDer,
      isNot(before.certificateDer),
    );
  });

  testWidgets('a_revoked_device_is_revoked_at_renewal', (tester) async {
    final world = World();
    final host = world.addHost('alpha');
    host.daemon.onRenew = (_) async =>
        throw const DaemonCallException(code: 16, reason: 'device_revoked');
    await world.prePair(host, validFor: const Duration(days: 20));
    await world.pump(tester);

    expect(world.stateOf(tester, 'alpha'), 'revoked');
    expect(world.reconnectDelay.requested, isEmpty);
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
