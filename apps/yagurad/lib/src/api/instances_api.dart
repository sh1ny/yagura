import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:grpc/grpc.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../errors.dart';
import '../host/daemon.dart';
import '../instances/instance.dart' as domain;
import 'convert.dart';
import 'pressure.dart';
import 'service_support.dart';

/// Limits of one `WatchInstances` subscriber (design D15, Resource Bounds).
class WatchLimits {
  const WatchLimits({
    this.maxEvents = 1000,
    this.maxBytes = 8 * 1024 * 1024,
    this.maxSubscribers = 32,
  });

  /// Events that may wait for a client that does not read.
  final int maxEvents;

  /// Bytes that may wait for it.
  final int maxBytes;

  /// Subscribers per daemon.
  final int maxSubscribers;
}

/// The `Instances` service (design D24).
class InstancesApi extends pb.InstancesServiceBase with GuardedService {
  InstancesApi(
    this.daemon,
    this.logSink, {
    this.watchLimits = const WatchLimits(),
  });

  final Daemon daemon;
  final WatchLimits watchLimits;

  @override
  final LogSink logSink;

  var _subscribers = 0;

  domain.Instance _instance(String id) => daemon.instances.get(id);

  // ---- reading ----------------------------------------------------------------

  @override
  Future<pb.ListInstancesResponse> listInstances(
    ServiceCall call,
    pb.ListInstancesRequest request,
  ) async => pb.ListInstancesResponse(
    instances: [for (final i in daemon.instances.list()) instanceToPb(i)],
  );

  @override
  Future<pb.Instance> getInstance(
    ServiceCall call,
    pb.GetInstanceRequest request,
  ) async => instanceToPb(_instance(request.instanceId));

  /// A snapshot of every instance, then slim deltas (design D15).
  ///
  /// Events pile up for a client that does not read; at the limit they are
  /// dropped, `resync_required` follows when the client reads again, and a
  /// fresh snapshot after it.
  @override
  Stream<pb.InstanceEvent> watchInstances(
    ServiceCall call,
    pb.WatchInstancesRequest request,
  ) {
    if (_subscribers >= watchLimits.maxSubscribers) {
      throw YaguraException(
        'too_many_subscribers',
        'this daemon already has ${watchLimits.maxSubscribers} instance '
            'subscribers',
        details: {'limit': watchLimits.maxSubscribers},
      );
    }
    final pressure = call is YaguraCall ? call.pressure : null;
    // What each instance's settings looked like when last sent.
    final sent = <String, String>{};
    StreamSubscription<domain.InstanceEvent>? source;
    late final StreamController<pb.InstanceEvent> controller;

    void sendSnapshot() {
      sent.clear();
      final instances = daemon.instances.list();
      for (final instance in instances) {
        sent[instance.id] = _digest(instance);
      }
      controller.add(
        pb.InstanceEvent(
          snapshot: pb.InstanceSnapshot(
            instances: [for (final i in instances) instanceToPb(i)],
          ),
        ),
      );
    }

    bool resyncIfBehind() {
      if (pressure == null) return false;
      if (pressure.queuedMessages < watchLimits.maxEvents &&
          pressure.queuedBytes < watchLimits.maxBytes) {
        return false;
      }
      pressure.dropQueuedData();
      controller.add(pb.InstanceEvent(resyncRequired: pb.ResyncRequired()));
      sendSnapshot();
      return true;
    }

    pb.InstanceEvent? delta(domain.InstanceEvent event) => switch (event) {
      domain.InstanceChanged(:final instance) => pb.InstanceEvent(
        changed: instanceToPb(
          instance,
          includeSettings: _settingsChanged(sent, instance),
        ),
      ),
      domain.InstanceRemoved(:final instanceId) => () {
        sent.remove(instanceId);
        return pb.InstanceEvent(removedInstanceId: instanceId);
      }(),
      domain.InstanceNotice(
        :final instanceId,
        :final kind,
        :final message,
        :final exitCode,
        :final lastLogLines,
      ) =>
        pb.InstanceEvent(
          notice: pb.InstanceNotice(
            instanceId: instanceId,
            kind: kind,
            message: message,
            exitCode: exitCode,
            lastLogLines: lastLogLines,
            at: timestamp(DateTime.now()),
          ),
        ),
    };

    controller = StreamController<pb.InstanceEvent>(
      sync: true,
      onListen: () {
        _subscribers++;
        // Subscribe before reading the snapshot, in the same turn, so no
        // change falls between them.
        source = daemon.instances.events.listen((event) {
          if (resyncIfBehind()) return;
          if (delta(event) case final out?) controller.add(out);
        }, onDone: () => unawaited(controller.close()));
        sendSnapshot();
      },
      onCancel: () async {
        _subscribers--;
        await source?.cancel();
      },
    );
    return controller.stream;
  }

  static String _digest(domain.Instance instance) =>
      sha256.convert(utf8.encode(jsonEncode(instance.settings))).toString();

  /// Whether [instance]'s settings differ from what was last sent; records
  /// what is sent now.
  static bool _settingsChanged(
    Map<String, String> sent,
    domain.Instance instance,
  ) {
    final digest = _digest(instance);
    final changed = sent[instance.id] != digest;
    sent[instance.id] = digest;
    return changed;
  }

  // ---- configuration ----------------------------------------------------------

  @override
  Future<pb.Instance> createInstance(
    ServiceCall call,
    pb.CreateInstanceRequest request,
  ) async {
    final settings = parseDocument(
      request.hasSettings() ? request.settings : null,
      'settings',
    );
    final instance = await daemon.instances.create(
      domain.CreateInstanceRequest(
        pluginId: request.pluginId,
        name: request.name,
        directory: request.directory.isEmpty ? null : request.directory,
        settings: settings,
        ports: portOverrides(request.ports),
        steamAccountId: request.steamAccountId.isEmpty
            ? null
            : request.steamAccountId,
        schemaVersion:
            request.hasSettings() && request.settings.schemaVersion != 0
            ? request.settings.schemaVersion
            : null,
      ),
    );
    return instanceToPb(instance);
  }

