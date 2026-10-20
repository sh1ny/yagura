import 'dart:convert';

import 'config_document.dart';
import 'source_lines.dart';

sealed class _Item {
  /// Whitespace and comments between the previous item (or the opening
  /// brace, or the start of the file) and this one.
  String lead = '';

  /// The rest of the line after the item's `;`: spaces, a `//` comment and
  /// the line ending.
  String trail = '';
}

final class _Entry extends _Item {
  _Entry(this.name, {this.isArray = false});

  String name;
  bool isArray;
  String beforeEquals = ' ';
  String afterEquals = ' ';
  String value = '';
  String beforeSemicolon = '';
}

final class _Class extends _Item {
  _Class(this.name);

  String name;
  String afterKeyword = ' ';

  /// Everything between the name and the opening brace.
  String afterName = '\n';
  final List<_Item> items = [];

  /// Whitespace and comments between the last item and the closing brace.
  String closeLead = '';
  String beforeSemicolon = '';
}

final class _Root {
  final List<_Item> items = [];

  /// Whitespace and comments between the last item and the end of the file.
  String closeLead = '';
}

/// A `dayz-cfg` config file such as DayZ's `serverDZ.cfg`: `key = value;`
/// entries, `class Name { ... };` blocks that nest, arrays written
/// `name[] = {"a", "b"};`, and `//` and `/* */` comments.
///
/// Comments, blank lines, key order, spacing, line endings and a leading byte
/// order mark are all kept. Parsing is strict about the structure: values are
/// a string, a bare token or a brace array, every entry ends in `;`, and every
/// `class` has a body and a closing `};`. Forward declarations such as
/// `class A;` are not supported.
///
/// Key paths are class names and a key name joined by dots: `maxPlayers`, or
/// `Missions.DayZ.template`. An array is addressed without its brackets
/// (`motd` for `motd[]`). Names are matched exactly (case-sensitive); when a
/// name appears more than once, [get] and [set] act on the last one and
/// [remove] drops all of them.
///
/// Values follow the file's conventions. [get] returns a quoted string as a
/// `String` (a doubled `""` reads as one quote), a number as `int` or
/// `double`, `true`/`false` as `bool`, any other bare token as a `String`, and
/// an array as a `List` of those. [set] writes a `String` in double quotes
/// (quotes inside doubled), a `num` or `bool` bare, and a `List` as
/// `name[] = {"a", "b"};` (the key gains or loses its `[]` to match). Setting
/// a value equal to the current one leaves the text untouched, so a bare
/// `x = abc;` stays as it is when set to `'abc'`.
///
/// A new key is appended after the last item of its class in the file's line
/// ending, with the indent of that item; a missing class is created the same
/// way. [remove] deletes the whole line of the entry but leaves the comments
/// around it.
class DayzCfgDocument extends ConfigDocument {
  DayzCfgDocument._(this._root, this._bom, this._eol, this._indentUnit);

  /// Parses [source]; throws [ConfigParseException] with the line and column
  /// of the first problem.
  factory DayzCfgDocument.parse(String source) {
    final bom = source.startsWith(bomChar);
    final text = bom ? source.substring(1) : source;
    final root = _Parser(text).parseRoot();
    final eol = text.contains('\r\n') ? '\r\n' : '\n';
    return DayzCfgDocument._(root, bom, eol, _detectIndent(root));
  }

  final _Root _root;
  final bool _bom;
  final String _eol;
  final String _indentUnit;

  static String _detectIndent(_Root block) {
    for (final item in block.items) {
      final indent = _indentOf(item.lead);
      if (indent.isNotEmpty) return indent;
    }
    return '    ';
  }

  @override
  String toSource() {
    final out = StringBuffer(_bom ? bomChar : '');
    _writeItems(_root.items, _root.closeLead, out);
    return out.toString();
  }

