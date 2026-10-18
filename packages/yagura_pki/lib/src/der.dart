import 'dart:convert';
import 'dart:typed_data';

import 'errors.dart';

/// Universal ASN.1 tags the package uses.
abstract final class Tag {
  static const boolean = 0x01;
  static const integer = 0x02;
  static const bitString = 0x03;
  static const octetString = 0x04;
  static const objectIdentifier = 0x06;
  static const utf8String = 0x0c;
  static const printableString = 0x13;
  static const ia5String = 0x16;
  static const utcTime = 0x17;
  static const generalizedTime = 0x18;
  static const sequence = 0x30;
  static const set = 0x31;
}

/// The tag of a context-specific element with number [number] (below 31).
int contextTag(int number, {required bool constructed}) =>
    0x80 | (constructed ? 0x20 : 0) | number;

/// How deep the parser follows nested elements.
const maxDerDepth = 12;

// -- Encoding ---------------------------------------------------------------

/// One DER element: [tag], definite length, [content].
Uint8List derTlv(int tag, List<int> content) {
  final length = content.length;
  final header = <int>[tag];
  if (length < 0x80) {
    header.add(length);
  } else {
    final bytes = <int>[];
    for (var v = length; v > 0; v >>= 8) {
      bytes.insert(0, v & 0xff);
    }
    header
      ..add(0x80 | bytes.length)
      ..addAll(bytes);
  }
  return Uint8List.fromList([...header, ...content]);
}

Uint8List _concat(Iterable<List<int>> parts) =>
    Uint8List.fromList([for (final part in parts) ...part]);

Uint8List derSequence(Iterable<List<int>> items) =>
    derTlv(Tag.sequence, _concat(items));

Uint8List derSet(Iterable<List<int>> items) => derTlv(Tag.set, _concat(items));

/// An explicit or implicit constructed context element wrapping [items].
Uint8List derContext(int number, Iterable<List<int>> items) =>
    derTlv(contextTag(number, constructed: true), _concat(items));

Uint8List derBoolean(bool value) =>
    derTlv(Tag.boolean, [if (value) 0xff else 0x00]);

/// A non-negative INTEGER.
Uint8List derInteger(BigInt value) {
  if (value.isNegative) {
    throw ArgumentError.value(value, 'value', 'must not be negative');
  }
  var bytes = _bigIntBytes(value);
  if (bytes.isEmpty) bytes = [0];
  if (bytes.first & 0x80 != 0) bytes = [0, ...bytes];
  return derTlv(Tag.integer, bytes);
}

Uint8List derSmallInteger(int value) => derInteger(BigInt.from(value));

Uint8List derOctetString(List<int> bytes) => derTlv(Tag.octetString, bytes);

/// A BIT STRING with [unusedBits] unused bits in its last byte.
Uint8List derBitString(List<int> bytes, {int unusedBits = 0}) =>
    derTlv(Tag.bitString, [unusedBits, ...bytes]);

Uint8List derUtf8String(String text) =>
    derTlv(Tag.utf8String, utf8.encode(text));

Uint8List derIa5String(String text) =>
    derTlv(Tag.ia5String, ascii.encode(text));

Uint8List derOid(String dotted) {
  final arcs = dotted.split('.').map(int.parse).toList();
  if (arcs.length < 2 || arcs[0] > 2 || (arcs[0] < 2 && arcs[1] > 39)) {
    throw ArgumentError.value(dotted, 'dotted', 'not an object identifier');
  }
  final out = <int>[];
  void base128(int value) {
    final chunk = <int>[value & 0x7f];
    for (var v = value >> 7; v > 0; v >>= 7) {
      chunk.insert(0, (v & 0x7f) | 0x80);
    }
    out.addAll(chunk);
  }

  base128(arcs[0] * 40 + arcs[1]);
  for (final arc in arcs.skip(2)) {
    base128(arc);
  }
  return derTlv(Tag.objectIdentifier, out);
}

