import 'dart:async';
import 'dart:collection';

import 'cancel_token.dart';

/// A counting semaphore with FIFO waiters that can report their position and
/// stop waiting when cancelled. Used for the SteamCMD installation locks
/// (capacity 1) and the host heavy slots (design D3).
class Semaphore {
  Semaphore(this.capacity);

  final int capacity;
  var _held = 0;
  final _waiters = Queue<_Waiter>();

  int get held => _held;
  int get waiting => _waiters.length;

  /// Takes a permit and returns the function that gives it back.
  ///
  /// While no permit is free, [onPosition] is called with the 1-based
  /// position in line, again whenever it changes. When [cancel] fires first,
  /// the wait ends with [OperationCancelled].
  Future<void Function()> acquire({
    CancelToken? cancel,
    void Function(int position)? onPosition,
  }) {
    cancel?.throwIfCancelled();
    if (_held < capacity && _waiters.isEmpty) {
      _held++;
      return Future.value(_releaseOnce());
    }
    final waiter = _Waiter(onPosition);
    _waiters.add(waiter);
    waiter.onPosition?.call(_waiters.length);
    if (cancel != null) {
      unawaited(
        cancel.whenCancelled.then((_) {
          if (_waiters.remove(waiter)) {
            waiter.completer.completeError(const OperationCancelled());
            _announcePositions();
          }
        }),
      );
    }
    return waiter.completer.future;
  }

  void Function() _releaseOnce() {
    var released = false;
    return () {
      if (released) return;
      released = true;
      if (_waiters.isNotEmpty) {
        // The permit passes straight to the next waiter.
        _waiters.removeFirst().completer.complete(_releaseOnce());
        _announcePositions();
      } else {
        _held--;
      }
    };
  }

  void _announcePositions() {
    var position = 1;
    for (final waiter in _waiters) {
      waiter.onPosition?.call(position++);
    }
  }
}

class _Waiter {
  _Waiter(this.onPosition);

  final void Function(int position)? onPosition;
  final completer = Completer<void Function()>();
}
