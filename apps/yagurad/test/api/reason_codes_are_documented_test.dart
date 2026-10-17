import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Where the reason codes of the daemon come from: its own sources, and the
/// plugin package whose problems the daemon reports.
const _sourceRoots = ['lib', '../../packages/yagura_plugin/lib'];

/// The Steam output patterns carry the reason of the failure they recognise.
const _steamPatterns = 'lib/src/steam/patterns.yaml';

final _code = '([a-z][a-z0-9_]*)';

/// How a reason code appears in the sources. The first group is the code.
final _emitters = <String, RegExp>{
  'YaguraException(code': RegExp("YaguraException\\(\\s*'$_code'"),
  'host/hook error reply': RegExp("\\b_error\\(\\s*'$_code'"),
  'reply map': RegExp("'reason':\\s*'$_code'"),
  'reason constant': RegExp("\\b\\w*(?:Reason|Code)\\s*=\\s*'$_code'"),
  'operation result': RegExp("\\bresult\\(\\s*reason:\\s*'$_code"),
  'operation warning': RegExp("\\.warn\\(\\s*'$_code'"),
  'problem code': RegExp("\\bcode:\\s*'$_code'"),
  'manifest problem': RegExp("\\breport\\.add\\(\\s*'$_code'"),
  'API error': RegExp("\\bgrpcErrorFor\\(\\s*'$_code'"),
};

/// Every code the sources can emit, with where it was found.
Map<String, Set<String>> emittedCodes() {
  final found = <String, Set<String>>{};
  void add(String code, String where) =>
      found.putIfAbsent(code, () => {}).add(where);

  for (final root in _sourceRoots) {
    for (final file in Directory(root).listSync(recursive: true)) {
      if (file is! File || p.extension(file.path) != '.dart') continue;
      // The generated Steam pattern table repeats patterns.yaml.
      if (p.basename(file.path) == 'patterns.g.dart') continue;
      final text = file.readAsStringSync();
      for (final MapEntry(:key, :value) in _emitters.entries) {
        for (final match in value.allMatches(text)) {
          add(match[1]!, '${p.relative(file.path)} ($key)');
        }
      }
    }
  }
  for (final match in RegExp(
    '^\\s*reason:\\s*$_code\\s*\$',
    multiLine: true,
  ).allMatches(File(_steamPatterns).readAsStringSync())) {
    add(match[1]!, '$_steamPatterns (pattern reason)');
  }
  return found;
}

/// The codes `docs/protocol.md` lists in its Errors section.
Set<String> documentedCodes() {
  final text = File('../../docs/protocol.md').readAsStringSync();
  final start = text.indexOf('\n## Errors');
  final end = text.indexOf('\n## ', start + 1);
  expect(
    start,
    isNonNegative,
    reason: 'docs/protocol.md has an Errors section',
  );
  final section = text.substring(start, end);
  return {
    for (final match in RegExp('`$_code`').allMatches(section)) match[1]!,
  };
}

void main() {
  test('every_emitted_reason_code_is_documented', () {
    final emitted = emittedCodes();
    final documented = documentedCodes();

    expect(
      emitted.length,
      greaterThan(40),
      reason: 'the scan finds the codes (a broken scan would find none)',
    );
    final missing = {
      for (final MapEntry(:key, :value) in emitted.entries)
        if (!documented.contains(key)) key: value,
    };
    expect(
      missing,
      isEmpty,
      reason:
          'add these reason codes to the Errors table of docs/protocol.md '
          '(code: where it is emitted)',
    );
  });
}
