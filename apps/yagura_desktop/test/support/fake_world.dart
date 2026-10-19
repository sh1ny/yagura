import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' show ECPublicKey;
import 'package:yagura_desktop/src/credentials.dart';
import 'package:yagura_desktop/src/daemon_record.dart';
import 'package:yagura_desktop/src/dialer.dart';
import 'package:yagura_desktop/src/keychain.dart';
import 'package:yagura_desktop/src/providers.dart';
import 'package:yagura_desktop/src/transport.dart';
import 'package:yagura_desktop/src/ui/daemons_page.dart';
import 'package:yagura_pki/yagura_pki.dart';
import 'package:yagura_proto/yagura_proto.dart';

import 'fake_daemon.dart';

/// The time every test starts at: a local time, so formatted output does not
/// depend on the time zone.
final DateTime kTestNow = DateTime(2026, 10, 19, 12);

/// An in-memory keychain. [unavailable] makes every call fail.
class FakeKeychain implements Keychain {
  final Map<String, String> entries = {};
  bool unavailable = false;

  void _check() {
    if (unavailable) throw const KeychainUnavailable('locked');
  }

  @override
  Future<String?> read(String key) async {
    _check();
    return entries[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _check();
    entries[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _check();
    entries.remove(key);
  }
}

class MemoryDaemonListStore implements DaemonListStore {
  MemoryDaemonListStore([List<DaemonRecord> initial = const []])
    : records = [...initial];

  List<DaemonRecord> records;

  @override
  Future<List<DaemonRecord>> load() async => [...records];

  @override
  Future<void> save(List<DaemonRecord> daemons) async {
    records = [...daemons];
  }
}

/// A daemon the client can pair with: it has a CA, a pairing code and a
/// [FakeDaemon] behind the secure connection.
class FakeHost {
  FakeHost({
    required this.id,
    this.name = 'Host',
    this.host = '10.0.0.2',
    this.port = 7443,
    FakeDaemon? daemon,
    DateTime Function()? now,
  }) : daemon = daemon ?? FakeDaemon(),
       _now = now ?? (() => kTestNow) {
    caKey = generateKeyPair();
    final start = _now().subtract(const Duration(days: 1));
    caDer = issueCaCertificate(
      key: caKey,
      commonName: 'Yagura CA $id',
      notBefore: start,
      notAfter: start.add(const Duration(days: 7300)),
    );
    ca = Certificate.parse(caDer);
    this.daemon.onRenew = (csr) async {
      final request = CertificationRequest.parse(csr);
      renewedKeys.add(request.publicKey);
      return EnrollResponse(
        deviceId: 'device-$id',
        clientCertificateDer: issue(request.publicKey, 'renewed'),
        caCertificateDer: caDer,
      );
    };
  }

  final String id;
  final String name;
  final String host;
  final int port;
  final FakeDaemon daemon;
  final DateTime Function() _now;

  late final EcKeyPair caKey;
  late final Uint8List caDer;
  late final Certificate ca;

  /// What `Pairing.Info` presents as the CA; defaults to the real one.
  Uint8List? presentedCa;

  /// The currently valid pairing code, or null.
  String? pairingCode = 'ABCDEFGHJK';

  final List<EnrollRequest> enrollRequests = [];
  final List<ECPublicKey> renewedKeys = [];

  /// How each pairing channel to this host was opened.
  final List<({bool pinned, String? authority})> channels = [];

  /// Keychain keys present when the last `Enroll` arrived.
  Set<String> keychainAtEnroll = const {};

  String get key => '$host:$port';

  String get fingerprint => sha256Hex(caDer);

  String get authority => 'yagurad-$id';

  String pairingString({String? code, String? fingerprint}) =>
      'yagura://$host:$port?code=${code ?? pairingCode}'
      '&ca=sha256:${fingerprint ?? this.fingerprint}'
      '&name=${Uri.encodeComponent(name)}';

  /// A client certificate for [key], valid [validFor] from [issuedAt].
  Uint8List issue(
    ECPublicKey key,
    String deviceName, {
    Duration validFor = const Duration(days: 365),
    DateTime? issuedAt,
  }) {
    final start = (issuedAt ?? _now()).subtract(const Duration(hours: 1));
    return issueClientCertificate(
      issuerKey: caKey,
      issuer: ca,
      subjectKey: key,
      commonName: deviceName,
      notBefore: start,
      notAfter: start.add(validFor + const Duration(hours: 1)),
    );
  }
}

/// One `DaemonDialer.secure` call.
typedef SecureOpen = ({
  String host,
  int port,
  String authority,
  DeviceCredentials credentials,
});

/// Hands out the hosts' fake daemons; every open is recorded.
class FakeDialer implements DaemonDialer {
  FakeDialer(this.keychain);

  final FakeKeychain keychain;
  final Map<String, FakeHost> hosts = {};
  final List<SecureOpen> secureOpens = [];

  /// Every network open, in order: `secure:<address>`, `pairing:<address>`.
  final List<String> opened = [];

  @override
  DaemonTransport secure({
    required String host,
    required int port,
    required String authority,
    required DeviceCredentials credentials,
  }) {
    opened.add('secure:$host:$port');
    secureOpens.add((
      host: host,
      port: port,
      authority: authority,
      credentials: credentials,
    ));
    final target = hosts['$host:$port'];
    if (target == null) {
      return FakeDaemon()
        ..failure = const DaemonCallException(code: 14, reason: 'unavailable');
    }
    // The client trusts only the CA it pinned, and checks the fixed name.
    if (!_same(credentials.caDer, target.caDer) ||
        authority != target.authority) {
      return FakeDaemon()
        ..failure = const DaemonCallException(
          code: 14,
          reason: 'server_ca_mismatch',
        );
    }
    return target.daemon;
  }

  @override
  DaemonTransport development({required String host, required int port}) {
    opened.add('development:$host:$port');
    final target = hosts['$host:$port'];
    return target?.daemon ??
        (FakeDaemon()
          ..failure = const DaemonCallException(
            code: 14,
            reason: 'unavailable',
          ));
  }

  @override
  PairingChannel pairing({
    required String host,
    required int port,
    Uint8List? pinnedCa,
    String? authority,
  }) {
    opened.add('pairing:$host:$port');
    final target = hosts['$host:$port'];
    target?.channels.add((pinned: pinnedCa != null, authority: authority));
    return _FakeChannel(this, target, pinnedCa, authority);
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _FakeChannel implements PairingChannel {
  _FakeChannel(this._dialer, this._host, this._pinnedCa, this._authority);

  final FakeDialer _dialer;
  final FakeHost? _host;
  final Uint8List? _pinnedCa;
  final String? _authority;

  FakeHost _reachable() {
    final host = _host;
    if (host == null) {
      throw const DaemonCallException(code: 14, reason: 'unavailable');
    }
    // A pinned channel only talks to the daemon whose CA it pinned.
    if (_pinnedCa != null &&
        (!_same(_pinnedCa, host.caDer) || _authority != host.authority)) {
      throw const DaemonCallException(code: 14, reason: 'server_ca_mismatch');
    }
    return host;
  }

  @override
  Future<PairingInfo> info() async {
    final host = _reachable();
    final ca = host.presentedCa ?? host.caDer;
    return PairingInfo(
      daemonName: host.name,
      caFingerprintSha256: sha256Hex(ca),
      apiVersion: '1.0',
      caCertificateDer: ca,
      tlsAuthority: host.authority,
    );
  }

  @override
  Future<EnrollResponse> enroll(EnrollRequest request) async {
    final host = _reachable();
    if (_pinnedCa == null) {
      throw StateError('Pairing.Enroll on a channel that pins no CA');
    }
    host.enrollRequests.add(request);
    host.keychainAtEnroll = {..._dialer.keychain.entries.keys};
    if (request.code != host.pairingCode) {
      throw const DaemonCallException(code: 7, reason: 'pairing_code_invalid');
    }
    host.pairingCode = null;
    final csr = CertificationRequest.parse(Uint8List.fromList(request.csrDer));
    return EnrollResponse(
      deviceId: 'device-${host.id}',
      clientCertificateDer: host.issue(csr.publicKey, request.deviceName),
      caCertificateDer: host.caDer,
    );
  }

  @override
  Future<void> close() async {}
}

/// Everything a multi-daemon widget test needs: a fake keychain, a daemon
/// list store, a dialer with fake hosts, and delays the test releases by hand.
class World {
  World() {
    dialer = FakeDialer(keychain);
  }

  final keychain = FakeKeychain();
  final store = MemoryDaemonListStore();
  late final FakeDialer dialer;
  final reconnectDelay = FakeDelay();
  final renewalDelay = FakeDelay();
  DateTime now = kTestNow;
  bool devDaemon = false;

  final List<FakeHost> hosts = [];

  FakeHost addHost(
    String id, {
    String? name,
    String host = '10.0.0.2',
    int port = 7443,
    FakeDaemon? daemon,
  }) {
    final fake = FakeHost(
      id: id,
      name: name ?? 'Host $id',
      host: host,
      port: port,
      daemon: daemon,
    );
    dialer.hosts[fake.key] = fake;
    hosts.add(fake);
    return fake;
  }

  /// Marks [host] as already paired: its credentials are in the keychain and
  /// the daemon is in the list, with a client certificate valid for
  /// [validFor] from now.
  Future<DaemonRecord> prePair(
    FakeHost host, {
    Duration validFor = const Duration(days: 365),
    DateTime? issuedAt,
  }) async {
    final key = generateKeyPair();
    final credentials = DeviceCredentials(
      caDer: host.caDer,
      certificateDer: host.issue(
        key.publicKey,
        'test-device',
        validFor: validFor,
        issuedAt: issuedAt,
      ),
      keyPem: key.privateKeyPem,
    );
    await CredentialStore(keychain).save(host.id, credentials);
    final record = DaemonRecord(
      id: host.id,
      name: host.name,
      host: host.host,
      port: host.port,
      caFingerprint: host.fingerprint,
    );
    store.records = [...store.records, record];
    return record;
  }

  List<Override> get overrides => [
    keychainProvider.overrideWithValue(keychain),
    daemonListStoreProvider.overrideWithValue(store),
    daemonDialerProvider.overrideWithValue(dialer),
    clockProvider.overrideWithValue(() => now),
    reconnectDelayProvider.overrideWithValue(reconnectDelay.call),
    renewalDelayProvider.overrideWithValue(renewalDelay.call),
    devDaemonEnabledProvider.overrideWithValue(devDaemon),
  ];

  late ProviderContainer container;

  /// Pumps the daemon list in an app wired to this world.
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1000, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return const DaemonsPage();
            },
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// The state label the list shows for [id].
  String? stateOf(WidgetTester tester, String id) {
    final finder = find.byKey(ValueKey('daemon:$id:state'));
    if (finder.evaluate().isEmpty) return null;
    return tester.widget<Text>(finder).data;
  }
}

Finder daemonCard(String id) => find.byKey(ValueKey('daemon:$id'));

/// Pumps until the queued asynchronous work (keychain, store, connection)
/// has settled.
Future<void> settleAll(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}
