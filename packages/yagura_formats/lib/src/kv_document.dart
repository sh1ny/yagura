import 'config_document.dart';
import 'source_lines.dart';

/// A `kv` config file: one `key value` or `key=value` pair per line, as used
/// by BattlEye's `BEServer_x64.cfg`.
///
/// Blank lines and lines starting with `//`, `#` or `;` are comments and are
/// kept as they are. Every pair keeps its own style, so `MaxPing 350`,
/// `MaxPing=350` and `MaxPing = 350` each survive an edit of their value. A
/// line with only a key is a flag whose value is the empty string.
///
/// Key paths are flat: the key itself, matched exactly (case-sensitive). When
/// a key appears more than once, [get] and [set] act on the last one and
/// [remove] drops all of them.
///
/// Values are plain text. [get] returns the rest of the line after the
/// separator, without trailing whitespace and without any unquoting, so
/// `MaxCreateVehiclePerInterval 72 1` reads as `'72 1'`. [set] writes a
/// `String` as is, a `num` or `bool` with `toString`, and a `List` as its
/// elements joined by spaces. A new key is appended in the file's own line
/// ending, using the separator of the last pair.
class KvDocument extends ConfigDocument {
  KvDocument._(this._lines, this._bom);

  /// Parses [source]; throws [ConfigParseException] with the line and column
  /// of a line that starts with `=`.
  factory KvDocument.parse(String source) {
    final bom = source.startsWith(bomChar);
    final lines = splitSourceLines(bom ? source.substring(1) : source);
    for (var i = 0; i < lines.length; i++) {
      _parseLine(lines[i], i + 1);
    }
    return KvDocument._(lines, bom);
  }

  static final _entry = RegExp(
    r'^([ \t]*)([^ \t=]+)([ \t]*=[ \t]*|[ \t]+|)(.*?)([ \t]*)$',
  );

  static void _parseLine(SourceLine line, int number) {
    final content = line.content;
    final trimmed = content.trimLeft();
    if (trimmed.isEmpty ||
        trimmed.startsWith('//') ||
        trimmed.startsWith('#') ||
        trimmed.startsWith(';')) {
      return;
    }
    final match = _entry.firstMatch(content);
    if (match == null) {
      throw ConfigParseException(
        'A line cannot start with "="',
        line: number,
        column: content.length - trimmed.length + 1,
      );
    }
    final lead = match.group(1)!.length;
    final key = match.group(2)!;
    final separator = match.group(3)!;
    final value = match.group(4)!;
    line
      ..key = key
      ..keyEnd = lead + key.length
      ..valueStart = lead + key.length + separator.length
      ..valueEnd = lead + key.length + separator.length + value.length;
  }

  final List<SourceLine> _lines;
  final bool _bom;

  @override
  String toSource() => '${_bom ? bomChar : ''}${_lines.join()}';

  int _indexOf(String key) => _lines.lastIndexWhere((l) => l.key == key);

  @override
  String? get(String path) {
    final index = _indexOf(path);
    return index < 0 ? null : _lines[index].rawValue;
  }

  @override
  void set(String path, Object? value) {
    final text = renderPlain(value);
    final index = _indexOf(path);
    if (index >= 0) {
      final line = _lines[index];
      if (line.rawValue == text) return;
      if (line.separator.isEmpty && text.isNotEmpty) {
        // A flag line has no separator yet.
        line.content =
            '${line.content.substring(0, line.keyEnd)} '
            '${line.content.substring(line.keyEnd)}';
        line
          ..valueStart += 1
          ..valueEnd += 1;
      }
      line.replaceValue(text);
      return;
    }
    final last = _lines.lastIndexWhere((l) => l.isEntry);
    final separator = last >= 0 && _lines[last].separator.isNotEmpty
        ? _lines[last].separator
        : ' ';
    final content = '$path$separator$text';
    final line = SourceLine(content, '')
      ..key = path
      ..keyEnd = path.length
      ..valueStart = path.length + separator.length
      ..valueEnd = content.length;
    insertLineAfter(_lines, _lines.length - 1, line, detectLineEnding(_lines));
  }

  @override
  void remove(String path) {
    _lines.removeWhere((l) => l.key == path);
  }
}
