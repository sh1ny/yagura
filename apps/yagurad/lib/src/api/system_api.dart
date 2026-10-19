import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../errors.dart';
import '../host/daemon.dart';
import '../host/secret_store.dart';
import '../instances/instance.dart';
import '../platform/disk_space.dart';
import '../version.dart';
import 'convert.dart';
import 'service_support.dart';

/// Components this daemon version does not build yet (design D7, D11). The
/// secret store joins them on a host without one, and the service accounts
/// are built only where the daemon manages them (service mode; a development
/// daemon runs everything as the current user).
List<String> notBuiltComponents({
  required bool secretStore,
  required bool serviceAccounts,
}) => [
  if (!secretStore) 'secret_store',
  'firewall',
  if (!serviceAccounts) 'service_accounts',
];

/// The `System` service: `GetInfo`, `GetHealth` and `ListAudit`.
class SystemApi extends pb.SystemServiceBase with GuardedService {
  SystemApi(this.daemon, this.logSink, {required this.devMode});

  final Daemon daemon;

  /// Whether callers are unauthenticated (the gate is `AllowAllGate`).
  final bool devMode;

  @override
  final LogSink logSink;

  @override
  Future<pb.DaemonInfo> getInfo(
    ServiceCall call,
    pb.GetInfoRequest request,
  ) async => pb.DaemonInfo(
    daemonVersion: daemonVersion,
    apiVersion: apiVersions.last,
    apiVersions: apiVersions,
    hostName: Platform.localHostname,
    os: daemon.os,
    osVersion: Platform.operatingSystemVersion,
    dataDir: daemon.dataDirectory.path,
    startedAt: timestamp(daemon.startedAt),
    devMode: devMode,
  );

  @override
  Future<pb.DaemonHealth> getHealth(
    ServiceCall call,
    pb.GetHealthRequest request,
  ) async {
    var databaseOk = true;
    try {
      daemon.operations.get('health-probe');
    } on Object {
      databaseOk = false;
    }
    var free = 0;
    try {
      free = (await probeDiskSpace(daemon.dataDirectory.path)).freeBytes;
    } on Object {
      // Unknown free space reads as 0.
    }
    final instances = daemon.instances.list();
    final security = daemon.security;
    final store = daemon.secrets;
    final secretStore = store is DatabaseSecretStore && store.available;
    var secretStoreOk = false;
    if (secretStore) {
      try {
        store.contains('health-probe');
        secretStoreOk = true;
      } on Object {
        // Reads as not ok.
      }
    }
    return pb.DaemonHealth(
      databaseOk: databaseOk,
      dataVolumeFreeBytes: Int64(free),
      runningInstances: [
        for (final i in instances)
          if (i.state == InstanceState.running) i,
      ].length,
      queuedOperations: instances.fold<int>(
        0,
        (sum, i) => sum + i.queuedOperations,
      ),
      leakedHookWorkers: daemon.hooks.leakedWorkers,
      hooksDegraded: daemon.hooks.degraded,
      pluginsOk: daemon.plugins.results.every((r) => r.isLoaded),
      secretStoreOk: secretStoreOk,
      notBuilt: notBuiltComponents(
        secretStore: secretStore,
        serviceAccounts: daemon.serviceAccountsManaged,
      ),
      adminChannelOk: daemon.adminChannelOk,
      serviceAccountsOk: daemon.serviceAccountsOk,
      serverCertNotAfter: security == null
          ? null
          : timestamp(security.identity.serverCertificate.notAfter),
    );
  }

  @override
  Future<pb.ListAuditResponse> listAudit(
    ServiceCall call,
    pb.ListAuditRequest request,
  ) async {
    // A dev daemon has no devices and keeps no audit log.
    final audit = daemon.security?.audit;
    if (audit == null) {
      throw YaguraException(
        'not_implemented',
        'System.ListAudit is not implemented in dev mode',
      );
    }
    final limit = request.pageSize == 0 ? 100 : request.pageSize.clamp(1, 1000);
    // The token is the id of the last entry of the previous page.
    final before = int.tryParse(request.pageToken);
    final entries = audit.list(limit: limit + 1, before: before);
    final page = entries.take(limit).toList();
    return pb.ListAuditResponse(
      entries: [
        for (final e in page)
          pb.AuditEntry(
            at: timestamp(e.at),
            deviceId: e.deviceId,
            remoteAddress: e.address,
            method: e.method,
            target: e.target,
            result: e.result,
          ),
      ],
      nextPageToken: entries.length > limit ? '${page.last.id}' : '',
    );
  }
}
