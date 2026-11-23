import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../errors.dart';
import '../config/config_binder.dart';
import '../files/instance_fs.dart';
import 'hook_context.dart';
import 'hook_limits.dart';
import 'hook_point.dart';
import 'hook_worker.dart';

/// One hook call to run.
class HookInvocation {
  HookInvocation({
    required this.point,
    required this.source,
    required this.context,
    required this.root,
    this.deadline = HookLimits.defaultDeadline,
  }) {
    if (deadline <= Duration.zero || deadline > HookLimits.maxDeadline) {
      throw ArgumentError.value(
        deadline,
        'deadline',
        'must be above zero and at most ${HookLimits.maxDeadline.inSeconds} s',
      );
    }
  }

  final HookPoint point;

  /// The text of the plugin's `hooks.js`.
  final String source;

  final HookContext context;

  /// The instance the hook works in; file reads and edits stay inside it.
  final InstanceFs root;

  /// How long the script may run once a worker slot is available.
  final Duration deadline;
}

/// The outcome of a hook call whose result passed validation; its file edits
/// ([files]) are for the config binder to apply.
class HookRunResult {
  const HookRunResult.skipped()
    : ran = false,
      result = const HookResult(),
      logs = const [];

  const HookRunResult({required this.result, required this.logs}) : ran = true;

  /// False when `hooks.js` does not export the hook.
  final bool ran;

  final HookResult result;

  /// Entries the hook wrote with `yagura.log`: `{level, message}` maps.
  final List<Map<String, Object?>> logs;

  /// The file edits the hook returned.
  List<FileEdit> get files => result.files;

  /// Extra launch arguments (`onPreStart`), if the hook returned any.
  List<String>? get args => result.args;

  /// Extra environment variables (`onPreStart`), if the hook returned any.
  Map<String, String>? get env => result.env;
}

/// Runs hooks in isolated workers (design D4).
///
/// Each call gets a fresh isolate with its own quickjs runtime. At most
/// [maxWorkers] workers exist at once; a worker whose watchdog fired keeps
/// its slot until its isolate has exited. Time spent waiting for a slot does
/// not count against the call's deadline. When [degradedAt] timed-out workers
/// have failed to exit within [leakGrace] of their watchdog, hooks are refused
/// with `hook_runtime_degraded` until the daemon restarts.
class HookHost {
  HookHost({
    this.maxWorkers = HookLimits.workerSlots,
    this.watchdogGrace = HookLimits.watchdogGrace,
    this.leakGrace = HookLimits.leakGrace,
    this.degradedAt = HookLimits.degradedAtLeaked,
    HookWorkerLauncher? launcher,
  }) : _launch = launcher ?? IsolateHookWorker.launch;

  final int maxWorkers;
  final Duration watchdogGrace;
  final Duration leakGrace;
  final int degradedAt;
  final HookWorkerLauncher _launch;

  final _waiters = Queue<Completer<void>>();
  int _used = 0;
  int _leaked = 0;
  bool _degraded = false;

  /// Workers holding a slot, including timed-out ones not yet exited.
  int get runningWorkers => _used;

  /// Workers whose isolate had not exited [leakGrace] after their watchdog and
  /// still has not. `GetHealth` reports this count.
  int get leakedWorkers => _leaked;

  /// Whether hooks are refused until restart.
  bool get degraded => _degraded;

  /// Runs [invocation]: waits for a slot (bounded by [cancel], which fails the
  /// call with `interrupted`), runs the hook in a worker, validates its result
  /// against the hook's schema and returns it with its file edits.
  Future<HookRunResult> run(
    HookInvocation invocation, {
    Future<void>? cancel,
  }) async {
    _refuseIfDegraded();
    final contextJson = jsonEncode(invocation.context.toJson());
    invocation.context.checkSize(utf8.encode(contextJson).length);

    final reply = await _execute(
      HookWorkerRequest(
        hookName: invocation.point.exportName,
        source: invocation.source,
        contextJson: contextJson,
        rootPath: invocation.root.root,
        recorded: invocation.root.recordedPaths,
        deadline: invocation.deadline,
      ),
      cancel,
    );
    return _finish(invocation, reply);
  }

