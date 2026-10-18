import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:yagura_js/yagura_js.dart';

import '../files/instance_fs.dart';
import 'hook_limits.dart';
import 'host_api.dart';

/// Everything a worker needs to run one hook call. Plain data, so it crosses
/// the isolate boundary.
class HookWorkerRequest {
  const HookWorkerRequest({
    required this.hookName,
    required this.source,
    required this.contextJson,
    required this.rootPath,
    required this.deadline,
    this.memoryLimitBytes = HookLimits.memoryBytes,
    this.stackBytes = HookLimits.stackBytes,
    this.resultLimitBytes = HookLimits.resultBytes,
  });

  factory HookWorkerRequest.fromMap(Map<String, Object?> map) =>
      HookWorkerRequest(
        hookName: map['hookName']! as String,
        source: map['source']! as String,
        contextJson: map['contextJson']! as String,
        rootPath: map['rootPath']! as String,
        deadline: Duration(microseconds: map['deadlineMicros']! as int),
        memoryLimitBytes: map['memoryLimitBytes']! as int,
        stackBytes: map['stackBytes']! as int,
        resultLimitBytes: map['resultLimitBytes']! as int,
      );

  final String hookName;

  /// The text of `hooks.js`.
  final String source;

  /// The hook context as JSON text.
  final String contextJson;

  final String rootPath;

  /// How long the script may run, measured from the start of the worker.
  final Duration deadline;
  final int memoryLimitBytes;
  final int stackBytes;
  final int resultLimitBytes;

  Map<String, Object?> toMap() => {
    'hookName': hookName,
    'source': source,
    'contextJson': contextJson,
    'rootPath': rootPath,
    'deadlineMicros': deadline.inMicroseconds,
    'memoryLimitBytes': memoryLimitBytes,
    'stackBytes': stackBytes,
    'resultLimitBytes': resultLimitBytes,
  };
}

/// One running hook call. Its reply is a map: `{'status': 'ok', 'missing':
/// bool, 'resultJson': String?, 'logs': List}` or `{'status': 'error',
/// 'reason': String, 'message': String, 'stack': String?, 'code': String?}`.
abstract interface class HookWorker {
  /// The worker's reply.
  Future<Map<String, Object?>> get result;

  /// Completes when the worker's isolate has exited.
  Future<void> get exited;

  /// Asks the isolate to exit as soon as it can.
  void kill();
}

/// Starts the worker for a request.
typedef HookWorkerLauncher = Future<HookWorker> Function(
  HookWorkerRequest request,
);

/// A worker running in its own isolate (design D4: a fresh isolate per call).
class IsolateHookWorker implements HookWorker {
  IsolateHookWorker._(this._isolate, this.result, this.exited);

  final Isolate _isolate;

  @override
  final Future<Map<String, Object?>> result;

  @override
  final Future<void> exited;

  static Future<HookWorker> launch(HookWorkerRequest request) async {
    final replies = ReceivePort();
    final exits = ReceivePort();
    final result = Completer<Map<String, Object?>>();
    final exited = Completer<void>();

    replies.listen((message) {
      if (!result.isCompleted) {
        result.complete((message as Map).cast<String, Object?>());
      }
      replies.close();
    });
    exits.listen((_) {
      exits.close();
      replies.close();
      if (!result.isCompleted) {
        result.complete({
          'status': 'error',
          'reason': 'internal_error',
          'message': 'the hook worker exited without a result',
        });
      }
      if (!exited.isCompleted) exited.complete();
    });

    try {
      final isolate = await Isolate.spawn<List<Object?>>(
        _workerMain,
        [replies.sendPort, request.toMap()],
        onExit: exits.sendPort,
        errorsAreFatal: true,
        debugName: 'hook-${request.hookName}',
      );
      return IsolateHookWorker._(isolate, result.future, exited.future);
    } on Object {
      replies.close();
      exits.close();
      rethrow;
    }
  }

  @override
  void kill() => _isolate.kill(priority: Isolate.immediate);
}

void _workerMain(List<Object?> message) {
  final reply = message[0]! as SendPort;
  final request = HookWorkerRequest.fromMap(
    (message[1]! as Map).cast<String, Object?>(),
  );
  Map<String, Object?> result;
  try {
    result = runHookInWorker(request);
  } on Object catch (e) {
    result = {
      'status': 'error',
      'reason': 'internal_error',
      'message': 'hook worker failed: $e',
    };
  }
  Isolate.exit(reply, result);
}

/// Runs one hook call in the current isolate and returns the worker reply.
///
/// Creates the quickjs runtime (heap and stack limits, deadline), registers
/// the `yagura.*` host API, loads `hooks.js`, calls the hook with the context
/// and frees the runtime.
Map<String, Object?> runHookInWorker(HookWorkerRequest request) {
  final js = QuickJsRuntime(
    memoryLimitBytes: request.memoryLimitBytes,
    maxStackBytes: request.stackBytes,
  );
  final logs = <Map<String, Object?>>[];
  var loaded = false;
  try {
    js.setDeadline(request.deadline);
    registerHostApi(js, InstanceFs(request.rootPath), logs);
    js.hideHostBridge();
    js.eval(hookPrelude, filename: '<yagura>');
    js.eval(request.source, filename: 'hooks.js');
    loaded = true;
    final reply =
        js.callFunction('__yagura_invoke', [
              request.hookName,
              jsonDecode(request.contextJson),
            ])!
            as Map;
    if (reply['missing'] == true) {
      return {'status': 'ok', 'missing': true, 'logs': logs};
    }
    final json = reply['json']! as String;
    if (utf8.encode(json).length > request.resultLimitBytes) {
      return _error(
        'hook_result_too_large',
        'hook ${request.hookName} returned a result over the '
            '${_describeBytes(request.resultLimitBytes)} limit',
      );
    }
    return {'status': 'ok', 'missing': false, 'resultJson': json, 'logs': logs};
  } on JsException catch (e) {
    return _fromJs(e, request.hookName, loaded: loaded);
  } finally {
    js.dispose();
  }
}

Map<String, Object?> _error(
  String reason,
  String message, {
  String? stack,
  String? code,
}) => {
  'status': 'error',
  'reason': reason,
  'message': message,
  'stack': ?stack,
  'code': ?code,
};

Map<String, Object?> _fromJs(
  JsException e,
  String hook, {
  required bool loaded,
}) {
  if (e is JsInterruptedException) {
    return _error('hook_timeout', 'hook $hook exceeded its deadline');
  }
  if (e.isOutOfMemory) {
    return _error(
      'hook_out_of_memory',
      'hook $hook exceeded the 64 MiB memory limit',
    );
  }
  if (!loaded && e.name == 'SyntaxError') {
    return _error('hook_syntax_error', e.message, stack: e.stack);
  }
  return _error('hook_error', e.message, stack: e.stack, code: e.code);
}

String _describeBytes(int bytes) => bytes % (1024 * 1024) == 0
    ? '${bytes ~/ (1024 * 1024)} MiB'
    : '$bytes bytes';
