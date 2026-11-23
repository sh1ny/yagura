import 'config_document.dart';
import 'source_lines.dart';

/// An `ini` config file: `[section]` headers, `key=value` pairs, and comment
/// lines starting with `;` or `#`.
///
/// Comments, blank lines, key order, spacing around `=`, trailing whitespace,
/// line endings (even mixed ones) and a leading byte order mark are all kept.
/// Comments are recognised only as whole lines: `name = x # y` has the value
/// `x # y`.
///
/// Key paths are `section.key`, or just `key` for a pair before the first
/// section. A section name may itself contain dots (`[Gameplay.Rules]` and
/// the path `Gameplay.Rules.friendly_fire`); the path is matched against the
/// sections present, longest section name first, and a new key whose section
/// is missing is split at the last dot. Names are matched exactly
/// (case-sensitive). When a key appears more than once in a section, [get]
/// and [set] act on the last one and [remove] drops all of them.
///
/// Values are text. [get] returns the raw value without trailing whitespace,
/// minus one pair of surrounding double quotes if present (`"a b"` reads as
/// `a b`); a missing key is `null`. [set] writes a `String`, `num` or `bool`
/// with `toString`: a changed value keeps the quotes of the one it replaces,
/// and a new value is quoted only when it has leading or trailing
/// whitespace. Lists are not supported and throw [ArgumentError]. A new key
/// goes after the last pair of its section (right after the header when the
/// section has none), copying the spacing around `=` of the neighbouring pair
/// (`key = value` when there is none); a new section is added at the end of
/// the file after a blank line. New lines use the file's own line ending.
class IniDocument extends ConfigDocument {
  IniDocument._(this._lines, this._bom);

  /// Parses [source]; throws [ConfigParseException] with the line and column
  /// of an unterminated section header or of a line that is neither a
  /// comment, a section header nor `key=value`.
  factory IniDocument.parse(String source) {
    final bom = source.startsWith(bomChar);
    final lines = splitSourceLines(bom ? source.substring(1) : source);
    String? section;
    for (var i = 0; i < lines.length; i++) {
      section = _parseLine(lines[i], i + 1) ?? section;
    }
    return IniDocument._(lines, bom);
  }

  static final _pair = RegExp(
    r'^([ \t]*)([^=]*?)([ \t]*)=([ \t]*)(.*?)([ \t]*)$',
  );

  /// Fills in [line] and returns its section name when it is a header.
  static String? _parseLine(SourceLine line, int number) {
    final content = line.content;
    final trimmed = content.trimLeft();
    final lead = content.length - trimmed.length;
    if (trimmed.isEmpty || trimmed.startsWith(';') || trimmed.startsWith('#')) {
      return null;
    }
    if (trimmed.startsWith('[')) {
      final close = content.indexOf(']', lead);
      if (close < 0) {
        throw ConfigParseException(
          'Unterminated section header',
          line: number,
          column: content.length + 1,
        );
      }
      final rest = content.substring(close + 1).trimLeft();
      if (rest.isNotEmpty && !rest.startsWith(';') && !rest.startsWith('#')) {
        throw ConfigParseException(
          'Unexpected text after the section header',
          line: number,
          column: content.length - rest.length + 1,
        );
      }
      line.section = content.substring(lead + 1, close).trim();
      return line.section;
    }
    final match = _pair.firstMatch(content);
    if (match == null || match.group(2)!.isEmpty) {
      throw ConfigParseException(
        match == null
            ? 'Expected "key=value", a section header or a comment'
            : 'A pair needs a key before "="',
        line: number,
        column: lead + 1,
      );
    }
    final key = match.group(2)!;
    final keyEnd = lead + key.length;
    final equals = keyEnd + match.group(3)!.length;
    final valueStart = equals + 1 + match.group(4)!.length;
    final valueEnd = valueStart + match.group(5)!.length;
    line
      ..key = key
      ..keyEnd = keyEnd
      ..valueStart = valueStart
      ..valueEnd = valueEnd;
    return null;
  }

  final List<SourceLine> _lines;
  final bool _bom;

  @override
  String toSource() => '${_bom ? bomChar : ''}${_lines.join()}';

  /// The section each line belongs to, `null` before the first header.
  List<String?> _sections() {
    String? current;
    return [
      for (final line in _lines)
        if (line.section != null) current = line.section else current,
    ];
  }

