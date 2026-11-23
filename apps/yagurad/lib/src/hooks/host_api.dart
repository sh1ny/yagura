import 'dart:convert';
import 'dart:typed_data';

import 'package:yagura_formats/yagura_formats.dart';
import 'package:yagura_js/yagura_js.dart';

import '../errors.dart';
import '../files/confined_fs.dart';
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
  const keyed = (name) => Object.freeze(yagura.formats[name]);
  const json = Object.freeze(yagura.formats.json);
  yagura.fs = guard(yagura.fs, (name) => function () {
    throw fail('not_supported',
      'yagura.fs.' + name + ' is not supported: hooks cannot write files, ' +
      'return file edits instead');
  });
  yagura.formats = guard({
    json,
    ini: keyed('ini'),
    'dayz-cfg': keyed('dayz-cfg'),
    kv: keyed('kv'),
  }, (format) => {
    const unsupported = function () {
      throw fail('unsupported_in_this_version',
        'yagura.formats.' + format + ' is not supported in this version; only ' +
        'json, ini, dayz-cfg and kv are');
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
/// (`readText`, `list`) confined to [root], `formats.json` (`parse`,
/// `serialize`) and `formats.ini`, `formats['dayz-cfg']` and `formats.kv`
/// (`get`, `edit`). Log entries are appended to [logs].
void registerHostApi(
  QuickJsRuntime js,
  ConfinedFs fs,
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
    final entry = _confined(() => fs.stat(path));
    if (entry == null) throw HostException('ENOENT', 'no such file: $path');
    if (entry.isDirectory) {
      throw HostException('EISDIR', 'is a directory: $path');
    }
    return utf8.decode(
      _confined(() => readCapped(fs, path)),
      allowMalformed: true,
    );
  });

  js.registerHostFunction('yagura.fs.list', (args) {
    final path = _pathArgument('yagura.fs.list', args);
    final directory = _confined(() => fs.stat(path));
    if (directory == null) {
      throw HostException('ENOENT', 'no such directory: $path');
    }
    if (!directory.isDirectory) {
      throw HostException('ENOTDIR', 'not a directory: $path');
    }
    final entries = <Map<String, Object?>>[];
    // The listing is built whole before the loop runs; the cap bounds the
    // result.
    for (final entry in _confined(() => fs.list(path))) {
      if (entries.length >= HookLimits.listEntries) {
        throw HostException(
          'host_limit_exceeded',
          'yagura.fs.list: "$path" has more than 10,000 entries',
        );
      }
      // A link is listed by name only: it is never opened.
      entries.add({
        'name': entry.name,
        'size': entry.isDirectory || entry.isLink ? 0 : entry.size,
        'isDirectory': entry.isDirectory && !entry.isLink,
      });
    }
    return entries;
  });

  for (final format in const ['ini', 'dayz-cfg', 'kv']) {
    _registerKeyedFormat(js, format);
  }

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

/// Registers `yagura.formats.<format>.get(text, path)` and `.edit(text,
/// patch)` for a key/value [format]: `get` returns the value at a key path (a
/// string, or `null` when the key is missing), `edit` returns [text] with the
/// patch (key path to value, `null` removes the key) applied, keeping
/// everything else of the text. A text that does not parse fails
/// `config_parse_error`.
void _registerKeyedFormat(QuickJsRuntime js, String format) {
  final prefix = 'yagura.formats.$format';
  ConfigDocument parse(String function, String text) {
    _checkSize('$prefix.$function', utf8.encode(text).length);
    try {
      return switch (format) {
        'ini' => IniDocument.parse(text),
        'kv' => KvDocument.parse(text),
        _ => DayzCfgDocument.parse(text),
      };
    } on ConfigParseException catch (e) {
      throw HostException(
        'config_parse_error',
        '$prefix.$function: ${e.message} (line ${e.line}, column ${e.column})',
      );
    }
  }

  js.registerHostFunction('$prefix.get', (args) {
    if (args case [final String text, final String path]) {
      final value = parse('get', text).get(path);
      return value == null ? null : '$value';
    }
    throw HostException('hook_error', '$prefix.get expects (text, path)');
  });

  js.registerHostFunction('$prefix.edit', (args) {
    if (args case [final String text, final Map<Object?, Object?> patch]) {
      final document = parse('edit', text);
      try {
        document.applyPatch({
          for (final MapEntry(:key, :value) in patch.entries)
            '$key': value is List && format != 'dayz-cfg'
                ? value.join(',')
                : value,
        });
      } on ArgumentError catch (e) {
        throw HostException('hook_error', '$prefix.edit: ${e.message}');
      }
      final out = document.toSource();
      _checkSize('$prefix.edit', utf8.encode(out).length);
      return out;
    }
    throw HostException('hook_error', '$prefix.edit expects (text, patch)');
  });
}

/// Reads the file [path] of [fs] in chunks, refusing as soon as more than
/// [limit] bytes have been read, so a file that grows during the read cannot
/// pass the cap.
List<int> readCapped(
  ConfinedFs fs,
  String path, {
  int limit = HookLimits.hostCallBytes,
}) {
  final file = fs.openRead(path);
  try {
    final bytes = BytesBuilder(copy: false);
    var offset = 0;
    while (true) {
      final chunk = file.readAt(offset, 64 * 1024);
      if (chunk.isEmpty) return bytes.takeBytes();
      offset += chunk.length;
      bytes.add(chunk);
      if (bytes.length > limit) {
        throw HostException(
          'host_limit_exceeded',
          'yagura.fs.readText: "$path" is over the 16 MiB limit',
        );
      }
    }
  } finally {
    file.close();
  }
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

/// Runs [action], which touches the instance's files; the sandbox check
/// surfaces in the hook as an error with the same `code`.
T _confined<T>(T Function() action) {
  try {
    return action();
  } on YaguraException catch (e) {
    throw HostException(e.reason, e.message);
  }
}
