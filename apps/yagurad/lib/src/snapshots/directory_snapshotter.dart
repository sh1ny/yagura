import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../errors.dart';
import '../files/instance_fs.dart';
import '../platform/disk_space.dart';
import 'snapshotter.dart';

/// Snapshots as directory copies on the snapshots volume (design D12):
/// `<root>/<instance>/<id>/` holds `manifest.json` and a copy of each data
/// path under `data/<n>`. A snapshot is built in `<id>.partial` and renamed
/// when complete, so a crash never leaves a listed half-written snapshot.
class DirectorySnapshotter implements Snapshotter {
  DirectorySnapshotter({
    required this.root,
    DateTime Function()? clock,
    DiskSpaceProbe? diskSpace,
    this.keep = 3,
    this.orphanRetention = const Duration(days: 30),
    this.beforeCopyingBack,
  }) : _clock = clock ?? DateTime.now,
       _diskSpace = diskSpace ?? probeDiskSpace;

  /// `<data>/snapshots`.
  final String root;

  /// Snapshots kept per instance.
  final int keep;

  /// How long the snapshots of a deleted instance are kept.
  final Duration orphanRetention;

  /// Test seam: awaited during a restore after the current data of a path was
  /// removed and before the snapshot's copy is put back.
  final Future<void> Function()? beforeCopyingBack;

  final DateTime Function() _clock;
  final DiskSpaceProbe _diskSpace;
  final _pinned = <String>{};
  var _lastStamp = 0;

  static final _random = Random.secure();
  static const _manifestName = 'manifest.json';
  static const _markerName = 'restoring.json';
  static const _partialSuffix = '.partial';

  String _instanceRoot(String instanceId) => p.join(root, instanceId);

  // ---- space -----------------------------------------------------------------

  @override
  Future<void> ensureSpace(SnapshotRequest request) async {
    final size = _sizeOf(request);
    final required = size * 2;
    final space = await _diskSpace(root);
    if (space.freeBytes < required) {
      throw YaguraException(
        'insufficient_disk',
        'the snapshots volume ${space.volume} has ${space.freeBytes} bytes '
            'free; a snapshot of "${request.instanceName}" needs twice its '
            'data size ($required bytes)',
        details: {
          'volume': space.volume,
          'freeBytes': space.freeBytes,
          'requiredBytes': required,
        },
      );
    }
  }

  /// The bytes the data paths hold. A link in them fails with
  /// `sandbox_violation`: a snapshot copies files and directories only, and a
  /// link would be dropped from the copy and from the data a restore puts
  /// back.
  int _sizeOf(SnapshotRequest request) {
    final fs = InstanceFs(request.instanceDirectory);
    var total = 0;
    for (final path in request.dataPaths) {
      total += fs.treeSize(fs.relative(path));
    }
    return total;
  }

  // ---- taking ----------------------------------------------------------------

  @override
  Future<String> take(SnapshotRequest request) async {
    final id = await _take(request);
    _prune(request.instanceId);
    return id;
  }

  Future<String> _take(SnapshotRequest request) async {
    await ensureSpace(request);
    final now = _clock().toUtc();
    var stamp = now.millisecondsSinceEpoch;
    if (stamp <= _lastStamp) stamp = _lastStamp + 1;
    _lastStamp = stamp;
    final id =
        'snap-${stamp.toRadixString(36).padLeft(9, '0')}-'
        '${_random.nextInt(0x10000).toRadixString(16).padLeft(4, '0')}';
    final directory = _instanceRoot(request.instanceId);
    final partial = Directory(p.join(directory, '$id$_partialSuffix'))
      ..createSync(recursive: true);
    try {
      final fs = InstanceFs(request.instanceDirectory);
      final entries = <Map<String, Object?>>[];
      var size = 0;
      for (var i = 0; i < request.dataPaths.length; i++) {
        final relative = p.relative(
          request.dataPaths[i],
          from: request.instanceDirectory,
        );
        final kind = switch (fs.stat(fs.relative(request.dataPaths[i]))) {
          null => 'missing',
          final entry when entry.isDirectory => 'directory',
          _ => 'file',
        };
        if (kind != 'missing') {
          size += fs.copyOut(
            fs.relative(request.dataPaths[i]),
            p.join(partial.path, 'data', '$i'),
          );
        }
        entries.add({'path': relative, 'kind': kind, 'index': i});
      }
      File(p.join(partial.path, _manifestName)).writeAsStringSync(
        jsonEncode({
          'id': id,
          'instanceId': request.instanceId,
          'instanceName': request.instanceName,
          'reason': request.reason,
          'createdAt': now.toIso8601String(),
          'sizeBytes': size,
          'paths': entries,
        }),
      );
      partial.renameSync(p.join(directory, id));
    } on Object {
      if (partial.existsSync()) partial.deleteSync(recursive: true);
      rethrow;
    }
    return id;
  }

  void _prune(String instanceId) {
    final all = list(instanceId);
    for (final stale in all.skip(keep)) {
      if (_pinned.contains('$instanceId/${stale.id}')) continue;
      _delete(instanceId, stale.id);
    }
  }

  void _delete(String instanceId, String id) {
    final directory = Directory(p.join(_instanceRoot(instanceId), id));
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }

  // ---- listing ---------------------------------------------------------------

