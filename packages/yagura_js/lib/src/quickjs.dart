import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'quickjs_ffi.dart';

/// A host function callable from JavaScript: receives the call's arguments
/// decoded from JSON and returns a JSON-encodable value (or `null`).
///
/// Throw a [HostException] to raise a JavaScript `Error` carrying a `code`;
/// any other exception becomes an `Error` with code `internal_error`.
typedef HostFunction = Object? Function(List<Object?> args);

/// Thrown by a [HostFunction] to raise a JavaScript error with a `code`.
class HostException implements Exception {
  HostException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'HostException($code): $message';
}

/// An exception raised by script code, with the engine's view of it.
class JsException implements Exception {
  JsException({
    required this.name,
    required this.message,
    this.stack,
    this.code,
  });

  /// The error's `name` (`Error`, `TypeError`, `SyntaxError`, ...), or
  /// `Error` for a thrown non-error value.
  final String name;
  final String message;

  /// The JavaScript stack, with `file:line:column` locations.
  final String? stack;

  /// The error's `code` property when it is a string (set by host functions).
  final String? code;

  /// Whether the engine ran out of heap ([QuickJsRuntime.memoryLimitBytes]).
  bool get isOutOfMemory => message == 'out of memory';

  @override
  String toString() =>
      'JsException($name): $message${stack == null ? '' : '\n$stack'}';
}

/// The script was stopped because the deadline passed. Scripts cannot catch it.
class JsInterruptedException extends JsException {
  JsInterruptedException()
    : super(name: 'InternalError', message: 'interrupted');
}

/// Default script stack limit. Design D4 asks for 1 MiB, but Dart isolate
/// threads on Windows have a 1 MiB stack in total, so a 1 MiB script limit
/// overruns the thread (observed access violations); 512 KiB leaves headroom
/// for the native frames below the script.
const defaultMaxStackBytes = 512 * 1024;

/// One quickjs-ng runtime with one context, used from a single isolate.
///
/// The runtime enforces [memoryLimitBytes] and [maxStackBytes], and stops
/// scripts at the deadline set with [setDeadline] (measured with a monotonic
/// clock). Values cross the boundary only as JSON.
class QuickJsRuntime {
  QuickJsRuntime({
    this.memoryLimitBytes = 64 * 1024 * 1024,
    this.maxStackBytes = defaultMaxStackBytes,
  }) {
    _rt = jsNewRuntime();
    jsSetMemoryLimit(_rt, memoryLimitBytes);
    jsSetMaxStackSize(_rt, maxStackBytes);
    _interruptCallable = NativeCallable<JSInterruptHandlerNative>.isolateLocal(
      _onInterrupt,
      exceptionalReturn: 1,
    );
    jsSetInterruptHandler(_rt, _interruptCallable.nativeFunction, nullptr);
    _ctx = jsNewContext(_rt);
    _hostCallable = NativeCallable<JSCFunctionNative>.isolateLocal(_onHostCall);
    _installBridge();
  }

  final int memoryLimitBytes;
  final int maxStackBytes;

  late final Pointer<JSRuntime> _rt;
  late final Pointer<JSContext> _ctx;
  late final NativeCallable<JSInterruptHandlerNative> _interruptCallable;
  late final NativeCallable<JSCFunctionNative> _hostCallable;

  final _hostFunctions = <String, HostFunction>{};
  final _clock = Stopwatch()..start();
  Duration? _deadline;
  bool _interrupted = false;
  bool _disposed = false;

  /// Stops scripts [after] from now. Calls from here on observe the deadline.
  void setDeadline(Duration after) {
    _interrupted = false;
    _deadline = _clock.elapsed + after;
  }

  void clearDeadline() {
    _interrupted = false;
    _deadline = null;
  }

  int _onInterrupt(Pointer<JSRuntime> rt, Pointer<Void> opaque) {
    final deadline = _deadline;
    if (deadline != null && _clock.elapsed >= deadline) _interrupted = true;
    return _interrupted ? 1 : 0;
  }