  static void _writeItems(
    List<_Item> items,
    String closeLead,
    StringBuffer out,
  ) {
    for (final item in items) {
      out.write(item.lead);
      switch (item) {
        case _Entry():
          out
            ..write(item.name)
            ..write(item.isArray ? '[]' : '')
            ..write(item.beforeEquals)
            ..write('=')
            ..write(item.afterEquals)
            ..write(item.value)
            ..write(item.beforeSemicolon)
            ..write(';');
        case _Class():
          out
            ..write('class')
            ..write(item.afterKeyword)
            ..write(item.name)
            ..write(item.afterName)
            ..write('{');
          _writeItems(item.items, item.closeLead, out);
          out
            ..write('}')
            ..write(item.beforeSemicolon)
            ..write(';');
      }
      out.write(item.trail);
    }
    out.write(closeLead);
  }

  // --- lookup -------------------------------------------------------------

  static List<String> _segments(String path) {
    final parts = path.split('.');
    final last = parts.last;
    parts[parts.length - 1] = last.endsWith('[]')
        ? last.substring(0, last.length - 2)
        : last;
    return parts;
  }

  /// The class block named by [classes] under the root, or `null`.
  ({List<_Item> items, _Class? owner})? _findContainer(List<String> classes) {
    List<_Item> items = _root.items;
    _Class? owner;
    for (final name in classes) {
      final index = items.lastIndexWhere((i) => i is _Class && i.name == name);
      if (index < 0) return null;
      owner = items[index] as _Class;
      items = owner.items;
    }
    return (items: items, owner: owner);
  }

  _Entry? _findEntry(String path) {
    final parts = _segments(path);
    final container = _findContainer(parts.sublist(0, parts.length - 1));
    if (container == null) return null;
    final index = container.items.lastIndexWhere(
      (i) => i is _Entry && i.name == parts.last,
    );
    return index < 0 ? null : container.items[index] as _Entry;
  }

  @override
  Object? get(String path) {
    final entry = _findEntry(path);
    return entry == null ? null : _readValue(entry.value);
  }

  @override
  void set(String path, Object? value) {
    final rendered = _render(value);
    final isArray = value is List;
    final parts = _segments(path);
    final entry = _findEntry(path);
    if (entry != null) {
      if (entry.isArray == isArray &&
          jsonEncode(_readValue(entry.value)) ==
              jsonEncode(_readValue(rendered))) {
        return;
      }
      entry
        ..isArray = isArray
        ..value = rendered;
      return;
    }
    var items = _root.items;
    _Class? owner;
    for (final name in parts.sublist(0, parts.length - 1)) {
      final index = items.lastIndexWhere((i) => i is _Class && i.name == name);
      if (index >= 0) {
        owner = items[index] as _Class;
      } else {
        final created = _Class(name)..afterName = _eol;
        _append(items, owner, created);
        owner = created;
      }
      items = owner.items;
    }
    _append(
      items,
      owner,
      _Entry(parts.last, isArray: isArray)..value = rendered,
    );
  }

  /// Appends [item] to [items], the body of [owner] (the root when `null`).
  void _append(List<_Item> items, _Class? owner, _Item item) {
    if (items.isEmpty) {
      final classIndent = owner == null ? '' : _indentOf(owner.lead);
      if (owner == null) {
        item
          ..lead = ''
          ..trail = _eol;
      } else {
        item
          ..lead = '$_eol$classIndent$_indentUnit'
          ..trail = _eol;
        owner.closeLead = classIndent;
      }
    } else {
      final last = items.last;
      final indent = _indentOf(last.lead);
      if (last.trail.endsWith('\n')) {
        item
          ..lead = indent
          ..trail = _eol;
      } else if (owner == null) {
        // The unterminated last line of the file: end it, keep the new last
        // line unterminated as well.
        last.trail += _eol;
        item
          ..lead = indent
          ..trail = '';
      } else {
        item
          ..lead = '$_eol$indent'
          ..trail = '';
      }
    }
    items.add(item);
  }

