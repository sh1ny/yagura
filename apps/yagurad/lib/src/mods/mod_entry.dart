/// One mod of an instance: a row of `instance_mods` (design D7).
///
/// The list is ordered. A mod taken out of the list while its entry is still
/// in the stage directory stays as a `removed` row after the listed ones, so
/// the next apply can find and remove the entry it made.
class ModEntry {
  ModEntry({
    required this.source,
    required this.itemId,
    required this.role,
    this.stagedName = '',
    this.stageKind = '',
    this.desiredVersion = '',
    this.stagedVersion = '',
    this.status = pending,
    this.lastError = '',
    List<String>? warnings,
    this.remoteUpdated = 0,
    this.updateAvailable = false,
  }) : warnings = warnings ?? [];

  static const pending = 'pending';
  static const downloading = 'downloading';
  static const staged = 'staged';
  static const failed = 'failed';
  static const unavailable = 'unavailable';
  static const removed = 'removed';

  final String source;
  final String itemId;
  String role;

  /// Fixed once, when the title is known or the metadata request failed.
  String stagedName;

  /// `link`, `copy` or empty (nothing made).
  String stageKind;
  String desiredVersion;
  String stagedVersion;
  String status;
  String lastError;
  List<String> warnings;

  /// Unix seconds of the newest version the last update check saw; 0 when none.
  int remoteUpdated;
  bool updateAvailable;

  /// The workshop title and size, known in memory only: the row has no column
  /// for them, so they are read again by the next check or acquire.
  String title = '';
  int sizeBytes = 0;

  bool get isRemoved => status == removed;

  /// `source|item`, the identity inside one instance.
  String get key => '$source|$itemId';

  ModEntry copy() =>
      ModEntry(
          source: source,
          itemId: itemId,
          role: role,
          stagedName: stagedName,
          stageKind: stageKind,
          desiredVersion: desiredVersion,
          stagedVersion: stagedVersion,
          status: status,
          lastError: lastError,
          warnings: [...warnings],
          remoteUpdated: remoteUpdated,
          updateAvailable: updateAvailable,
        )
        ..title = title
        ..sizeBytes = sizeBytes;
}