  /// Evaluates [source] as a global script and returns its completion value
  /// converted through JSON (`undefined` becomes `null`).
  Object? eval(String source, {String filename = '<eval>'}) {
    _checkOpen();
    jsUpdateStackTop(_rt);
    final input = source.toNativeUtf8();
    final name = filename.toNativeUtf8();
    try {
      final result = jsEval(
        _ctx,
        input.cast(),
        input.length,
        name.cast(),
        jsEvalTypeGlobal,
      );
      return _takeJson(result);
    } finally {
      calloc.free(input);
      calloc.free(name);
    }
  }

  /// Calls the global function [name] with [args] (each passed through JSON)
  /// and returns its result converted through JSON.
  Object? callFunction(String name, [List<Object?> args = const []]) {
    _checkOpen();
    jsUpdateStackTop(_rt);
    final global = jsGetGlobalObject(_ctx);
    final fn = _getProperty(global, name);
    final argv = args.isEmpty ? nullptr : calloc<JSValue>(args.length);
    var parsed = 0;
    try {
      if (!jsIsFunction(_ctx, fn)) {
        throw JsException(
          name: 'TypeError',
          message: '$name is not a function',
        );
      }
      for (final arg in args) {
        final value = _parseJson(jsonEncode(arg));
        if (value.tag == jsTagException) throw _takeException();
        (argv + parsed).ref
          ..u = value.u
          ..tag = value.tag;
        parsed++;
      }
      final result = jsCall(_ctx, fn, _undefined(), args.length, argv);
      return _takeJson(result);
    } finally {
      for (var i = 0; i < parsed; i++) {
        jsFreeValue(_ctx, (argv + i).ref);
      }
      if (argv != nullptr) calloc.free(argv);
      jsFreeValue(_ctx, fn);
      jsFreeValue(_ctx, global);
    }
  }

  /// Makes [function] callable from scripts as the global `path`, where
  /// `path` may be dotted (`yagura.fs.readText`); missing namespace objects
  /// are created.
  void registerHostFunction(String path, HostFunction function) {
    _checkOpen();
    _hostFunctions[path] = function;
    final parts = path.split('.');
    eval('''
(function (host, path, parts) {
  let target = globalThis;
  for (const part of parts.slice(0, -1)) {
    if (target[part] === undefined) target[part] = {};
    target = target[part];
  }
  target[parts[parts.length - 1]] = function () {
    const reply = JSON.parse(host(path, JSON.stringify(Array.prototype.slice.call(arguments))));
    if (reply.e) {
      const error = new Error(reply.e.message);
      error.code = reply.e.code;
      throw error;
    }
    return reply.v;
  };
})(globalThis.__yagura_host, ${jsonEncode(path)}, ${jsonEncode(parts)});
''', filename: '<yagura-bridge>');
  }

  /// Removes the raw bridge function behind registered host functions from
  /// the global object. Host functions registered before keep working.
  void hideHostBridge() {
    eval('delete globalThis.__yagura_host;', filename: '<yagura-bridge>');
  }

