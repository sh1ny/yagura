import 'dart:convert';

import 'package:test/test.dart';
import 'package:yagura_formats/yagura_formats.dart';

void main() {
  group('round trip', () {
    final samples = <String, String>{
      'pretty with CRLF':
          '{\r\n  "a": 1,\r\n  "b": [1, 2,3 ],\r\n  "c": {}\r\n}\r\n',
      'tabs and odd spacing':
          '\t{ "a" :\t"x\\u00e9\\n" ,"b":\n[\n]\n, "c":-0.5e+10 }',
      'compact': '{"a":[true,false,null],"b":{"c":"d"}}',
      'scalar root': '  42  ',
      'bom': '﻿{"a": 1}',
      'unicode keys': '{"\u00fc": "ü", "k": 12345678901234567890}',
    };
    for (final entry in samples.entries) {
      test('keeps ${entry.key} byte for byte', () {
        expect(JsonDocument.parse(entry.value).toSource(), entry.value);
      });
    }

    test('toValue matches dart:convert', () {
      const text = '{"a": [1, 2.5, "x"], "b": {"c": null}}';
      expect(JsonDocument.parse(text).toValue(), jsonDecode(text));
    });

    for (final bad in [
      '',
      '{',
      '{"a": 1,}',
      '[1,]',
      '{"a" 1}',
      "{'a': 1}",
      '{"a": 01}',
      '{"a": "line\nbreak"}',
      '// c\n{}',
      '{} extra',
      r'"bad \x escape"',
    ]) {
      test('rejects ${jsonEncode(bad)}', () {
        expect(() => JsonDocument.parse(bad), throwsFormatException);
      });
    }
  });

  group('merge patch (RFC 7386)', () {
    String patched(String source, Object? patch) =>
        (JsonDocument.parse(source)..mergePatch(patch)).toSource();

    test('sets a nested value and keeps order and formatting', () {
      const source =
          '{\n  "Other": 1,\n  "GeneralData": {\n    "disableBaseDamage": false,\n'
          '    "keep": [1, 2]\n  },\n  "Tail": "t"\n}\n';
      expect(
        patched(source, {
          'GeneralData': {'disableBaseDamage': true},
        }),
        source.replaceFirst('false', 'true'),
      );
    });

    test('appends a new key using the sibling formatting', () {
      expect(
        patched('{\n  "a": 1,\n  "b": 2\n}\n', {'c': 3}),
        '{\n  "a": 1,\n  "b": 2,\n  "c": 3\n}\n',
      );
      expect(patched('{"a": 1, "b": 2}', {'c': 3}), '{"a": 1, "b": 2, "c": 3}');
    });

    test('appends a nested object pretty printed', () {
      expect(
        patched('{\n  "a": 1\n}', {
          'n': {
            'x': true,
            'y': [1],
          },
        }),
        '{\n  "a": 1,\n  "n": {\n    "x": true,\n    "y": [\n      1\n    ]\n  }\n}',
      );
    });

    test('null removes a key and a missing key is a no-op', () {
      expect(
        patched('{\n  "a": 1,\n  "b": 2,\n  "c": 3\n}', {
          'b': null,
          'zz': null,
        }),
        '{\n  "a": 1,\n  "c": 3\n}',
      );
      expect(
        patched('{\n  "a": 1,\n  "b": 2\n}', {'b': null}),
        '{\n  "a": 1\n}',
      );
    });

    test('arrays are replaced, not merged', () {
      expect(
        patched('{"a": [1, 2, 3]}', {
          'a': [9],
        }),
        '{"a": [9]}',
      );
    });

    test('an object patch over a scalar drops nulls inside it', () {
      expect(
        patched('{"a": 1}', {
          'a': {'x': null, 'y': 2},
        }),
        '{"a": {"y": 2}}',
      );
    });

    test('fills an empty object and keeps comments of whitespace', () {
      expect(
        patched('{\n  "a": {}\n}', {
          'a': {'b': 1},
        }),
        '{\n  "a": {\n    "b": 1\n  }\n}',
      );
    });

    test('a non-object patch replaces the document', () {
      expect(patched(' {"a": 1}\n', [1]), ' [1]\n');
    });

    test('result still parses and equals RFC semantics', () {
      final doc = JsonDocument.parse('{"a":"b","c":{"d":"e","f":"g"}}');
      doc.mergePatch({
        'a': 'z',
        'c': {'f': null},
      });
      expect(doc.toValue(), {
        'a': 'z',
        'c': {'d': 'e'},
      });
    });
  });
}
