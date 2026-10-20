import 'dart:io';

import 'package:test/test.dart';
import 'package:yagura_formats/yagura_formats.dart';

void main() {
  group('dayz-cfg', () {
    test('array_value_in_dayz_cfg', () {
      final doc = DayzCfgDocument.parse('hostname = "x";\n')
        ..set('motd', ['Welcome', 'Have fun']);
      expect(
        doc.toSource(),
        'hostname = "x";\nmotd[] = {"Welcome", "Have fun"};\n',
      );
      expect(doc.get('motd'), ['Welcome', 'Have fun']);
    });

    test('replaces an existing array in place', () {
      final doc = DayzCfgDocument.parse('  motd[]={"old"};  // c\nnext = 1;\n')
        ..set('motd', ['Welcome', 'Have fun']);
      expect(
        doc.toSource(),
        '  motd[]={"Welcome", "Have fun"};  // c\nnext = 1;\n',
      );
    });

    test('reads typed values and nested classes', () {
      final doc = DayzCfgDocument.parse(
        'a = 1;\nb = 2.5;\nc = "s ""q""";\nd = true;\n'
        'class X { class Y { z = 7; }; };\n',
      );
      expect(doc.get('a'), 1);
      expect(doc.get('b'), 2.5);
      expect(doc.get('c'), 's "q"');
      expect(doc.get('d'), true);
      expect(doc.get('X.Y.z'), 7);
      expect(doc.get('X.nope'), isNull);
    });

    test('quotes strings, leaves numbers and booleans bare', () {
      final doc = DayzCfgDocument.parse('')
        ..set('s', 'say "hi"')
        ..set('n', 3)
        ..set('f', 1.5)
        ..set('b', false);
      expect(
        doc.toSource(),
        's = "say ""hi""";\nn = 3;\nf = 1.5;\nb = false;\n',
      );
    });

    test('appends in the file line ending and removes a key line', () {
      final doc = DayzCfgDocument.parse('a = 1;\r\nb = 2;\r\n')
        ..set('c', 3)
        ..remove('a');
      expect(doc.toSource(), 'b = 2;\r\nc = 3;\r\n');
    });

    test('adds a key inside a nested class using its indent', () {
      final doc = DayzCfgDocument.parse('class A\n{\n    x = 1;\n};\n')
        ..set('A.y', 2);
      expect(doc.toSource(), 'class A\n{\n    x = 1;\n    y = 2;\n};\n');
    });

    test('creates a missing class block', () {
      final doc = DayzCfgDocument.parse('a = 1;\n')..set('B.c', 2);
      expect(doc.get('B.c'), 2);
      expect(DayzCfgDocument.parse(doc.toSource()).get('B.c'), 2);
    });

    test('keeps a BOM', () {
      final doc = DayzCfgDocument.parse('﻿a = 1;\n')..set('a', 2);
      expect(doc.toSource(), '﻿a = 2;\n');
    });
  });

  test('edits one line of the real serverDZ.cfg', () {
    final original = File('test/corpus/serverDZ.cfg').readAsStringSync();
    final doc = DayzCfgDocument.parse(original)
      ..set('maxPlayers', 40)
      ..set('Missions.DayZ.template', 'dayzOffline.enoch')
      ..set('motd', ['Hi']);
    final a = original.split('\n');
    final b = doc.toSource().split('\n');
    // The appended key adds one line; of the original lines only the two
    // edited ones differ.
    expect(b.length, a.length + 1);
    expect([
      for (var i = 0; i < a.length; i++)
        if (a[i] != b[i]) a[i].trim(),
    ], hasLength(2));
    expect(doc.get('maxPlayers'), 40);
    expect(b.last, 'motd[] = {"Hi"};');
  });

  group('ini', () {
    test('reads sections and top-level keys', () {
      final doc = IniDocument.parse(
        'top = 1\n[S]\n; c\nk = "v w"\n# d\nj=2\n[S.T]\nm = 3\n',
      );
      expect(doc.get('top'), '1');
      expect(doc.get('S.k'), 'v w');
      expect(doc.get('S.j'), '2');
      expect(doc.get('S.T.m'), '3');
      expect(doc.get('S.nope'), isNull);
    });

    test('appends to the end of an existing section', () {
      final doc = IniDocument.parse('[A]\nx = 1\n\n[B]\ny = 2\n')
        ..set('A.z', 3);
      expect(doc.toSource(), '[A]\nx = 1\nz = 3\n\n[B]\ny = 2\n');
    });

    test('creates a missing section and keeps CRLF', () {
      final doc = IniDocument.parse('a = 1\r\n')..set('N.k', 'v');
      expect(doc.toSource(), 'a = 1\r\n\r\n[N]\r\nk = v\r\n');
    });

    test('keeps the separator style and quotes of a changed value', () {
      final doc = IniDocument.parse('a=1\nb = "x"\n')
        ..set('a', 2)
        ..set('b', 'y');
      expect(doc.toSource(), 'a=2\nb = "y"\n');
    });

    test('removes a key', () {
      final doc = IniDocument.parse('[A]\nx = 1\ny = 2\n')..remove('A.x');
      expect(doc.toSource(), '[A]\ny = 2\n');
    });
  });

  group('kv', () {
    test('keeps each line style', () {
      final doc = KvDocument.parse('A 1\nB=2\nC = 3\n# note\nFlag\n')
        ..set('A', 10)
        ..set('B', 20)
        ..set('C', 30);
      expect(doc.toSource(), 'A 10\nB=20\nC = 30\n# note\nFlag\n');
      expect(doc.get('Flag'), '');
      expect(doc.get('Missing'), isNull);
    });

    test('keeps multi-word values and appends in the last style', () {
      final doc = KvDocument.parse('Max 72 1\r\n')
        ..set('Other', 5)
        ..set('Pair', [1, 2]);
      expect(doc.get('Max'), '72 1');
      expect(doc.toSource(), 'Max 72 1\r\nOther 5\r\nPair 1 2\r\n');
    });

    test('applies a key path patch where null removes', () {
      final doc = KvDocument.parse('A 1\nB 2\n')
        ..applyPatch({'A': 9, 'B': null, 'C': 'x'});
      expect(doc.toSource(), 'A 9\nC x\n');
    });
  });
}
