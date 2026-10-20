import 'dart:async';
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

  /// Makes `write` fail while reads still work.
  bool failWrites = false;

  /// Makes `delete` fail for keys containing this text.
  String? failDeleteContaining;

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
    if (failWrites) throw const KeychainUnavailable('read-only');
    entries[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _check();
    if (failDeleteContaining case final part? when key.contains(part)) {
      throw const KeychainUnavailable('delete refused');
    }
    entries.remove(key);
  }
}

class MemoryDaemonListStore implements DaemonListStore {
  MemoryDaemonListStore([List<DaemonRecord> initial = const []])
    : records = [...initial];

  List<DaemonRecord> records;

  /// What `load` reports as unreadable or damaged.
  int unreadable = 0;
  bool damaged = false;
  bool copied = true;
  List<String> unreadableNames = [];
  List<String> overCapNames = [];
  String? readError;
  int damagedCopies = 0;

  /// Makes `save` throw while set.
  Object? saveFailure;
  int saves = 0;

  /// While set, `save` waits for it (to interleave other changes).
  Completer<void>? saveGate;

  @override
  Future<DaemonListLoad> load() async => DaemonListLoad(
    [...records],
    unreadable: unreadable,
    damaged: damaged,
    copied: copied,
    unreadableNames: unreadableNames,
    overCapNames: overCapNames,
    readError: readError,
    damagedCopies: damagedCopies,
  );

  @override
  String? get saveRefusal => readError != null || (damaged && !copied)
      ? 'the daemon list is not saved'
      : null;

  @override
  void discardUnreadable() {
    unreadable = 0;
    unreadableNames = [];
    overCapNames = [];
  }

  @override
  Future<void> discardDamagedCopies() async => damagedCopies = 0;

  @override
  Future<void> save(List<DaemonRecord> daemons) async {
    saves++;
    if (saveGate case final gate?) await gate.future;
    if (saveFailure case final failure?) throw failure;
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
    this.daemon.onRenew = _renew;
  }

  /// The device's certificates as the daemon keeps them (design D4): the
  /// fingerprint and whether it ever authenticated a call. The last is the
  /// newest.
  final List<({String sha, bool used})> certificates = [];

  /// The fingerprint presented on the connection that is open.
  String? presenting;

  /// The daemon's gate: a certificate that is not (or no longer) one of the
  /// device's authenticates nothing; one that is, counts as used.
  bool authenticate(String sha) {
    if (certificates.isEmpty) certificates.add((sha: sha, used: true));
    final at = certificates.indexWhere((c) => c.sha == sha);
    if (at < 0) return false;
    certificates[at] = (sha: sha, used: true);
    presenting = sha;
    return true;
  }

  /// `RenewCertificate` with the daemon's rule: the newest certificate may
  /// renew; the one before it only while the newest has never been used. The
  /// certificate that renewed stays, the new one is added, all others go.
  Future<EnrollResponse> _renew(Uint8List csr) async {
    final newest = certificates.last;
    if (presenting != newest.sha && newest.used) {
      throw const DaemonCallException(code: 16, reason: 'unauthenticated');
    }
    final request = CertificationRequest.parse(csr);
    renewedKeys.add(request.publicKey);
    final der = issue(request.publicKey, 'renewed', validFor: renewalValidFor);
    certificates
      ..removeWhere((c) => c.sha != presenting)
      ..add((sha: sha256Hex(der), used: false));
    return EnrollResponse(
      deviceId: 'device-$id',
      clientCertificateDer: der,
      caCertificateDer: caDer,
    );
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

  /// How long the certificates this daemon renews are valid; short ones come
  /// back already due, as from a daemon whose clock is far behind.
  Duration renewalValidFor = const Duration(days: 365);

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
    if (!target.authenticate(sha256Hex(credentials.certificateDer))) {
      return FakeDaemon()
        ..failure = const DaemonCallException(
          code: 16,
          reason: 'unauthenticated',
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

  /// A store to use instead of [store], for tests over the real file.
  DaemonListStore? fileStore;
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
    daemonListStoreProvider.overrideWithValue(fileStore ?? store),
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
