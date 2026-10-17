/// A snapshot to take of an instance's data paths.
class SnapshotRequest {
  const SnapshotRequest({
    required this.instanceId,
    required this.instanceName,
    required this.instanceDirectory,
    required this.dataPaths,
    required this.reason,
  });

  final String instanceId;
  final String instanceName;
  final String instanceDirectory;

  /// Absolute data paths, resolved inside the instance directory.
  final List<String> dataPaths;

  /// `pre_update`, `pre_delete` or `pre_restore`.
  final String reason;
}

/// What the snapshot list shows (mirrors `Snapshot` in `instances.proto`).
class SnapshotInfo {
  const SnapshotInfo({
    required this.id,
    required this.instanceId,
    required this.instanceName,
    required this.reason,
    required this.createdAt,
    required this.sizeBytes,
  });

  final String id;
  final String instanceId;
  final String instanceName;
  final String reason;
  final DateTime createdAt;
  final int sizeBytes;

  @override
  String toString() => 'SnapshotInfo($instanceId/$id $reason)';
}

/// Restoring [snapshotId] over the data paths of an instance.
class RestoreRequest {
  const RestoreRequest({
    required this.instanceId,
    required this.instanceName,
    required this.instanceDirectory,
    required this.dataPaths,
    required this.snapshotId,
  });

  final String instanceId;
  final String instanceName;
  final String instanceDirectory;

  /// The plugin's current data paths, which the `pre_restore` snapshot
  /// copies.
  final List<String> dataPaths;
  final String snapshotId;
}

/// The snapshot service (design D12). `DirectorySnapshotter` implements it.
abstract interface class Snapshotter {
  /// Throws `insufficient_disk` when the snapshots volume lacks the space for
  /// [request], without changing anything: an update asks before it stops the
  /// server.
  Future<void> ensureSpace(SnapshotRequest request);

  /// Takes the snapshot, prunes the instance's older ones and returns its id.
  Future<String> take(SnapshotRequest request);

  /// The instance's snapshots, newest first.
  List<SnapshotInfo> list(String instanceId);

  /// The `pre_delete` snapshots of instances that no longer exist (not in
  /// [knownInstanceIds]), newest first.
  List<SnapshotInfo> listOrphans(Set<String> knownInstanceIds);

  /// Replaces the instance's data paths with the contents of the snapshot:
  /// the source is pinned, a `pre_restore` snapshot of the current data comes
  /// first, and only then is any data path replaced. [onStep] is told
  /// `pre_restore` and `restore`; [checkCancelled] is asked before each point
  /// where the restore can still be abandoned. Pruning for the new snapshot
  /// happens after the restore ends.
  ///
  /// Throws `snapshot_not_found`.
  Future<void> restore(
    RestoreRequest request, {
    required void Function(String step) onStep,
    required void Function() checkCancelled,
  });

  /// Instances whose restore started replacing data and did not finish.
  List<String> interruptedRestores();

  /// Forgets an interrupted restore (after Acknowledge or a finished restore).
  void clearInterruptedRestore(String instanceId);

  /// Removes snapshots of instances that no longer exist once they are 30 days
  /// old, and half-written snapshots.
  Future<void> purgeExpired(Set<String> knownInstanceIds);
}