  /// Loads [source] (a plugin's `hooks.js`) in a worker without calling any
  /// hook, so a syntax error or a failing top level surfaces at plugin load.
  /// Throws the same errors as [run] (`hook_syntax_error` names the line).
  Future<void> checkLoads({
    required String source,
    required String rootPath,
    Duration deadline = HookLimits.defaultDeadline,
  }) async {
    _refuseIfDegraded();
    final reply = await _execute(
      HookWorkerRequest(
        hookName: loadCheckName,
        source: source,
        contextJson: '{}',
        rootPath: rootPath,
        deadline: deadline,
      ),
      null,
    );
    if (reply['status'] != 'ok') {
      throw YaguraException(
        reply['reason']! as String,
        reply['message']! as String,
        details: {'stack': ?reply['stack'], 'code': ?reply['code']},
      );
    }
  }

  /// The hook name [checkLoads] asks for; no plugin exports it.
  static const loadCheckName = '__yagura_load_check__';

  /// Takes a worker slot, runs [request] and returns the worker's reply (or
  /// the watchdog's error reply).
  Future<Map<String, Object?>> _execute(
    HookWorkerRequest request,
    Future<void>? cancel,
  ) async {
    await _acquireSlot(cancel);
    final HookWorker worker;
    try {
      worker = await _launch(request);
    } on Object {
      _releaseSlot();
      rethrow;
    }

    final hook = request.hookName;
    var exited = false;
    var counted = false;
    Timer? leakTimer;
    unawaited(
      worker.exited.then((_) {
        exited = true;
        leakTimer?.cancel();
        if (counted) _leaked--;
        _releaseSlot();
      }),
    );

    final watchdog = Completer<Map<String, Object?>>();
    final watchdogTimer = Timer(request.deadline + watchdogGrace, () {
      worker.kill();
      leakTimer = Timer(leakGrace, () {
        if (exited) return;
        counted = true;
        _leaked++;
        if (_leaked >= degradedAt) _enterDegraded();
      });
      watchdog.complete({
        'status': 'error',
        'reason': 'hook_timeout',
        'message': 'hook $hook exceeded its deadline',
      });
    });

    final Map<String, Object?> reply;
    try {
      reply = await Future.any([worker.result, watchdog.future]);
    } finally {
      watchdogTimer.cancel();
    }

    return reply;
  }

  HookRunResult _finish(HookInvocation invocation, Map<String, Object?> reply) {
    final hook = invocation.point.exportName;
    if (reply['status'] != 'ok') {
      throw YaguraException(
        reply['reason']! as String,
        reply['message']! as String,
        details: {
          'hook': hook,
          'stack': ?reply['stack'],
          'code': ?reply['code'],
        },
      );
    }
    final logs = [
      for (final entry in (reply['logs'] as List? ?? const []))
        (entry as Map).cast<String, Object?>(),
    ];
    if (reply['missing'] == true) return const HookRunResult.skipped();
    final Object? decoded;
    try {
      decoded = jsonDecode(reply['resultJson']! as String);
    } on FormatException catch (e) {
      throw YaguraException(
        'hook_result_invalid',
        'hook $hook returned a result that is not JSON: ${e.message}',
        details: {'hook': hook, 'path': r'$'},
      );
    }
    final result = invocation.point.parseResult(decoded);
    // The edits are applied by the config binder, in one pass with the
    // bindings; a format it cannot edit fails here, before anything runs on.
    for (final edit in result.files) {
      checkFormat(edit.path, edit.format);
    }
    return HookRunResult(result: result, logs: logs);
  }

  void _refuseIfDegraded() {
    if (_degraded) {
      throw YaguraException(
        'hook_runtime_degraded',
        'hooks are refused until the daemon restarts: $_leaked hook workers '
            'did not exit after their deadline',
        details: {'leakedWorkers': _leaked},
      );
    }
  }

  void _enterDegraded() {
    _degraded = true;
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().completeError(_degradedError());
    }
  }

  YaguraException _degradedError() => YaguraException(
    'hook_runtime_degraded',
    'hooks are refused until the daemon restarts: $_leaked hook workers '
        'did not exit after their deadline',
    details: {'leakedWorkers': _leaked},
  );

  Future<void> _acquireSlot(Future<void>? cancel) {
    if (_used < maxWorkers) {
      _used++;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    unawaited(
      cancel?.then((_) {
        if (_waiters.remove(waiter)) {
          waiter.completeError(
            YaguraException(
              'interrupted',
              'the hook call was cancelled while waiting for a worker',
            ),
          );
        }
      }),
    );
    return waiter.future;
  }

  void _releaseSlot() {
    if (_waiters.isNotEmpty) {
      // The slot passes straight to the next waiter.
      _waiters.removeFirst().complete();
    } else {
      _used--;
    }
  }
}
