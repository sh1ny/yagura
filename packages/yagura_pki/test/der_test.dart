import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yagura_pki/src/der.dart';
import 'package:yagura_pki/src/errors.dart';

Uint8List bytes(List<int> v) => Uint8List.fromList(v);

void main() {
  group('encoding round trips through the parser', () {
    test('integers', () {
      for (final value in [
        BigInt.zero,
        BigInt.one,
        BigInt.from(127),
        BigInt.from(128),
        BigInt.from(255),
        BigInt.from(256),
        BigInt.parse('ffffffffffffffffffffffffffffffff', radix: 16),
        BigInt.parse('80000000000000000000000000000000', radix: 16),
      ]) {
        expect(parseDer(derInteger(value)).integer, value, reason: '$value');
      }
    });

    test('an INTEGER whose top bit is set gets a leading zero', () {
      expect(derInteger(BigInt.from(128)), [0x02, 0x02, 0x00, 0x80]);
      expect(derInteger(BigInt.from(127)), [0x02, 0x01, 0x7f]);
      expect(derInteger(BigInt.zero), [0x02, 0x01, 0x00]);
    });

    test('object identifiers', () {
      for (final oid in [
        '1.2.840.10045.4.3.2',
        '2.5.29.19',
        '1.3.6.1.5.5.7.3.1',
        '2.5.4.3',
      ]) {
        expect(parseDer(derOid(oid)).oid, oid);
      }
      expect(derOid('1.2.840.113549'), [
        0x06,
        0x06,
        0x2a,
        0x86,
        0x48,
        0x86,
        0xf7,
        0x0d,
      ]);
    });

    test('lengths of 127, 128, 255, 256 and 70000 bytes', () {
      for (final length in [0, 1, 127, 128, 255, 256, 70000]) {
        final element = derOctetString(List<int>.filled(length, 7));
        final parsed = parseDer(element);
        expect(parsed.octetString, hasLength(length));
        expect(parsed.encoded, element);
      }
      expect(derOctetString(List<int>.filled(128, 0)).sublist(0, 3), [
        0x04,
        0x81,
        0x80,
      ]);
    });

    test('times use UTCTime up to 2049 and GeneralizedTime after', () {
      final a = DateTime.utc(2026, 10, 18, 12, 30, 45);
      final b = DateTime.utc(2050, 1, 2, 3, 4, 5);
      expect(derTime(a)[0], Tag.utcTime);
      expect(derTime(b)[0], Tag.generalizedTime);
      expect(parseDer(derTime(a)).time, a);
      expect(parseDer(derTime(b)).time, b);
    });

    test('booleans, bit strings, text', () {
      expect(parseDer(derBoolean(true)).boolean, isTrue);
      expect(parseDer(derBoolean(false)).boolean, isFalse);
      expect(parseDer(derBitString([1, 2, 3])).bitString(), bytes([1, 2, 3]));
      expect(parseDer(derUtf8String('Wächter 守')).text, 'Wächter 守');
    });

    test('nested sequences and context elements', () {
      final der = derSequence([
        derSmallInteger(1),
        derContext(3, [
          derSequence([derOid('2.5.4.3')]),
        ]),
      ]);
      final top = parseDer(der).sequence;
      expect(top, hasLength(2));
      expect(top[1].tag, contextTag(3, constructed: true));
      expect(top[1].children.single.sequence.single.oid, '2.5.4.3');
    });
  });

  group('the parser refuses what DER forbids', () {
    void refuses(String name, List<int> data) {
      test(name, () {
        expect(() => parseDer(bytes(data)), throwsA(isA<DerException>()));
      });
    }

    refuses('an empty input', const []);
    refuses('a truncated header', const [0x30]);
    refuses('indefinite length', const [0x30, 0x80, 0x00, 0x00]);
    refuses('a length longer than the input', const [0x04, 0x05, 0x01]);
    refuses('a non-minimal long length', const [
      0x04,
      0x81,
      0x05,
      1,
      2,
      3,
      4,
      5,
    ]);
    refuses('a long length with a leading zero', const [
      0x04,
      0x82,
      0x00,
      0x81,
    ]);
    refuses('a length of more than four bytes', const [
      0x04,
      0x85,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
    refuses('a multi-byte tag', const [0x1f, 0x81, 0x00, 0x00]);
    refuses('trailing bytes', [...derSmallInteger(1), 0x00]);
    refuses('two elements where one is expected', [
      ...derSmallInteger(1),
      ...derSmallInteger(2),
    ]);

    test('a negative INTEGER', () {
      expect(
        () => parseDer(bytes([0x02, 0x01, 0x80])).integer,
        throwsA(isA<DerException>()),
      );
    });

    test('an INTEGER with a redundant leading zero', () {
      expect(
        () => parseDer(bytes([0x02, 0x02, 0x00, 0x01])).integer,
        throwsA(isA<DerException>()),
      );
    });

    test('a BOOLEAN that is not 0x00 or 0xff', () {
      expect(
        () => parseDer(bytes([0x01, 0x01, 0x01])).boolean,
        throwsA(isA<DerException>()),
      );
    });

    test('nesting beyond the depth limit', () {
      var element = derSmallInteger(1);
      for (var i = 0; i < maxDerDepth + 3; i++) {
        element = derSequence([element]);
      }
      Der walk(Der node) =>
          node.tag == Tag.sequence ? walk(node.sequence.single) : node;
      expect(() => walk(parseDer(element)), throwsA(isA<DerException>()));
    });

    test('a time with an offset instead of Z', () {
      final bad = derTlv(Tag.utcTime, '261018123045+0100'.codeUnits);
      expect(() => parseDer(bad).time, throwsA(isA<DerException>()));
    });

    test('a calendar date that does not exist', () {
      final bad = derTlv(Tag.utcTime, '260231000000Z'.codeUnits);
      expect(() => parseDer(bad).time, throwsA(isA<DerException>()));
    });
  });
}
