import 'confined_fs.dart';

/// The per-instance use of [ConfinedFs] (design D8): every daemon file
/// operation inside an instance directory goes through one of these, rooted
/// at the instance's stored directory.
///
/// Opening the root is part of every operation, so an instance directory
/// replaced by a link or junction fails the next operation on it with
/// `sandbox_violation`.
class InstanceFs extends ConfinedFs {
  /// Confines to the instance directory [directory].
  InstanceFs(super.directory);

  /// The marker file `.yagura/deleting` is there while a delete with files is in
  /// progress (design D25).
  static const deletingMarker = '.yagura/deleting';

  /// The directory below the instance that holds the daemon's own files.
  static const yaguraDirectory = '.yagura';
}