  /// The index of the last entry for [key] in [section], or -1.
  int _find(String? section, String key) {
    final sections = _sections();
    for (var i = _lines.length - 1; i >= 0; i--) {
      if (_lines[i].key == key && sections[i] == section) return i;
    }
    return -1;
  }

  /// Splits [path] into section and key: the longest existing section
  /// prefix, else a top-level key named by the whole path, else the last dot.
  (String?, String) _resolve(String path) {
    final known = {
      for (final line in _lines)
        if (line.section != null) line.section!,
    };
    for (
      var dot = path.lastIndexOf('.');
      dot > 0;
      dot = path.lastIndexOf('.', dot - 1)
    ) {
      if (known.contains(path.substring(0, dot))) {
        return (path.substring(0, dot), path.substring(dot + 1));
      }
    }
    final dot = path.lastIndexOf('.');
    if (dot <= 0 || _find(null, path) >= 0) return (null, path);
    return (path.substring(0, dot), path.substring(dot + 1));
  }

  static String _unquote(String raw) =>
      raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')
      ? raw.substring(1, raw.length - 1)
      : raw;

  @override
  String? get(String path) {
    final (section, key) = _resolve(path);
    final index = _find(section, key);
    return index < 0 ? null : _unquote(_lines[index].rawValue);
  }

  @override
  void set(String path, Object? value) {
    if (value is List || value is Map) {
      throw ArgumentError.value(value, 'value', 'INI has no list values');
    }
    final text = renderPlain(value);
    final (section, key) = _resolve(path);
    final index = _find(section, key);
    if (index >= 0) {
      final line = _lines[index];
      if (_unquote(line.rawValue) == text) return;
      final quoted =
          line.rawValue.length >= 2 &&
          line.rawValue.startsWith('"') &&
          line.rawValue.endsWith('"');
      line.replaceValue(
        quoted
            ? '"$text"'
            : _needsQuotes(text)
            ? '"$text"'
            : text,
      );
      return;
    }
    _append(section, key, _needsQuotes(text) ? '"$text"' : text);
  }

  static bool _needsQuotes(String text) =>
      text.isNotEmpty && (text.trim() != text);

  void _append(String? section, String key, String text) {
    final eol = detectLineEnding(_lines);
    final sections = _sections();
    var after = -1;
    var found = section == null;
    var separator = ' = ';
    for (var i = 0; i < _lines.length; i++) {
      final inScope = sections[i] == section;
      if (_lines[i].section != null && _lines[i].section == section) {
        found = true;
        after = i;
      }
      if (inScope && _lines[i].isEntry) {
        after = i;
        separator = _lines[i].separator;
      }
    }
    if (section == null && after < 0) {
      // No top-level pair yet: go before the first section header, or to the
      // end of a file that has none.
      final header = _lines.indexWhere((l) => l.section != null);
      after = header < 0 ? _lines.length - 1 : header - 1;
    }
    if (!found) {
      final end = _lines.length - 1;
      if (end >= 0 && _lines[end].content.trim().isNotEmpty) {
        insertLineAfter(_lines, end, SourceLine('', ''), eol);
      } else if (end >= 0 && _lines[end].eol.isEmpty) {
        _lines[end].eol = eol;
      }
      final header = SourceLine('[$section]', '')..section = section;
      insertLineAfter(_lines, _lines.length - 1, header, eol);
      after = _lines.length - 1;
      _insertEntry(after, key, separator, text, eol);
      return;
    }
    _insertEntry(after, key, separator, text, eol);
  }

  void _insertEntry(
    int after,
    String key,
    String separator,
    String text,
    String eol,
  ) {
    final content = '$key$separator$text';
    final line = SourceLine(content, '')
      ..key = key
      ..keyEnd = key.length
      ..valueStart = key.length + separator.length
      ..valueEnd = content.length;
    insertLineAfter(_lines, after, line, eol);
  }

  @override
  void remove(String path) {
    final (section, key) = _resolve(path);
    final sections = _sections();
    final doomed = <SourceLine>{
      for (var i = 0; i < _lines.length; i++)
        if (_lines[i].key == key && sections[i] == section) _lines[i],
    };
    _lines.removeWhere(doomed.contains);
  }
}
