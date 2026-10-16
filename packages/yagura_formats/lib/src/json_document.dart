import 'dart:convert';

/// A node of a lossless JSON tree. Every node keeps the whitespace around it
/// ([leading] before the value, [trailing] after it), so serialising an
/// untouched tree reproduces the source byte for byte.
sealed class JsonNode {
  String leading = '';
  String trailing = '';

  /// The node as plain Dart data (`Map`, `List`, `String`, `num`, `bool`,
  /// `null`).
  Object? toValue();
}

/// A string, number, `true`, `false` or `null`, kept as its source text.
final class JsonScalar extends JsonNode {
  JsonScalar(this.raw);

  String raw;

  @override
  Object? toValue() => jsonDecode(raw);
}

/// One `"key": value` pair of a [JsonObject].
final class JsonMember {
  JsonMember({
    required this.rawKey,
    required this.value,
    this.beforeKey = '',
    this.beforeColon = '',
  });

  /// Whitespace before the key.
  String beforeKey;

  /// The key as written, quotes and escapes included.
  String rawKey;

  /// Whitespace between the key and the colon. The whitespace after the colon
  /// is `value.leading`.
  String beforeColon;

  JsonNode value;

  String get key => jsonDecode(rawKey) as String;
}

final class JsonObject extends JsonNode {
  JsonObject([List<JsonMember>? members]) : members = members ?? [];

  final List<JsonMember> members;

  /// Whitespace between the braces of an empty object.
  String emptyInner = '';

  @override
  Object? toValue() => {for (final m in members) m.key: m.value.toValue()};
}

final class JsonArray extends JsonNode {
  JsonArray([List<JsonNode>? items]) : items = items ?? [];

  final List<JsonNode> items;

  /// Whitespace between the brackets of an empty array.
  String emptyInner = '';

  @override
  Object? toValue() => [for (final i in items) i.toValue()];
}

/// A parsed JSON text that serialises back to exactly what was parsed, apart
/// from the edits applied with [mergePatch].
///
/// Parsing is strict JSON (RFC 8259): no comments and no trailing commas. A
/// leading byte order mark is kept.
class JsonDocument {
  JsonDocument._(this.root, this._bom, this._style);

  /// Maximum nesting depth accepted by [parse].
  static const maxDepth = 512;

  /// Parses [source]; throws [FormatException] with the offset on bad input.
  factory JsonDocument.parse(String source) {
    final bom = source.startsWith('﻿');
    final text = bom ? source.substring(1) : source;
    final root = _Parser(text).parseDocument();
    return JsonDocument._(root, bom, _Style.detect(text, root));
  }

  JsonNode root;
  final bool _bom;
  final _Style _style;

  /// The document as text, identical to the parsed source if unedited.
  String toSource() {
    final out = StringBuffer();
    if (_bom) out.write('﻿');
    _write(root, out);
    return out.toString();
  }

  /// The document as plain Dart data.
  Object? toValue() => root.toValue();

  /// Applies [patch] with RFC 7386 (JSON Merge Patch) semantics: an object
  /// patch merges recursively, `null` removes a key, anything else (arrays
  /// included) replaces the value. [patch] is plain Dart JSON data.
  ///
  /// Untouched members keep their order and formatting; new members take the
  /// layout of their siblings.
  void mergePatch(Object? patch) {
    root = _merge(root, patch, 0);
  }

  JsonNode _merge(JsonNode target, Object? patch, int depth) {
    if (patch is! Map) return _replace(target, _build(patch, depth));
    final JsonObject object;
    if (target is JsonObject) {
      object = target;
    } else {
      object = JsonObject()
        ..leading = target.leading
        ..trailing = target.trailing;
    }
    for (final entry in patch.entries) {
      final key = entry.key as String;
      final Object? value = entry.value;
      final index = object.members.lastIndexWhere((m) => m.key == key);
      if (value == null) {
        _removeKey(object, key);
      } else if (index >= 0) {
        final member = object.members[index];
        member.value = _merge(member.value, value, depth + 1);
      } else {
        _addMember(object, key, value, depth);
      }
    }
    return object;
  }

  JsonNode _replace(JsonNode old, JsonNode replacement) => replacement
    ..leading = old.leading
    ..trailing = old.trailing;

