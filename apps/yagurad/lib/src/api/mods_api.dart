import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../host/daemon.dart';
import '../mods/mod_entry.dart';
import '../mods/mods_service.dart';
import 'convert.dart';
import 'service_support.dart';

/// The `Mods` service (design D7, D14): each instance's mod list, staging,
/// and the check for newer versions. Setting the list never waits for Steam;
/// staging and updates are operations.
class ModsApi extends pb.ModsServiceBase with GuardedService {
  ModsApi(this.daemon, this.logSink);

  final Daemon daemon;

  @override
  final LogSink logSink;

  @override
  Future<pb.ListModsResponse> listMods(
    ServiceCall call,
    pb.ListModsRequest request,
  ) async =>
      _response(request.instanceId, daemon.mods.list(request.instanceId));

  @override
  Future<pb.ListModsResponse> setMods(
    ServiceCall call,
    pb.SetModsRequest request,
  ) async => _response(
    request.instanceId,
    daemon.mods.setMods(
      request.instanceId,
      expectedRevision: request.expectedRevision.toInt(),
      refs: [
        for (final ref in request.mods)
          ModRef(source: ref.source, itemId: ref.itemId, role: ref.role),
      ],
    ),
  );

  @override
  Future<pb.Operation> applyMods(
    ServiceCall call,
    pb.ApplyModsRequest request,
  ) async => operationToPb(daemon.instances.applyMods(request.instanceId));

  @override
  Future<pb.Operation> checkModUpdates(
    ServiceCall call,
    pb.CheckModUpdatesRequest request,
  ) async =>
      operationToPb(daemon.instances.checkModUpdates(request.instanceId));

  @override
  Future<pb.Operation> updateMods(
    ServiceCall call,
    pb.UpdateModsRequest request,
  ) async => operationToPb(
    daemon.instances.updateMods(request.instanceId, request.itemIds),
  );

  pb.ListModsResponse _response(String instanceId, ModsListing listing) {
    final record = daemon.instances.requireRecord(instanceId);
    final appId =
        daemon.plugins.find(record.pluginId)?.manifest.mods?.workshopAppId ?? 0;
    final positions = <String, int>{};
    return pb.ListModsResponse(
      mods: [
        for (final mod in listing.mods)
          _mod(
            mod,
            positions[mod.role] = (positions[mod.role] ?? -1) + 1,
            appId,
          ),
      ],
      updateCheck: listing.updateCheck,
      checkedAt: listing.checkedAt == null
          ? null
          : timestamp(listing.checkedAt!),
    );
  }

  pb.Mod _mod(ModEntry mod, int position, int appId) => pb.Mod(
    source: mod.source,
    itemId: mod.itemId,
    name: mod.title,
    role: mod.role,
    position: position,
    status: mod.status,
    stagedName: mod.stagedName,
    desiredVersion: mod.desiredVersion,
    stagedVersion: mod.stagedVersion,
    sizeBytes: Int64(daemon.mods.sizeOf(mod, appId)),
    localUpdated: _at(int.tryParse(mod.stagedVersion) ?? 0),
    remoteUpdated: _at(mod.remoteUpdated),
    updateAvailable: mod.updateAvailable,
    lastError: mod.lastError,
    warnings: mod.warnings,
  );

  /// Unix seconds as a timestamp; unset for 0 (never).
  static Timestamp? _at(int seconds) => seconds <= 0
      ? null
      : timestamp(
          DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
        );
}
