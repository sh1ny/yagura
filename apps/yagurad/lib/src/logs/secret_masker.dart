/// Replaces an instance's secret values in a log line with `***` (design D11).
///
/// A value of [substringLength] or more characters is replaced wherever it
/// occurs; a shorter one only as a whole word, so a 4-character secret does
/// not blank out every word that happens to contain it.
class SecretMasker {
  SecretMasker(Iterable<String> secrets) : _pattern = _build(secrets);

  /// A masker that changes nothing.
  static final none = SecretMasker(const []);

  /// What a secret becomes.
  static const replacement = '***';

  /// The shortest value that is matched inside a word.
  static const substringLength = 6;

  final RegExp? _pattern;

  bool get isEmpty => _pattern == null;

  /// [line] with every secret replaced.
  String mask(String line) {
    final pattern = _pattern;
    return pattern == null ? line : line.replaceAll(pattern, replacement);
  }

  static const _wordChar = r'[\p{L}\p{N}_]';

  static RegExp? _build(Iterable<String> secrets) {
    // Longest first, so a secret that contains another is replaced whole.
    final values = {
      for (final value in secrets)
        if (value.isNotEmpty) value,
    }.toList()..sort((a, b) => b.length.compareTo(a.length));
    if (values.isEmpty) return null;
    String alternatives(Iterable<String> items) =>
        items.map(RegExp.escape).join('|');
    final long = values.where((v) => v.length >= substringLength);
    final short = values.where((v) => v.length < substringLength);
    return RegExp(
      [
        if (long.isNotEmpty) '(?:${alternatives(long)})',
        if (short.isNotEmpty)
          '(?<!$_wordChar)(?:${alternatives(short)})(?!$_wordChar)',
      ].join('|'),
      unicode: true,
    );
  }
}
