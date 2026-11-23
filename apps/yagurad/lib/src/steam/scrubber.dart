/// What replaces a secret in SteamCMD output (design D3).
const scrubbedMark = '***';

/// Masks the secrets of one SteamCMD run (the password and the Steam Guard
/// code it was given) in every line it prints, before the line goes to the
/// failure tail, the classifier, the operation's events or a log (design D3).
///
/// SteamCMD echoes its command line when asked and prints some arguments back
/// in its errors, so the masking happens at the single place the output
/// enters the daemon.
class Scrubber {
  Scrubber([Iterable<String> secrets = const []]) {
    for (final secret in secrets) {
      add(secret);
    }
  }

  /// A scrubber that masks nothing.
  static final none = Scrubber();

  final _secrets = <String>[];

  /// Starts masking [secret]. An empty value masks nothing.
  void add(String secret) {
    if (secret.isEmpty || _secrets.contains(secret)) return;
    _secrets
      ..add(secret)
      // The longest first, so a secret that contains another is masked whole.
      ..sort((a, b) => b.length.compareTo(a.length));
  }

  /// [text] with every secret replaced by [scrubbedMark].
  String scrub(String text) {
    var out = text;
    for (final secret in _secrets) {
      out = out.replaceAll(secret, scrubbedMark);
    }
    return out;
  }
}
