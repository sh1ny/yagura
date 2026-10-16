import 'dart:convert';
import 'dart:io';

import 'package:yagura_formats/yagura_formats.dart';
import 'package:yagura_js/yagura_js.dart';

import '../errors.dart';
import '../files/instance_root.dart';
import 'hook_limits.dart';

/// JavaScript run in every hook runtime after the host functions are
/// registered and before `hooks.js`: it locks down `yagura`, answers calls to
/// functions the API does not have, and defines how hooks are found.
///
/// A hook is a function exported as `exports.<name>` or
/// `module.exports.<name>`, or declared at the top level as `function <name>`.
const hookPrelude = r'''
(function () {
  const fail = (code, message) => {
    const error = new Error(message);
    error.code = code;
    return error;
  };
  const guard = (target, onMissing) => new Proxy(Object.freeze(target), {
    get(object, property) {
      if (typeof property !== 'string' || property in object) return object[property];
      return onMissing(property);
    },
  });
  const json = Object.freeze(yagura.formats.json);
  yagura.fs = guard(yagura.fs, (name) => function () {
    throw fail('not_supported',
      'yagura.fs.' + name + ' is not supported: hooks cannot write files, ' +
      'return file edits instead');
  });
  yagura.formats = guard({ json }, (format) => {
    const unsupported = function () {
      throw fail('unsupported_in_this_version',
        'yagura.formats.' + format + ' is not supported in this version; only json is');
    };
    return { parse: unsupported, serialize: unsupported };
  });
  Object.freeze(yagura);
  globalThis.module = { exports: {} };
  globalThis.exports = globalThis.module.exports;
  globalThis.__yagura_invoke = function (name, context) {
    const sources = [globalThis.exports, globalThis.module && globalThis.module.exports, globalThis];
    let hook;
    for (const source of sources) {
      if (source && typeof source[name] === 'function') { hook = source[name]; break; }
    }
    if (hook === undefined) return { missing: true };
    const result = hook.call(undefined, context);
    if (result && typeof result.then === 'function') {
      throw new TypeError('hook ' + name + ' returned a promise; hooks must be synchronous');
    }
    const text = JSON.stringify(result === undefined ? null : result);
    return { missing: false, json: text === undefined ? 'null' : text };
  };
})();
''';

/// Registers the pure `yagura.*` host API on [js]: `log`, read-only `fs`
/// (`readText`, `list`) confined to [root], and `formats.json`
/// (`parse`, `serialize`). Log entries are appended to [logs].
void registerHostApi(
  QuickJsRuntime js,
  InstanceRoot root,
  List<Map<String, Object?>> logs,
) {
  js.registerHostFunction('yagura.log', (args) {
    final (level, message) = switch (args) {
      [final String message] => ('info', message),
      [final String level, final Object? message] => (level, '$message'),
      _ => throw HostException(
        'hook_error',
        'yagura.log expects (message) or (level, message)',
      ),
    };
    if (!const {'debug', 'info', 'warn', 'error'}.contains(level)) {
      throw HostException('hook_error', 'unknown log level "$level"');
    }
    if (logs.length < HookLimits.logEntries) {
      logs.add({
        'level': level,
        'message': message.length > HookLimits.logEntryChars
            ? message.substring(0, HookLimits.logEntryChars)
            : message,
      });
    }
    return null;
  });

  js.registerHostFunction('yagura.fs.readText', (args) {
    final path = _pathArgument('yagura.fs.readText', args);
    final resolved = _resolve(root, path);
    switch (FileSystemEntity.typeSync(resolved)) {
      case FileSystemEntityType.notFound:
        throw HostException('ENOENT', 'no such file: $path');
      case FileSystemEntityType.directory:
        throw HostException('EISDIR', 'is a directory: $path');
      default:
    }
    final file = File(resolved);
    final length = file.lengthSync();
    if (length > HookLimits.hostCallBytes) {
      throw HostException(
        'host_limit_exceeded',
        'yagura.fs.readText: "$path" is $length bytes, over the 16 MiB limit',
      );
    }
    return utf8.decode(file.readAsBytesSync(), allowMalformed: true);
  });

  js.registerHostFunction('yagura.fs.list', (args) {
    final path = _pathArgument('yagura.fs.list', args);
    final resolved = _resolve(root, path);
    switch (FileSystemEntity.typeSync(resolved)) {
      case FileSystemEntityType.notFound:
        throw HostException('ENOENT', 'no such directory: $path');
      case FileSystemEntityType.directory:
        break;
      default:
        throw HostException('ENOTDIR', 'not a directory: $path');
    }
    final entries = <Map<String, Object?>>[];
    for (final entity in Directory(resolved).listSync(followLinks: false)) {
      if (entries.length >= HookLimits.listEntries) {
        throw HostException(
          'host_limit_exceeded',
          'yagura.fs.list: "$path" has more than 10,000 entries',
        );
      }
      final stat = entity.statSync();
      final isDirectory = stat.type == FileSystemEntityType.directory;
      entries.add({
        'name': entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
        'size': isDirectory ? 0 : stat.size,
        'isDirectory': isDirectory,
      });
    }
    return entries;
  });

  js.registerHostFunction('yagura.formats.json.parse', (args) {
    if (args case [final String text]) {
      _checkSize('yagura.formats.json.parse', utf8.encode(text).length);
      try {
        return JsonDocument.parse(text).toValue();
      } on FormatException catch (e) {
        throw HostException('invalid_json', e.message);
      }
    }
    throw HostException(
      'hook_error',
      'yagura.formats.json.parse expects a string',
    );
  });

  js.registerHostFunction('yagura.formats.json.serialize', (args) {
    final (value, indent) = switch (args) {
      [final Object? value] => (value, null),
      [final Object? value, final int indent]
          when indent >= 0 && indent <= 10 =>
        (value, indent),
      _ => throw HostException(
        'hook_error',
        'yagura.formats.json.serialize expects (value) or (value, indent 0-10)',
      ),
    };
    final text = indent == null || indent == 0
        ? jsonEncode(value)
        : JsonEncoder.withIndent(' ' * indent).convert(value);
    _checkSize('yagura.formats.json.serialize', utf8.encode(text).length);
    return text;
  });
}

String _pathArgument(String function, List<Object?> args) {
  if (args case [final String path] when path.isNotEmpty) return path;
  throw HostException('hook_error', '$function expects a path string');
}

void _checkSize(String function, int bytes) {
  if (bytes > HookLimits.hostCallBytes) {
    throw HostException(
      'host_limit_exceeded',
      '$function: $bytes bytes is over the 16 MiB limit',
    );
  }
}

/// Resolves [path] inside [root]; the sandbox check surfaces in the hook as an
/// error with the same `code`.
String _resolve(InstanceRoot root, String path) {
  try {
    return root.resolve(path);
  } on YaguraException catch (e) {
    throw HostException(e.reason, e.message);
  }
}