  /// Frees the context and runtime. Safe to call more than once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    jsFreeContext(_ctx);
    jsFreeRuntime(_rt);
    _interruptCallable.close();
    _hostCallable.close();
  }

  void _checkOpen() {
    if (_disposed) throw StateError('QuickJsRuntime is disposed');
  }

  // -- bridge ---------------------------------------------------------------

  void _installBridge() {
    final name = '__yagura_host'.toNativeUtf8();
    final global = jsGetGlobalObject(_ctx);
    try {
      final fn = jsNewCFunction2(
        _ctx,
        _hostCallable.nativeFunction,
        name.cast(),
        2,
        jsCFuncGeneric,
        0,
      );
      jsSetPropertyStr(_ctx, global, name.cast(), fn);
    } finally {
      jsFreeValue(_ctx, global);
      calloc.free(name);
    }
  }

  /// Entry point from QuickJS for every registered host function. Never
  /// throws into native code: failures travel back as `{"e": ...}`.
  JSValue _onHostCall(
    Pointer<JSContext> ctx,
    JSValue thisValue,
    int argc,
    Pointer<JSValue> argv,
  ) {
    String reply;
    try {
      final path = _toDartString(argv[0]);
      final args = jsonDecode(_toDartString(argv[1])) as List<Object?>;
      final function = _hostFunctions[path];
      if (function == null) {
        throw HostException('internal_error', 'unknown host function $path');
      }
      reply = jsonEncode({'v': function(args)});
    } on HostException catch (e) {
      reply = jsonEncode({
        'e': {'code': e.code, 'message': e.message},
      });
    } on Object catch (e) {
      reply = jsonEncode({
        'e': {'code': 'internal_error', 'message': '$e'},
      });
    }
    return _newString(reply);
  }

  // -- value helpers --------------------------------------------------------

  JSValue _undefined() => Struct.create<JSValue>()
    ..u = 0
    ..tag = jsTagUndefined;

  JSValue _newString(String value) {
    final bytes = utf8.encode(value);
    final buffer = calloc<Uint8>(bytes.length + 1);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      return jsNewStringLen(_ctx, buffer.cast(), bytes.length);
    } finally {
      calloc.free(buffer);
    }
  }

  JSValue _parseJson(String json) {
    final bytes = utf8.encode(json);
    final buffer = calloc<Uint8>(bytes.length + 1);
    final name = '<json>'.toNativeUtf8();
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      return jsParseJSON(_ctx, buffer.cast(), bytes.length, name.cast());
    } finally {
      calloc.free(buffer);
      calloc.free(name);
    }
  }

  JSValue _getProperty(JSValue object, String name) {
    final key = name.toNativeUtf8();
    try {
      return jsGetPropertyStr(_ctx, object, key.cast());
    } finally {
      calloc.free(key);
    }
  }

  bool _isString(JSValue v) => v.tag == jsTagString || v.tag == jsTagStringRope;

  /// Copies a JS string (or the string form of any value) into Dart.
  String _toDartString(JSValue value) {
    final length = calloc<Size>();
    try {
      final chars = jsToCStringLen2(_ctx, length, value, false);
      if (chars == nullptr) return '';
      try {
        return utf8.decode(
          chars.cast<Uint8>().asTypedList(length.value),
          allowMalformed: true,
        );
      } finally {
        jsFreeCString(_ctx, chars);
      }
    } finally {
      calloc.free(length);
    }
  }

  /// Frees [value] and returns it converted through JSON, or throws the
  /// pending exception when [value] is `JS_EXCEPTION`.
  Object? _takeJson(JSValue value) {
    if (value.tag == jsTagException) throw _takeException();
    if (value.tag == jsTagUndefined) return null;
    final undefined = _undefined();
    final json = jsJSONStringify(_ctx, value, undefined, undefined);
    jsFreeValue(_ctx, value);
    if (json.tag == jsTagException) throw _takeException();
    if (json.tag == jsTagUndefined) return null; // functions, symbols
    try {
      return jsonDecode(_toDartString(json));
    } finally {
      jsFreeValue(_ctx, json);
    }
  }

  /// Clears the pending exception and describes it.
  JsException _takeException() {
    final exception = jsGetException(_ctx);
    try {
      if (_interrupted) return JsInterruptedException();
      if (exception.tag != jsTagObject) {
        return JsException(name: 'Error', message: _toDartString(exception));
      }
      String? text(String property) {
        final value = _getProperty(exception, property);
        try {
          return _isString(value) ? _toDartString(value) : null;
        } finally {
          jsFreeValue(_ctx, value);
        }
      }

      return JsException(
        name: text('name') ?? 'Error',
        message: text('message') ?? '',
        stack: text('stack'),
        code: text('code'),
      );
    } finally {
      jsFreeValue(_ctx, exception);
    }
  }
}
