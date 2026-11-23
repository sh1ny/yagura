/// The error code a parse failure reports to the user.
const configParseErrorCode = 'config_parse_error';

/// A config file that does not parse.
///
/// Carries the stable [code] `config_parse_error` and the 1-based [line] and
/// [column] of the problem, so a caller can name the file, line and column in
/// its own error. It is a [FormatException], so code that catches that type
/// keeps working.
class ConfigParseException implements FormatException {
  /// Creates an exception for a problem at [line] and [column] (both 1-based).
  ConfigParseException(
    this.message, {
    required this.line,
    required this.column,
    this.source,
    this.offset,
  });

  /// Creates an exception for a problem at [offset] in [source], working out
  /// the line and column from the text.
  factory ConfigParseException.atOffset(
    String message,
    String source,
    int offset,
  ) {
    final clamped = offset.clamp(0, source.length);
    var line = 1;
    var lineStart = 0;
    for (var i = 0; i < clamped; i++) {
      if (source.codeUnitAt(i) == 0x0A) {
        line++;
        lineStart = i + 1;
      }
    }
    return ConfigParseException(
      message,
      line: line,
      column: clamped - lineStart + 1,
      source: source,
      offset: clamped,
    );
  }

  /// The stable error code, always `config_parse_error`.
  String get code => configParseErrorCode;

  @override
  final String message;

  /// The 1-based line of the problem.
  final int line;

  /// The 1-based column of the problem.
  final int column;

  @override
  final dynamic source;

  @override
  final int? offset;

  @override
  String toString() => '$code: $message (line $line, column $column)';
}

/// The shared surface of the key/value document formats: read, set and remove
/// a value by key path, and write the document back losslessly.
///
/// A hook patch for these formats is a map from key path to value, where a
/// `null` value removes the key ([applyPatch]).
abstract class ConfigDocument {
  /// The document as text, identical to the parsed source if unedited.
  String toSource();

  /// The value at [path], or `null` when the key is missing.
  Object? get(String path);

  /// Sets the value at [path], adding the key when it is missing.
  ///
  /// Setting a value equal to the current one leaves the source untouched.
  void set(String path, Object? value);

  /// Removes the key at [path]; does nothing when it is missing.
  void remove(String path);

  /// Applies [patch], a map from key path to new value, where `null` removes
  /// the key.
  void applyPatch(Map<String, Object?> patch) {
    for (final MapEntry(:key, :value) in patch.entries) {
      if (value == null) {
        remove(key);
      } else {
        set(key, value);
      }
    }
  }
}
