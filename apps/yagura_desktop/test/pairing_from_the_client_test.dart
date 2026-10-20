import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yagura_desktop/src/credentials.dart';
import 'package:yagura_pki/yagura_pki.dart';

import 'support/fake_world.dart';
import 'support/pairing_ui.dart';

bool _contains(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length && match; j++) {
      match = haystack[i + j] == needle[j];
    }
    if (match) return true;
  }
  return false;
}

void main() {
  testWidgets('pair_a_new_daemon', (tester) async {
    final world = World();
    final host = world.addHost('alpha', name: 'Alpha host');
    await world.pump(tester);
    expect(daemonCard('alpha'), findsNothing);

    await pairThroughTheUi(tester, host.pairingString());

    // The daemon is added and connected.
    expect(pairingError(tester), isNull);
    expect(world.stateOf(tester, 'alpha'), 'connected');
    final record = world.store.records.single;
    expect(record.id, 'alpha');
    expect(record.address, '10.0.0.2:7443');
    expect(record.caFingerprint, host.fingerprint);

    // The code, the name and a CSR were sent, nothing else.
    final request = host.enrollRequests.single;
    expect(request.code, 'ABCDEFGHJK');
    expect(request.deviceName, 'my-laptop');
    final credentials = (await CredentialStore(world.keychain).load('alpha'))!;
    final key = EcKeyPair.fromPrivateKeyPem(credentials.keyPem);
    final csr = CertificationRequest.parse(Uint8List.fromList(request.csrDer));
    expect(csr.publicKey.Q, key.publicKey.Q);
    final scalar = key.privateKey.d!.toRadixString(16).padLeft(64, '0');
    final scalarBytes = [
      for (var i = 0; i < 64; i += 2)
        int.parse(scalar.substring(i, i + 2), radix: 16),
    ];
    expect(_contains(request.writeToBuffer(), scalarBytes), isFalse);
    // The key, the certificate and the CA are in the keychain.
    expect(credentials.caDer, host.caDer);
    expect(
      Certificate.parse(credentials.certificateDer).subject.commonName,
      'my-laptop',
    );
    // Info came over a channel that pins nothing; Enroll came over one that
    // pins the checked CA and the daemon's fixed name.
    expect(host.channels, [
      (pinned: false, authority: null),
      (pinned: true, authority: 'yagurad-alpha'),
    ]);
  });

  testWidgets('malformed_pairing_string', (tester) async {
    final world = World();
    final host = world.addHost('alpha');
    await world.pump(tester);

    for (final text in [
      'hello world',
      'https://10.0.0.2:7443?code=ABCDEFGHJK&ca=sha256:${host.fingerprint}',
      'yagura://10.0.0.2:7443?code=ABCDEFGHJK',
      'yagura://10.0.0.2:7443?code=ABCDEFGHJK&ca=sha256:abcd',
      'yagura://:7443?code=ABCDEFGHJK&ca=sha256:${host.fingerprint}',
    ]) {
      await pairThroughTheUi(tester, text);
      expect(pairingError(tester), contains('invalid_pairing_string'));
      // The dialog stays open for another try.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }

    // No network call, no key, no daemon.
    expect(world.dialer.opened, isEmpty);
    expect(world.keychain.entries, isEmpty);
    expect(world.store.records, isEmpty);
  });

  testWidgets('pairing_code_rejected', (tester) async {
    final world = World();
    final host = world.addHost('alpha');
    final string = host.pairingString(); // with the code the host issued
    host.pairingCode = null; // which expired or was used since
    await world.pump(tester);

    await pairThroughTheUi(tester, string);

    expect(pairingError(tester), contains('expired or was used'));
    expect(daemonCard('alpha'), findsNothing);
    expect(world.store.records, isEmpty);
    // A key existed while the code was checked, and it is gone.
    expect(host.keychainAtEnroll, isNotEmpty);
    expect(world.keychain.entries, isEmpty);
  });

  testWidgets('a_locked_keychain_refuses_pairing', (tester) async {
    final world = World();
    final host = world.addHost('alpha');
    world.keychain.unavailable = true;
    await world.pump(tester);

    await pairThroughTheUi(tester, host.pairingString());

    expect(pairingError(tester), contains('keychain_unavailable'));
    expect(host.enrollRequests, isEmpty);
    expect(world.store.records, isEmpty);
  });
}
