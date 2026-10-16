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

/// Seam for the snapshot service of group 6. Without one, the `snapshot` steps
/// are skipped.
abstract interface class Snapshotter {
  /// Takes the snapshot and returns its id.
  Future<String> take(SnapshotRequest request);
}