  @override
  void remove(String path) {
    final parts = _segments(path);
    final container = _findContainer(parts.sublist(0, parts.length - 1));
    if (container == null) return;
    final owner = container.owner;
    final items = container.items;
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (item is! _Entry || item.name != parts.last) continue;
      final startsLine =
          item.lead.contains('\n') ||
          (i == 0 && owner == null) ||
          (i > 0 && items[i - 1].trail.endsWith('\n'));
      final carry = startsLine
          ? item.lead.substring(0, item.lead.lastIndexOf('\n') + 1)
          : item.trail;
      items.removeAt(i);
      if (i < items.length) {
        items[i].lead = carry + items[i].lead;
      } else if (owner != null) {
        owner.closeLead = carry + owner.closeLead;
      } else {
        _root.closeLead = carry + _root.closeLead;
      }
    }
  }

  // --- values -------------------------------------------------------------

  static String _indentOf(String lead) {
    final tail = lead.substring(lead.lastIndexOf('\n') + 1);
    return tail.trim().isEmpty ? tail : '';
  }

  static String _render(Object? value) => switch (value) {
    null => throw ArgumentError.notNull('value'),
    String() => '"${value.replaceAll('"', '""')}"',
    num() || bool() => value.toString(),
    List() => '{${value.map(_render).join(', ')}}',
    _ => throw ArgumentError.value(value, 'value', 'unsupported value type'),
  };

  static Object? _readValue(String raw) {
    final text = raw.trim();
    if (text.startsWith('{')) {
      final inner = text.substring(1, text.length - 1);
      return [for (final part in _splitElements(inner)) _readValue(part)];
    }
    if (text.startsWith('"')) {
      return text.substring(1, text.length - 1).replaceAll('""', '"');
    }
    if (text == 'true') return true;
    if (text == 'false') return false;
    return int.tryParse(text) ?? double.tryParse(text) ?? text;
  }

  /// Splits array contents at top-level commas, ignoring strings, nested
  /// arrays and comments.
  static List<String> _splitElements(String inner) {
    final parts = <String>[];
    var depth = 0;
    var start = 0;
    var i = 0;
    while (i < inner.length) {
      final c = inner[i];
      if (c == '"') {
        i++;
        while (i < inner.length) {
          if (inner[i] == '"') {
            if (i + 1 < inner.length && inner[i + 1] == '"') {
              i += 2;
              continue;
            }
            break;
          }
          i++;
        }
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
      } else if (c == ',' && depth == 0) {
        parts.add(_stripComments(inner.substring(start, i)));
        start = i + 1;
      }
      i++;
    }
    final lastPart = _stripComments(inner.substring(start));
    if (lastPart.trim().isNotEmpty || parts.isNotEmpty) parts.add(lastPart);
    return parts;
  }

  static String _stripComments(String text) => text
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');
}

class _Parser {
  _Parser(this.text);

  final String text;
  int pos = 0;

  Never fail(String message, [int? at]) =>
      throw ConfigParseException.atOffset(message, text, at ?? pos);

  _Root parseRoot() {
    final root = _Root();
    root.closeLead = parseItems(root.items, null);
    return root;
  }

  /// Reads items into [items] until the closing brace of a block (or the end
  /// of the file for the root) and returns the text before that brace.
  String parseItems(List<_Item> items, _Class? owner) {
    while (true) {
      final lead = trivia();
      if (pos >= text.length) {
        if (owner != null) fail('Missing "}" for class ${owner.name}');
        return lead;
      }
      if (text[pos] == '}') {
        if (owner == null) fail('Unexpected "}"');
        return lead;
      }
      final item = parseItem();
      item.lead = lead;
      items.add(item);
    }
  }

  _Item parseItem() {
    final start = pos;
    final word = identifier();
    if (word.isEmpty) fail('Expected a key name or "class"');
    if (word == 'class' && pos < text.length && isSpace(text.codeUnitAt(pos))) {
      return parseClass();
    }
    final entry = _Entry(word);
    if (text.startsWith('[]', pos)) {
      entry.isArray = true;
      pos += 2;
    }
    entry.beforeEquals = trivia();
    if (!(pos < text.length && text[pos] == '=')) {
      fail('Expected "=" after ${entry.name}', pos < text.length ? pos : start);
    }
    pos++;
    entry.afterEquals = trivia();
    final valueStart = pos;
    parseValue();
    entry.value = text.substring(valueStart, pos);
    entry.beforeSemicolon = trivia();
    expectSemicolon();
    entry.trail = lineTrail();
    return entry;
  }