  void _removeKey(JsonObject object, String key) {
    while (true) {
      final index = object.members.lastIndexWhere((m) => m.key == key);
      if (index < 0) return;
      final removed = object.members.removeAt(index);
      if (index == object.members.length && object.members.isNotEmpty) {
        // The removed member was last: its trailing whitespace precedes the
        // closing brace, so it moves to the new last member.
        object.members.last.value.trailing = removed.value.trailing;
      }
      if (object.members.isEmpty) object.emptyInner = '';
    }
  }

  void _addMember(JsonObject object, String key, Object value, int depth) {
    final rawKey = jsonEncode(key);
    final node = _build(value, depth + 1);
    if (object.members.isEmpty) {
      final style = _style;
      object.members.add(
        JsonMember(
          rawKey: rawKey,
          value: node
            ..leading = style.afterColon
            ..trailing = style.newlineIndent(depth),
          beforeKey: style.newlineIndent(depth + 1),
          beforeColon: style.beforeColon,
        ),
      );
      return;
    }
    final last = object.members.last;
    final previousTrailing = object.members.length > 1
        ? object.members[object.members.length - 2].value.trailing
        : '';
    object.members.add(
      JsonMember(
        rawKey: rawKey,
        value: node
          ..leading = last.value.leading
          ..trailing = last.value.trailing,
        beforeKey: last.beforeKey,
        beforeColon: last.beforeColon,
      ),
    );
    last.value.trailing = previousTrailing;
  }

  /// Builds a node for new data in the document's detected layout.
  JsonNode _build(Object? value, int depth) {
    switch (value) {
      case Map():
        final object = JsonObject();
        final entries = value.entries.toList();
        for (var i = 0; i < entries.length; i++) {
          final node = _build(entries[i].value, depth + 1)
            ..leading = _style.afterColon
            ..trailing = i == entries.length - 1
                ? _style.newlineIndent(depth)
                : '';
          object.members.add(
            JsonMember(
              rawKey: jsonEncode(entries[i].key as String),
              value: node,
              beforeKey: _style.newlineIndent(depth + 1),
              beforeColon: _style.beforeColon,
            ),
          );
        }
        return object;
      case List():
        final array = JsonArray();
        for (var i = 0; i < value.length; i++) {
          array.items.add(
            _build(value[i], depth + 1)
              ..leading = _style.newlineIndent(depth + 1)
              ..trailing = i == value.length - 1
                  ? _style.newlineIndent(depth)
                  : '',
          );
        }
        return array;
      default:
        return JsonScalar(jsonEncode(value));
    }
  }

  static void _write(JsonNode node, StringBuffer out) {
    out.write(node.leading);
    switch (node) {
      case JsonScalar():
        out.write(node.raw);
      case JsonObject():
        out.write('{');
        if (node.members.isEmpty) out.write(node.emptyInner);
        for (var i = 0; i < node.members.length; i++) {
          final member = node.members[i];
          if (i > 0) out.write(',');
          out
            ..write(member.beforeKey)
            ..write(member.rawKey)
            ..write(member.beforeColon)
            ..write(':');
          _write(member.value, out);
        }
        out.write('}');
      case JsonArray():
        out.write('[');
        if (node.items.isEmpty) out.write(node.emptyInner);
        for (var i = 0; i < node.items.length; i++) {
          if (i > 0) out.write(',');
          _write(node.items[i], out);
        }
        out.write(']');
    }
    out.write(node.trailing);
  }
}

/// Layout detected from the source, used for members and values a patch adds.
class _Style {
  _Style({
    required this.indent,
    required this.newline,
    required this.beforeColon,
    required this.afterColon,
  });

  /// One indentation level, or `null` when the document is not indented.
  final String? indent;
  final String newline;
  final String beforeColon;
  final String afterColon;

  String newlineIndent(int depth) =>
      indent == null ? '' : '$newline${indent! * depth}';

  static _Style detect(String text, JsonNode root) {
    final indentMatch = RegExp(r'\n([ \t]+)[^ \t\r\n]').firstMatch(text);
    final indent = indentMatch?.group(1);
    final newline = text.contains('\r\n') ? '\r\n' : '\n';
    JsonMember? sample;
    void find(JsonNode node) {
      if (sample != null) return;
      switch (node) {
        case JsonObject():
          if (node.members.isNotEmpty) {
            sample = node.members.first;
          }
        case JsonArray():
          node.items.forEach(find);
        case JsonScalar():
          break;
      }
    }

    find(root);
    final member = sample;
    return _Style(
      indent: indent,
      newline: newline,
      beforeColon: member?.beforeColon ?? '',
      afterColon: member?.value.leading ?? (indent == null ? '' : ' '),
    );
  }
}