  SnapshotInfo? _read(Directory directory) {
    final manifest = File(p.join(directory.path, _manifestName));
    if (!manifest.existsSync()) return null;
    try {
      final json = jsonDecode(manifest.readAsStringSync());
      if (json is! Map<String, Object?>) return null;
      return SnapshotInfo(
        id: json['id'] as String,
        instanceId: json['instanceId'] as String,
        instanceName: json['instanceName'] as String,
        reason: json['reason'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        sizeBytes: json['sizeBytes'] as int,
      );
    } on Object {
      return null;
    }
  }

  @override
  List<SnapshotInfo> list(String instanceId) {
    final directory = Directory(_instanceRoot(instanceId));
    if (!directory.existsSync()) return const [];
    return _sorted([
      for (final entry in directory.listSync().whereType<Directory>())
        if (!entry.path.endsWith(_partialSuffix)) ?_read(entry),
    ]);
  }

  List<SnapshotInfo> _sorted(List<SnapshotInfo> snapshots) =>
      snapshots..sort((a, b) {
        final byTime = b.createdAt.compareTo(a.createdAt);
        return byTime != 0 ? byTime : b.id.compareTo(a.id);
      });

  Iterable<Directory> _instanceDirectories() {
    final directory = Directory(root);
    if (!directory.existsSync()) return const [];
    return directory.listSync().whereType<Directory>();
  }

  @override
  List<SnapshotInfo> listOrphans(Set<String> knownInstanceIds) => _sorted([
    for (final instance in _instanceDirectories())
      if (!knownInstanceIds.contains(p.basename(instance.path)))
        for (final info in list(p.basename(instance.path)))
          if (info.reason == 'pre_delete') info,
  ]);

  // ---- restoring -------------------------------------------------------------

  File _marker(String instanceId) =>
      File(p.join(_instanceRoot(instanceId), _markerName));

  @override
  Future<void> restore(
    RestoreRequest request, {
    required void Function(String step) onStep,
    required void Function() checkCancelled,
  }) async {
    final source = Directory(
      p.join(_instanceRoot(request.instanceId), request.snapshotId),
    );
    final info = _read(source);
    if (info == null) {
      throw YaguraException(
        'snapshot_not_found',
        'instance "${request.instanceName}" has no snapshot '
            '${request.snapshotId}',
        details: {
          'instanceId': request.instanceId,
          'snapshotId': request.snapshotId,
        },
      );
    }
    final manifest = jsonDecode(
      File(p.join(source.path, _manifestName)).readAsStringSync(),
    ) as Map<String, Object?>;
    final entries = [
      for (final entry in manifest['paths'] as List<Object?>)
        entry as Map<String, Object?>,
    ];
    final fs = InstanceFs(request.instanceDirectory);
    final targets = <String>[];
    for (final entry in entries) {
      final target = p.normalize(
        p.join(request.instanceDirectory, entry['path'] as String),
      );
      if (!p.isWithin(request.instanceDirectory, target)) {
        throw YaguraException(
          'internal_error',
          'snapshot ${request.snapshotId} names a path outside the instance '
              'directory: ${entry['path']}',
        );
      }
      // A link on the way (an intermediate directory replaced since the
      // snapshot) fails every operation on the path with `sandbox_violation`
      // before anything is deleted or copied. The last segment stays as
      // named: a link there is removed itself, never followed.
      final relative = fs.relative(target);
      final parent = p.dirname(relative);
      fs.stat(parent == '.' ? '' : parent);
      targets.add(relative);
    }

    final pin = '${request.instanceId}/${request.snapshotId}';
    _pinned.add(pin);
    try {
      checkCancelled();
      onStep('pre_restore');
      await _take(
        SnapshotRequest(
          instanceId: request.instanceId,
          instanceName: request.instanceName,
          instanceDirectory: request.instanceDirectory,
          dataPaths: request.dataPaths,
          reason: 'pre_restore',
        ),
      );
      // The last point where the restore can be abandoned: past it, data paths
      // are being replaced.
      checkCancelled();
      onStep('restore');
      _marker(request.instanceId)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'snapshotId': request.snapshotId,
            'startedAt': _clock().toUtc().toIso8601String(),
          }),
        );
      for (var i = 0; i < entries.length; i++) {
        final target = targets[i];
        fs.deleteTree(target);
        await beforeCopyingBack?.call();
        if (entries[i]['kind'] != 'missing') {
          fs.copyIn(
            p.join(source.path, 'data', '${entries[i]['index']}'),
            target,
          );
        }
      }
      _marker(request.instanceId).deleteSync();
    } finally {
      _pinned.remove(pin);
      _prune(request.instanceId);
    }
  }

  @override
  List<String> interruptedRestores() => [
    for (final instance in _instanceDirectories())
      if (File(p.join(instance.path, _markerName)).existsSync())
        p.basename(instance.path),
  ];

  @override
  void clearInterruptedRestore(String instanceId) {
    final marker = _marker(instanceId);
    if (marker.existsSync()) marker.deleteSync();
  }

  // ---- expiry ----------------------------------------------------------------

  @override
  Future<void> purgeExpired(Set<String> knownInstanceIds) async {
    final now = _clock().toUtc();
    for (final instance in _instanceDirectories().toList()) {
      final instanceId = p.basename(instance.path);
      for (final entry in instance.listSync().whereType<Directory>()) {
        if (entry.path.endsWith(_partialSuffix)) {
          entry.deleteSync(recursive: true);
        }
      }
      if (knownInstanceIds.contains(instanceId)) continue;
      for (final info in list(instanceId)) {
        if (now.difference(info.createdAt) >= orphanRetention) {
          _delete(instanceId, info.id);
        }
      }
      if (instance.existsSync() && instance.listSync().isEmpty) {
        instance.deleteSync();
      }
    }
  }
}