  @override
  Future<pb.Instance> updateSettings(
    ServiceCall call,
    pb.UpdateSettingsRequest request,
  ) async {
    final settings = parseDocument(
      request.hasSettings() ? request.settings : null,
      'settings',
      required: true,
    );
    final version = request.hasSettings() ? request.settings.schemaVersion : 0;
    final instance = daemon.instances.updateSettings(
      domain.UpdateSettingsRequest(
        instanceId: request.instanceId,
        settings: settings,
        ports: request.ports.isEmpty ? null : portOverrides(request.ports),
        exposure: request.ports.isEmpty ? null : portExposure(request.ports),
        restartPolicy: request.hasRestartPolicy()
            ? request.restartPolicy
            : null,
        steamAccountId: request.hasSteamAccountId()
            ? request.steamAccountId
            : null,
        autostart: request.hasAutostart() ? request.autostart : null,
        schemaVersion: version == 0 ? null : version,
        expectedRevision: request.expectedRevision.toInt(),
      ),
    );
    return instanceToPb(instance);
  }

  /// Stores a secret setting value (design D3); the value is never returned.
  @override
  Future<pb.Instance> setSecret(
    ServiceCall call,
    pb.SetSecretRequest request,
  ) async => instanceToPb(
    daemon.instances.setSecret(
      request.instanceId,
      request.key,
      request.value,
      expectedRevision: request.expectedRevision.toInt(),
    ),
  );

  @override
  Future<pb.Instance> deleteSecret(
    ServiceCall call,
    pb.DeleteSecretRequest request,
  ) async => instanceToPb(
    daemon.instances.deleteSecret(
      request.instanceId,
      request.key,
      expectedRevision: request.expectedRevision.toInt(),
    ),
  );

  @override
  Future<pb.Operation> deleteInstance(
    ServiceCall call,
    pb.DeleteInstanceRequest request,
  ) async => operationToPb(
    daemon.instances.delete(
      request.instanceId,
      deleteFiles: request.deleteFiles,
      confirmName: request.confirmName,
      expectedRevision: request.expectedRevision.toInt(),
    ),
  );

  @override
  Future<pb.ImportInstanceResponse> importInstance(
    ServiceCall call,
    pb.ImportInstanceRequest request,
  ) => throw _notImplemented('ImportInstance');

  @override
  Future<pb.ExportInstanceResponse> exportInstance(
    ServiceCall call,
    pb.ExportInstanceRequest request,
  ) => throw _notImplemented('ExportInstance');

  // ---- lifecycle --------------------------------------------------------------

  @override
  Future<pb.Operation> install(
    ServiceCall call,
    pb.LifecycleRequest request,
  ) async => operationToPb(
    daemon.instances.install(
      request.instanceId,
      validateFiles: request.validateFiles,
    ),
  );

  @override
  Future<pb.Operation> update(
    ServiceCall call,
    pb.LifecycleRequest request,
  ) async => operationToPb(
    daemon.instances.update(
      request.instanceId,
      skipSnapshot: request.skipSnapshot,
      validateFiles: request.validateFiles,
    ),
  );

  @override
  Future<pb.Operation> validate(
    ServiceCall call,
    pb.LifecycleRequest request,
  ) async => operationToPb(daemon.instances.validate(request.instanceId));

  @override
  Future<pb.Operation> start(
    ServiceCall call,
    pb.LifecycleRequest request,
  ) async => operationToPb(daemon.instances.start(request.instanceId));

  @override
  Future<pb.Operation> stop(
    ServiceCall call,
    pb.LifecycleRequest request,
  ) async => operationToPb(
    daemon.instances.stop(request.instanceId, force: request.force),
  );

  @override
  Future<pb.Operation> restart(
    ServiceCall call,
    pb.LifecycleRequest request,
  ) async => operationToPb(daemon.instances.restart(request.instanceId));

  @override
  Future<pb.Operation> applyConfig(
    ServiceCall call,
    pb.LifecycleRequest request,
  ) => throw _notImplemented('ApplyConfig');

  @override
  Future<pb.Instance> acknowledge(
    ServiceCall call,
    pb.LifecycleRequest request,
  ) async => instanceToPb(daemon.instances.acknowledge(request.instanceId));

  // ---- snapshots --------------------------------------------------------------

  @override
  Future<pb.ListSnapshotsResponse> listSnapshots(
    ServiceCall call,
    pb.GetInstanceRequest request,
  ) async => pb.ListSnapshotsResponse(
    snapshots: [
      for (final s in daemon.instances.listSnapshots(request.instanceId))
        snapshotToPb(s),
    ],
  );

  @override
  Future<pb.Operation> restoreSnapshot(
    ServiceCall call,
    pb.RestoreSnapshotRequest request,
  ) async => operationToPb(
    daemon.instances.restoreSnapshot(
      request.instanceId,
      request.snapshotId,
      expectedRevision: request.expectedRevision.toInt(),
    ),
  );

  @override
  Future<pb.ListSnapshotsResponse> listOrphanSnapshots(
    ServiceCall call,
    pb.ListOrphanSnapshotsRequest request,
  ) async => pb.ListSnapshotsResponse(
    snapshots: [
      for (final s in daemon.instances.listOrphanSnapshots()) snapshotToPb(s),
    ],
  );

  YaguraException _notImplemented(String method) => YaguraException(
    'not_implemented',
    'Instances.$method is not implemented in this version',
  );
}