  _Class parseClass() {
    final afterKeyword = trivia();
    final nameAt = pos;
    final name = identifier();
    if (name.isEmpty) fail('Expected a class name', nameAt);
    final cls = _Class(name)..afterKeyword = afterKeyword;
    final headStart = pos;
    while (pos < text.length && text[pos] != '{') {
      if (text[pos] == ';') fail('A class needs a body: class $name { ... };');
      pos++;
    }
    if (pos >= text.length) fail('Missing "{" for class $name', headStart);
    cls.afterName = text.substring(headStart, pos);
    pos++; // {
    cls.closeLead = parseItems(cls.items, cls);
    pos++; // }
    cls.beforeSemicolon = trivia();
    expectSemicolon();
    cls.trail = lineTrail();
    return cls;
  }

  void expectSemicolon() {
    if (pos >= text.length || text[pos] != ';') fail('Expected ";"');
    pos++;
  }

  // --- values -------------------------------------------------------------

  void parseValue() {
    if (pos >= text.length) fail('Expected a value');
    switch (text[pos]) {
      case '"':
        parseString();
      case '{':
        parseArray();
      default:
        final start = pos;
        while (pos < text.length && isBareChar(pos)) {
          pos++;
        }
        if (pos == start) fail('Expected a value');
    }
  }

  bool isBareChar(int at) {
    final c = text[at];
    if (c == ';' || c == ',' || c == '{' || c == '}' || c == '"') return false;
    if (isSpace(text.codeUnitAt(at))) return false;
    if (c == '/' && at + 1 < text.length) {
      final n = text[at + 1];
      if (n == '/' || n == '*') return false;
    }
    return true;
  }

  void parseString() {
    final start = pos;
    pos++;
    while (true) {
      if (pos >= text.length) fail('Unterminated string', start);
      if (text[pos] == '"') {
        if (pos + 1 < text.length && text[pos + 1] == '"') {
          pos += 2;
          continue;
        }
        pos++;
        return;
      }
      pos++;
    }
  }

  void parseArray() {
    final start = pos;
    pos++; // {
    trivia();
    if (pos < text.length && text[pos] == '}') {
      pos++;
      return;
    }
    while (true) {
      trivia();
      parseValue();
      trivia();
      if (pos >= text.length) fail('Unterminated array', start);
      if (text[pos] == ',') {
        pos++;
        continue;
      }
      if (text[pos] == '}') {
        pos++;
        return;
      }
      fail('Expected "," or "}" in the array');
    }
  }

  // --- trivia -------------------------------------------------------------

  static bool isSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

  String identifier() {
    final start = pos;
    while (pos < text.length && RegExp(r'[A-Za-z0-9_]').hasMatch(text[pos])) {
      pos++;
    }
    return text.substring(start, pos);
  }

  /// Consumes whitespace and comments.
  String trivia() {
    final start = pos;
    while (pos < text.length) {
      final c = text.codeUnitAt(pos);
      if (isSpace(c)) {
        pos++;
      } else if (text.startsWith('//', pos)) {
        final nl = text.indexOf('\n', pos);
        pos = nl < 0 ? text.length : nl;
      } else if (text.startsWith('/*', pos)) {
        final end = text.indexOf('*/', pos + 2);
        if (end < 0) fail('Unterminated comment');
        pos = end + 2;
      } else {
        break;
      }
    }
    return text.substring(start, pos);
  }

  /// Consumes the rest of the line after an item: spaces, a `//` comment and
  /// the line ending.
  String lineTrail() {
    final start = pos;
    while (pos < text.length && (text[pos] == ' ' || text[pos] == '\t')) {
      pos++;
    }
    if (text.startsWith('//', pos)) {
      final nl = text.indexOf('\n', pos);
      pos = nl < 0 ? text.length : nl;
      if (pos > start && text[pos - 1] == '\r') pos--;
    }
    if (text.startsWith('\r\n', pos)) {
      pos += 2;
    } else if (pos < text.length && text[pos] == '\n') {
      pos++;
    }
    return text.substring(start, pos);
  }
}