class _Parser {
  _Parser(this.text);

  final String text;
  int pos = 0;

  static final _number = RegExp(
    r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
  );

  Never fail(String message) =>
      throw FormatException('$message at offset $pos', text, pos);

  JsonNode parseDocument() {
    final node = parseNode(0);
    if (pos != text.length) fail('Unexpected content after the JSON value');
    return node;
  }

  String whitespace() {
    final start = pos;
    while (pos < text.length) {
      final c = text.codeUnitAt(pos);
      if (c != 0x20 && c != 0x09 && c != 0x0A && c != 0x0D) break;
      pos++;
    }
    return text.substring(start, pos);
  }

  JsonNode parseNode(int depth) {
    final leading = whitespace();
    final node = parseValue(depth);
    node
      ..leading = leading
      ..trailing = whitespace();
    return node;
  }

  JsonNode parseValue(int depth) {
    if (depth > JsonDocument.maxDepth) fail('JSON is nested too deeply');
    if (pos >= text.length) fail('Unexpected end of JSON');
    switch (text[pos]) {
      case '{':
        return parseObject(depth);
      case '[':
        return parseArray(depth);
      case '"':
        return JsonScalar(parseString());
      case 't':
        return JsonScalar(literal('true'));
      case 'f':
        return JsonScalar(literal('false'));
      case 'n':
        return JsonScalar(literal('null'));
      default:
        final match = _number.matchAsPrefix(text, pos);
        if (match == null) fail('Unexpected character');
        pos = match.end;
        return JsonScalar(match.group(0)!);
    }
  }

  String literal(String word) {
    if (!text.startsWith(word, pos)) fail('Invalid literal');
    pos += word.length;
    return word;
  }

  /// Reads a string literal and returns its source text.
  String parseString() {
    final start = pos;
    pos++; // opening quote
    while (true) {
      if (pos >= text.length) fail('Unterminated string');
      final c = text.codeUnitAt(pos);
      if (c == 0x22) {
        pos++;
        return text.substring(start, pos);
      }
      if (c < 0x20) fail('Control character in string');
      if (c == 0x5C) {
        pos++;
        if (pos >= text.length) fail('Unterminated string');
        final e = text[pos];
        if (e == 'u') {
          final hex = pos + 5 <= text.length
              ? text.substring(pos + 1, pos + 5)
              : '';
          if (!RegExp(r'^[0-9a-fA-F]{4}$').hasMatch(hex)) {
            fail('Bad \\u escape');
          }
          pos += 4;
        } else if (!'"\\/bfnrt'.contains(e)) {
          fail('Bad escape');
        }
      }
      pos++;
    }
  }

  JsonObject parseObject(int depth) {
    final object = JsonObject();
    pos++; // {
    var before = whitespace();
    if (pos < text.length && text[pos] == '}') {
      pos++;
      object.emptyInner = before;
      return object;
    }
    while (true) {
      if (pos >= text.length || text[pos] != '"') fail('Expected a string key');
      final rawKey = parseString();
      final beforeColon = whitespace();
      if (pos >= text.length || text[pos] != ':') fail('Expected ":"');
      pos++;
      final value = parseNode(depth + 1);
      object.members.add(
        JsonMember(
          beforeKey: before,
          rawKey: rawKey,
          beforeColon: beforeColon,
          value: value,
        ),
      );
      if (pos >= text.length) fail('Unterminated object');
      if (text[pos] == ',') {
        pos++;
        before = whitespace();
        continue;
      }
      if (text[pos] == '}') {
        pos++;
        return object;
      }
      fail('Expected "," or "}"');
    }
  }

  JsonArray parseArray(int depth) {
    final array = JsonArray();
    pos++; // [
    final inner = whitespace();
    if (pos < text.length && text[pos] == ']') {
      pos++;
      array.emptyInner = inner;
      return array;
    }
    pos -= inner.length; // the first element owns this whitespace
    while (true) {
      array.items.add(parseNode(depth + 1));
      if (pos >= text.length) fail('Unterminated array');
      if (text[pos] == ',') {
        pos++;
        continue;
      }
      if (text[pos] == ']') {
        pos++;
        return array;
      }
      fail('Expected "," or "]"');
    }
  }
}
