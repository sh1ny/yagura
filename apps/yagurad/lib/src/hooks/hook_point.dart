import '../errors.dart';
import '../files/file_edit_writer.dart';

/// The lifecycle points at which a plugin's `hooks.js` may export a function.
enum HookPoint {
  /// After the daemon installed the instance's game files.
  onPostInstall(allowsLaunchChanges: false),

  /// After the daemon updated the instance's game files.
  onPostUpdate(allowsLaunchChanges: false),

  /// Before the server process starts; may add arguments and environment.
  onPreStart(allowsLaunchChanges: true),

  /// After the server process stopped.
  onPostStop(allowsLaunchChanges: false);

  const HookPoint({required this.allowsLaunchChanges});

  /// Whether the result may carry `args` and `env` (only `onPreStart`).
  final bool allowsLaunchChanges;

  /// The name `hooks.js` exports and error messages use.
  String get exportName => name;

  /// Result keys this hook accepts; any other key is rejected.
  Set<String> get resultKeys => {
    'files',
    if (allowsLaunchChanges) ...['args', 'env'],
  };

  /// Validates [json] (the decoded return value of the hook) against this
  /// hook's result schema. `null` (a hook returning nothing) is an empty
  /// result. Throws `hook_result_invalid` naming the hook and the path.
  HookResult parseResult(Object? json) {
    Never invalid(String path, String problem) => throw YaguraException(
      'hook_result_invalid',
      'hook $exportName returned an invalid result at $path: $problem',
      details: {'hook': exportName, 'path': path},
    );

    if (json == null) return const HookResult();
    if (json is! Map) invalid(r'$', 'expected an object');

    for (final key in json.keys) {
      if (!resultKeys.contains(key)) invalid('$key', 'unknown key');
    }

    List<String>? args;
    if (json['args'] case final Object? value when json.containsKey('args')) {
      if (value is! List) invalid('args', 'expected an array of strings');
      args = [
        for (var i = 0; i < value.length; i++)
          switch (value[i]) {
            final String s => s,
            _ => invalid('args[$i]', 'expected a string'),
          },
      ];
    }

    Map<String, String>? env;
    if (json['env'] case final Object? value when json.containsKey('env')) {
      if (value is! Map) invalid('env', 'expected an object of strings');
      env = {
        for (final entry in value.entries)
          entry.key as String: switch (entry.value) {
            final String s => s,
            _ => invalid('env.${entry.key}', 'expected a string'),
          },
      };
    }

    final files = <FileEdit>[];
    if (json['files'] case final Object? value when json.containsKey('files')) {
      if (value is! List) invalid('files', 'expected an array of file edits');
      for (var i = 0; i < value.length; i++) {
        final edit = value[i];
        final at = 'files[$i]';
        if (edit is! Map) invalid(at, 'expected an object');
        for (final key in edit.keys) {
          if (!const {'path', 'format', 'patch'}.contains(key)) {
            invalid('$at.$key', 'unknown key');
          }
        }
        final path = edit['path'];
        if (path is! String || path.isEmpty) {
          invalid('$at.path', 'expected a non-empty string');
        }
        final format = edit['format'];
        if (format is! String || format.isEmpty) {
          invalid('$at.format', 'expected a non-empty string');
        }
        final patch = edit['patch'];
        if (patch is! Map) invalid('$at.patch', 'expected an object');
        files.add(FileEdit(path: path, format: format, patch: patch));
      }
    }
    return HookResult(args: args, env: env, files: files);
  }
}

/// A validated hook result.
class HookResult {
  const HookResult({this.args, this.env, this.files = const []});

  /// Extra launch arguments (`onPreStart`), appended after the manifest's.
  final List<String>? args;

  /// Extra environment variables (`onPreStart`).
  final Map<String, String>? env;

  /// File edits the daemon applies after validation.
  final List<FileEdit> files;

  /// The result in its JSON form; absent keys stay absent.
  Map<String, Object?> toJson() => {
    'args': ?args,
    'env': ?env,
    if (files.isNotEmpty)
      'files': [
        for (final edit in files)
          {'path': edit.path, 'format': edit.format, 'patch': edit.patch},
      ],
  };
}
