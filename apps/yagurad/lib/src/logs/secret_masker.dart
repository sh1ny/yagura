/// Replaces an instance's secret values in a log line with `***` (design D11).
///
/// A value of [substringLength] or more characters is replaced wherever it
/// occurs; a shorter one only as a whole word, so a 4-character secret does
/// not blank out every word that happens to contain it.
class SecretMasker {
  SecretMasker(Iterable<String> secrets)
    : _pattern = _build(secrets),
      _withhold = false;

  const SecretMasker._withholding() : _pattern = null, _withhold = true;

  /// A masker that changes nothing.
  static final none = SecretMasker(const []);

  /// A masker that replaces every line with [withheld].
  static const withholding = SecretMasker._withholding();

  /// What a secret becomes.
  static const replacement = '***';

  /// What a whole line becomes when its instance's secrets cannot be read
  /// and no masker was built before.
  static const withheld =
      '[line withheld: the secrets to mask could not be read]';

  /// The shortest value that is matched inside a word.
  static const substringLength = 6;

  final RegExp? _pattern;
  final bool _withhold;

  bool get isEmpty => _pattern == null && !_withhold;

  /// [line] with every secret replaced.
  String mask(String line) {
    if (_withhold) return withheld;
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
