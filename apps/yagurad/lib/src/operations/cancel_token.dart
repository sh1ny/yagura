import 'dart:async';

/// Thrown by a step that noticed its operation was cancelled. The runner ends
/// the operation `cancelled`.
class OperationCancelled implements Exception {
  const OperationCancelled();

  @override
  String toString() => 'OperationCancelled';
}

/// Cancellation of one operation (design D18). Steps check [isCancelled] at
/// their boundaries; interruptible waits (SteamCMD, health) listen to
/// [whenCancelled] instead.
class CancelToken {
  final _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  /// Completes when [cancel] is called.
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }

  /// Throws [OperationCancelled] when cancelled.
  void throwIfCancelled() {
    if (isCancelled) throw const OperationCancelled();
  }
}
