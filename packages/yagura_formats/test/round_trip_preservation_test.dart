import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yagura_formats/yagura_formats.dart';

/// The formats a corpus file is valid in, by file name prefix.
List<String> _formatsOf(String name) {
  if (name.startsWith('serverDZ')) return ['dayz-cfg'];
  if (name.startsWith('cfggameplay')) return ['json'];
  if (name.startsWith('BEServer_x64')) return ['kv'];
  if (name.startsWith('generic')) return ['ini', 'kv'];
  throw StateError('Corpus file $name has no format mapping');
}

String _roundTrip(String format, String source) => switch (format) {
  'json' => JsonDocument.parse(source).toSource(),
  'ini' => IniDocument.parse(source).toSource(),
  'dayz-cfg' => DayzCfgDocument.parse(source).toSource(),
  'kv' => KvDocument.parse(source).toSource(),
  _ => throw ArgumentError(format),
};

/// Decodes [bytes] keeping a leading byte order mark as U+FEFF.
String _decode(List<int> bytes) {
  final bom =
      bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;
  final text = utf8.decode(bom ? bytes.sublist(3) : bytes);
  return bom ? '﻿$text' : text;
}

List<int> _encode(String text) => text.startsWith('﻿')
    ? [0xEF, 0xBB, 0xBF, ...utf8.encode(text.substring(1))]
    : utf8.encode(text);

String _corpus(String name) =>
    _decode(File('test/corpus/$name').readAsBytesSync());

/// The indexes of the lines that differ, splitting on `\n`.
List<int> _changedLines(String before, String after) {
  final a = before.split('\n');
  final b = after.split('\n');
  expect(b.length, a.length, reason: 'line count changed');
  return [
    for (var i = 0; i < a.length; i++)
      if (a[i] != b[i]) i,
  ];
}

void main() {
  group('corpus', () {
    final files =
        Directory('test/corpus')
            .listSync()
            .whereType<File>()
            .where(
              (f) =>
                  !f.path.endsWith('README.md') &&
                  !f.path.endsWith('.gitattributes'),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    test('has files to check', () {
      expect(files.length, greaterThanOrEqualTo(10));
    });

    test('corpus_round_trips_byte_for_byte', () {
      for (final file in files) {
        final name = file.uri.pathSegments.last;
        final bytes = file.readAsBytesSync();
        final source = _decode(bytes);
        for (final format in _formatsOf(name)) {
          expect(
            _encode(_roundTrip(format, source)),
            bytes,
            reason: '$name as $format',
          );
        }
      }
    });
  });

  group('round trip', () {
    test('unchanged_file_stays_identical', () {
      final dz = _corpus('serverDZ.cfg');
      final doc = DayzCfgDocument.parse(dz)
        ..set('maxPlayers', 60)
        ..set('hostname', 'EXAMPLE NAME')
        ..set('Missions.DayZ.template', 'dayzOffline.chernarusplus');
      expect(doc.toSource(), dz);

      const withArray = 'motd[] = {"a","b"};  // keep\n';
      final array = DayzCfgDocument.parse(withArray)..set('motd', ['a', 'b']);
      expect(array.toSource(), withArray);

      final ini = _corpus('generic.crlf.ini');
      final iniDoc = IniDocument.parse(ini)
        ..set('port', 2302)
        ..set('Network.max_clients', 32)
        ..set('Network.motd', 'Welcome, survivors')
        ..set('Gameplay.Rules.friendly_fire', false);
      expect(iniDoc.toSource(), ini);

      final kv = _corpus('BEServer_x64.bom.cfg');
      final kvDoc = KvDocument.parse(kv)
        ..set('RConPort', 2307)
        ..set('MaxPing', 350);
      expect(kvDoc.toSource(), kv);

      final json = _corpus('cfggameplay.trailing-ws.json');
      final jsonDoc = JsonDocument.parse(json)..mergePatch({'version': 123});
      expect(jsonDoc.toSource(), json);
    });

    test('comments_and_unknown_keys_survive', () {
      const original =
          '// Admin: keep maxPlayers at or below the slot count.\r\n'
          'hostname = "My Server";   // shown in the browser\r\n'
          'maxPlayers = 60;          // slots\r\n'
          '\r\n'
          'myCustomKey = 1;\r\n'
          '/* block\r\n   comment */\r\n'
          'class Missions\r\n{\r\n\tclass DayZ\r\n\t{\r\n'
          '\t\ttemplate = "dayzOffline.chernarusplus";\r\n\t};\r\n};\r\n';
      final doc = DayzCfgDocument.parse(original)..set('maxPlayers', 40);
      expect(_changedLines(original, doc.toSource()), [2]);
      expect(
        doc.toSource().split('\n')[2],
        'maxPlayers = 40;          // slots\r',
      );
      expect(doc.get('myCustomKey'), 1);

      const ini =
          '; admin note\n[Server]\nname = x # not a comment\n'
          'custom = keep\n\n# tail\nport = 1\n';
      final iniDoc = IniDocument.parse(ini)..set('Server.port', 2);
      expect(_changedLines(ini, iniDoc.toSource()), [6]);
      expect(iniDoc.toSource().split('\n')[6], 'port = 2');

      const kv = '// note\nMaxPing 350\nCustom=1\nRConPort 2307\n';
      final kvDoc = KvDocument.parse(kv)..set('MaxPing', 200);
      expect(_changedLines(kv, kvDoc.toSource()), [1]);
      expect(kvDoc.toSource().split('\n')[1], 'MaxPing 200');
    });

    test('unparseable_file', () {
      void expectParseError(void Function() parse, int line, int column) {
        try {
          parse();
          fail('expected a ConfigParseException');
        } on ConfigParseException catch (e) {
          expect(e.code, 'config_parse_error');
          expect(e, isA<FormatException>());
          expect(e.line, line);
          expect(e.column, column);
          expect(e.message, isNotEmpty);
        }
      }

      final json = _corpus('cfggameplay.json')
          .replaceFirst('"version": 123,', '"version": 123,,');
      expectParseError(() => JsonDocument.parse(json), 2, 17);

      expectParseError(() => IniDocument.parse('[Network\nport=1\n'), 1, 9);
      expectParseError(() => IniDocument.parse('a=1\nbroken line\n'), 2, 1);

      expectParseError(
        () => DayzCfgDocument.parse('hostname = "x"\nmaxPlayers = 60;\n'),
        2,
        1,
      );
      expectParseError(
        () => DayzCfgDocument.parse('class A\n{\n  a = 1;\n'),
        4,
        1,
      );
      expectParseError(() => DayzCfgDocument.parse('a = "open;\n'), 1, 5);

      expectParseError(() => KvDocument.parse('ok 1\r\n=oops\r\n'), 2, 1);
    });
  });
}
