import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';

import 'support.dart';

const _server = '''
logs:
  - name: server
    path: "logs/server.log"
    encoding: utf-8
    rotation: fixed
''';

PluginResult _load(String logs) =>
    loadPlugin(writePlugin(valheimWith(_server, logs)));

void main() {
  test('a file source with a glob and newest rotation loads', () {
    final result = _load('''
logs:
  - name: server
    path: "{{instance}}/profiles/*.RPT"
    encoding: latin-1
    rotation: newest
''');
    expect(result.reasons, isEmpty);
    final source = result.manifest!.logs.single;
    expect(source.path, '{{instance}}/profiles/*.RPT');
    expect(source.isStdout, isFalse);
    expect(source.encoding, 'latin-1');
    expect(source.rotation, 'newest');
  });

  test('a stdout capture loads and has no path', () {
    final result = _load('''
logs:
  - name: server
    stdout: true
    encoding: utf-16le
''');
    expect(result.reasons, isEmpty);
    final source = result.manifest!.logs.single;
    expect(source.isStdout, isTrue);
    expect(source.path, isNull);
    expect(source.encoding, 'utf-16le');
  });

  test('a stdout capture and a file source can be declared together', () {
    final result = _load('''
logs:
  - name: server
    path: "logs/server.log"
  - name: console
    stdout: true
  - name: server2
    path: "b.log"
''');
    expect(result.reasons, isEmpty);
    expect(result.manifest!.logs.map((l) => l.isStdout), [false, true, false]);
  });

  for (final (label, logs) in [
    ('latin1', '  - name: server\n    path: "a.log"\n    encoding: latin1\n'),
    (
      'timestamped',
      '  - name: server\n    path: "a.log"\n    rotation: timestamped\n',
    ),
    (
      'path and stdout',
      '  - name: server\n    path: "a.log"\n    stdout: true\n',
    ),
    ('neither path nor stdout', '  - name: server\n    encoding: utf-8\n'),
    (
      'stdout with a rotation',
      '  - name: server\n    stdout: true\n    rotation: fixed\n',
    ),
  ]) {
    test('$label is rejected', () {
      expect(_load('logs:\n$logs').status, PluginStatus.rejected);
    });
  }
}
