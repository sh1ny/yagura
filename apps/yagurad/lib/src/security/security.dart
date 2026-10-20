import 'dart:async';

import '../host/database.dart';
import '../host/secret_store.dart';
import 'audit.dart';
import 'auth_gate.dart';
import 'devices.dart';
import 'identity.dart';
import 'pairing.dart';

/// How often the failure counts and last seen times are written.
const securityFlushInterval = Duration(seconds: 10);

/// Everything the secure listener needs from the daemon (design D1, D2, D4):
/// identity, devices, pairing, the gate and the two logs. Present only in
/// service mode.
class DaemonSecurity {
  DaemonSecurity._(
    this.identity,
    this.devices,
    this.pairing,
    this.audit,
    this.failures,
    this.gate,
  );

  final DaemonIdentity identity;
  final DeviceStore devices;
  final PairingService pairing;
  final AuditLog audit;
  final AuthFailureLog failures;
  final DeviceAuthGate gate;

  Timer? _timer;

  /// Opens the identity (making it on first start) and the stores. A
  /// failure of the secret store is `secret_store_unavailable`.
  static DaemonSecurity open(
    YaguraDatabase database,
    SecretStore secrets, {
    required DateTime Function() clock,
  }) {
    final identity = DaemonIdentity.open(database, secrets, clock: clock);
    final devices = DeviceStore(database, clock: clock);
    if (identity.recreated) {
      // The old CA is gone: certificates it signed are no longer trusted.
      devices.revokeAll('identity_reset');
    }
    final audit = AuditLog(database, clock: clock);
    final failures = AuthFailureLog(database, clock: clock);
    final security = DaemonSecurity._(
      identity,
      devices,
      PairingService(
        database: database,
        identity: identity,
        devices: devices,
        audit: audit,
        clock: clock,
      ),
      audit,
      failures,
      DeviceAuthGate(
        devices: devices,
        failures: failures,
        audit: audit,
        clock: clock,
      ),
    );
    security._timer = Timer.periodic(securityFlushInterval, (_) {
      security.flush();
    });
    return security;
  }

  /// Revokes [deviceId] and ends its open calls (design D2). The gate's
  /// index is rebuilt before this returns.
  ///
  /// [except] is the call that asked for it, so a device that revokes itself
  /// still gets its answer.
  DeviceRecord revokeDevice(String deviceId, String by, {CallPermit? except}) {
    final device = devices.revoke(deviceId, by);
    gate.cancelCalls(deviceId, except: except);
    return device;
  }

  /// Writes what is held in memory.
  void flush() {
    failures.flush();
    devices.flush();
  }

  void close() {
    _timer?.cancel();
    _timer = null;
    flush();
  }
}