/// UTCTime for 1950-2049, GeneralizedTime otherwise (RFC 5280 4.1.2.5).
Uint8List derTime(DateTime time) {
  final t = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  final tail =
      '${two(t.month)}${two(t.day)}${two(t.hour)}${two(t.minute)}'
      '${two(t.second)}Z';
  if (t.year >= 1950 && t.year <= 2049) {
    return derTlv(Tag.utcTime, ascii.encode('${two(t.year % 100)}$tail'));
  }
  return derTlv(
    Tag.generalizedTime,
    ascii.encode('${t.year.toString().padLeft(4, '0')}$tail'),
  );
}

List<int> _bigIntBytes(BigInt value) {
  if (value == BigInt.zero) return const [];
  final out = <int>[];
  var v = value;
  while (v > BigInt.zero) {
    out.insert(0, (v & BigInt.from(0xff)).toInt());
    v >>= 8;
  }
  return out;
}

/// [value] as exactly [length] big-endian bytes.
Uint8List bigIntToFixedBytes(BigInt value, int length) {
  final bytes = _bigIntBytes(value);
  if (bytes.length > length) {
    throw ArgumentError.value(value, 'value', 'does not fit in $length bytes');
  }
  return Uint8List.fromList([
    ...List<int>.filled(length - bytes.length, 0),
    ...bytes,
  ]);
}

BigInt bytesToBigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}

// -- Parsing ----------------------------------------------------------------

/// One parsed element. [encoded] is the element exactly as it appeared
/// (tag, length and content), so a signature can be checked over it.
class Der {
  Der._(this.tag, this.encoded, this.content, this._depth);

  final int tag;
  final Uint8List encoded;
  final Uint8List content;
  final int _depth;

  /// The elements inside a constructed element, in order.
  List<Der> get children {
    if (tag & 0x20 == 0) {
      throw const DerException('a primitive element has no children');
    }
    return _parseAll(content, _depth + 1);
  }

  bool get isSequence => tag == Tag.sequence;

  /// This element's children, which must be a SEQUENCE.
  List<Der> get sequence {
    if (tag != Tag.sequence) {
      throw DerException('expected a SEQUENCE, found tag 0x${_hex(tag)}');
    }
    return children;
  }

  /// A non-negative INTEGER.
  BigInt get integer {
    if (tag != Tag.integer) {
      throw DerException('expected an INTEGER, found tag 0x${_hex(tag)}');
    }
    if (content.isEmpty) throw const DerException('empty INTEGER');
    if (content[0] & 0x80 != 0) {
      throw const DerException('negative INTEGER');
    }
    if (content.length > 1 && content[0] == 0 && content[1] & 0x80 == 0) {
      throw const DerException('INTEGER is not minimally encoded');
    }
    return bytesToBigInt(content);
  }

  /// The dotted form of an OBJECT IDENTIFIER.
  String get oid {
    if (tag != Tag.objectIdentifier) {
      throw DerException(
        'expected an OBJECT IDENTIFIER, found tag 0x${_hex(tag)}',
      );
    }
    if (content.isEmpty) throw const DerException('empty OBJECT IDENTIFIER');
    final arcs = <int>[];
    var value = 0;
    var open = false;
    for (final b in content) {
      if (!open && b == 0x80) {
        throw const DerException('OBJECT IDENTIFIER is not minimal');
      }
      if (value > (1 << 40)) {
        throw const DerException('OBJECT IDENTIFIER arc is too large');
      }
      value = (value << 7) | (b & 0x7f);
      open = b & 0x80 != 0;
      if (!open) {
        if (arcs.isEmpty) {
          final first = value >= 80 ? 2 : value ~/ 40;
          arcs
            ..add(first)
            ..add(value - first * 40);
        } else {
          arcs.add(value);
        }
        value = 0;
      }
    }
    if (open) throw const DerException('truncated OBJECT IDENTIFIER');
    return arcs.join('.');
  }

  /// A BOOLEAN (DER: 0x00 or 0xff).
  bool get boolean {
    if (tag != Tag.boolean || content.length != 1) {
      throw const DerException('expected a BOOLEAN');
    }
    return switch (content[0]) {
      0x00 => false,
      0xff => true,
      _ => throw const DerException('BOOLEAN is not DER'),
    };
  }

