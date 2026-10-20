/// The byte order mark, as it appears in a decoded string.
const bomChar = '﻿';

/// One line of a source text: its [content] without the line ending, and the
/// line ending itself ([eol] is `\n`, `\r\n`, or empty for a final line with
/// no terminator).
///
/// A line that holds a `key value` pair also records where the key and the
/// value sit inside [content], so the value can be replaced without touching
/// the rest of the line.
class SourceLine {
  SourceLine(this.content, this.eol);

  String content;
  String eol;

  /// The section name when this line is an INI section header.
  String? section;

  /// The key when this line is a key/value entry.
  String? key;

  /// Where the key ends and the value starts and ends inside [content].
  int keyEnd = 0;
  int valueStart = 0;
  int valueEnd = 0;

  bool get isEntry => key != null;

  /// The raw value text of an entry line.
  String get rawValue => content.substring(valueStart, valueEnd);

  /// The text between the key and the value (`' = '`, `'='`, `' '`).
  String get separator => content.substring(keyEnd, valueStart);

  /// Replaces the raw value text of an entry line.
  void replaceValue(String text) {
    content =
        content.substring(0, valueStart) + text + content.substring(valueEnd);
    valueEnd = valueStart + text.length;
  }

  @override
  String toString() => '$content$eol';
}

/// Splits [text] into lines, remembering each line ending.
List<SourceLine> splitSourceLines(String text) {
  final lines = <SourceLine>[];
  var start = 0;
  while (start < text.length) {
    final nl = text.indexOf('\n', start);
    if (nl < 0) {
      lines.add(SourceLine(text.substring(start), ''));
      break;
    }
    final crlf = nl > start && text.codeUnitAt(nl - 1) == 0x0D;
    lines.add(
      SourceLine(
        text.substring(start, crlf ? nl - 1 : nl),
        crlf ? '\r\n' : '\n',
      ),
    );
    start = nl + 1;
  }
  return lines;
}

/// The line ending the file uses: the last terminator found, else `\n`.
String detectLineEnding(List<SourceLine> lines) {
  for (var i = lines.length - 1; i >= 0; i--) {
    if (lines[i].eol.isNotEmpty) return lines[i].eol;
  }
  return '\n';
}

/// Appends [line] after the line at [index] (or at the start when [index] is
/// -1), keeping a missing final line ending missing.
void insertLineAfter(
  List<SourceLine> lines,
  int index,
  SourceLine line,
  String eol,
) {
  if (index >= 0 && lines[index].eol.isEmpty) {
    // The previous line was the unterminated last line: terminate it and leave
    // the new last line unterminated, as the file was.
    lines[index].eol = eol;
    line.eol = '';
  } else {
    line.eol = eol;
  }
  lines.insert(index + 1, line);
}

/// Renders a scalar for a plain-text config value.
String renderPlain(Object? value) => switch (value) {
  null => throw ArgumentError.notNull('value'),
  String() => value,
  num() || bool() => value.toString(),
  List() => value.map(renderPlain).join(' '),
  _ => throw ArgumentError.value(value, 'value', 'unsupported value type'),
};
