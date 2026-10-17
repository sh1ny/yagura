import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../errors.dart';
import '../host/daemon.dart';
import '../instances/instance.dart';
import '../platform/disk_space.dart';
import '../version.dart';
import 'convert.dart';
import 'service_support.dart';

/// Components M1 does not have (design D24); their `*_ok` fields mean
/// nothing.
const m1NotBuilt = ['secret_store', 'firewall'];

/// The `System` service: `GetInfo` and `GetHealth`; `ListAudit` arrives with
/// remote clients (M2).
class SystemApi extends pb.SystemServiceBase with GuardedService {
  SystemApi(this.daemon, this.logSink, {required this.devMode});

  final Daemon daemon;
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
      notBuilt: m1NotBuilt,
    );
  }

  @override
  Future<pb.ListAuditResponse> listAudit(
    ServiceCall call,
    pb.ListAuditRequest request,
  ) => throw YaguraException(
    'not_implemented',
    'System.ListAudit is not implemented in this version',
  );
}