  /// The bytes of a BIT STRING without the unused-bits byte; its unused bits
  /// are returned through [unusedBits] when given.
  Uint8List bitString({void Function(int unusedBits)? unusedBits}) {
    if (tag != Tag.bitString || content.isEmpty) {
      throw const DerException('expected a BIT STRING');
    }
    final unused = content[0];
    if (unused > 7 || (content.length == 1 && unused != 0)) {
      throw const DerException('invalid BIT STRING padding');
    }
    unusedBits?.call(unused);
    return Uint8List.sublistView(content, 1);
  }

  Uint8List get octetString {
    if (tag != Tag.octetString) {
      throw DerException('expected an OCTET STRING, found tag 0x${_hex(tag)}');
    }
    return content;
  }

  /// The text of a UTF8String, PrintableString or IA5String.
  String get text {
    switch (tag) {
      case Tag.utf8String:
        try {
          return utf8.decode(content);
        } on FormatException {
          throw const DerException('invalid UTF-8 text');
        }
      case Tag.printableString || Tag.ia5String:
        if (content.any((b) => b > 0x7f)) {
          throw const DerException('invalid ASCII text');
        }
        return ascii.decode(content);
      default:
        throw DerException('expected a text string, found tag 0x${_hex(tag)}');
    }
  }

  /// A UTCTime or GeneralizedTime in the `...Z` form DER requires.
  DateTime get time {
    final text = switch (tag) {
      Tag.utcTime || Tag.generalizedTime => latin1.decode(content),
      _ => throw DerException('expected a time, found tag 0x${_hex(tag)}'),
    };
    final utc = tag == Tag.utcTime;
    final digits = utc ? 12 : 14;
    if (text.length != digits + 1 ||
        !text.endsWith('Z') ||
        !RegExp(r'^\d+$').hasMatch(text.substring(0, digits))) {
      throw DerException('invalid time "$text"');
    }
    int part(int from, int length) =>
        int.parse(text.substring(from, from + length));
    var year = utc ? part(0, 2) : part(0, 4);
    final rest = utc ? 2 : 4;
    if (utc) year += year >= 50 ? 1900 : 2000;
    final month = part(rest, 2);
    final day = part(rest + 2, 2);
    final hour = part(rest + 4, 2);
    final minute = part(rest + 6, 2);
    final second = part(rest + 8, 2);
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31 ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      throw DerException('invalid time "$text"');
    }
    final result = DateTime.utc(year, month, day, hour, minute, second);
    if (result.month != month || result.day != day) {
      throw DerException('invalid time "$text"');
    }
    return result;
  }
}

String _hex(int v) => v.toRadixString(16).padLeft(2, '0');

/// Parses exactly one element from [data]: no bytes may follow it.
Der parseDer(Uint8List data) {
  final all = _parseAll(data, 0);
  if (all.length != 1) {
    throw const DerException('expected exactly one element');
  }
  return all.single;
}

List<Der> _parseAll(Uint8List data, int depth) {
  if (depth > maxDerDepth) {
    throw const DerException('elements are nested too deeply');
  }
  final out = <Der>[];
  var i = 0;
  while (i < data.length) {
    final start = i;
    final tag = data[i++];
    if (tag & 0x1f == 0x1f) {
      throw const DerException('multi-byte tags are not supported');
    }
    if (i >= data.length) throw const DerException('truncated element');
    var length = data[i++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      if (count == 0) {
        throw const DerException('indefinite lengths are not DER');
      }
      if (count > 4 || i + count > data.length) {
        throw const DerException('invalid length');
      }
      if (data[i] == 0) {
        throw const DerException('length is not minimally encoded');
      }
      length = 0;
      for (var k = 0; k < count; k++) {
        length = (length << 8) | data[i++];
      }
      if (length < 0x80) {
        throw const DerException('length is not minimally encoded');
      }
    }
    if (length > data.length - i) {
      throw const DerException('element is longer than its container');
    }
    out.add(
      Der._(
        tag,
        Uint8List.sublistView(data, start, i + length),
        Uint8List.sublistView(data, i, i + length),
        depth,
      ),
    );
    i += length;
  }
  return out;
}
