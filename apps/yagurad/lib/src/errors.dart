/// An operation failure carrying a stable reason code from the protocol's
/// reason list (`docs/protocol.md`), such as `sandbox_violation` or
/// `hook_timeout`.
class YaguraException implements Exception {
  YaguraException(this.reason, this.message, {this.details = const {}});

  /// Stable snake_case identifier.
  final String reason;

  /// Human-readable explanation naming the hook, path or limit involved.
  final String message;

  /// Structured context (`hook`, `path`, `format`, `stack`, ...).
  final Map<String, Object?> details;

  @override
  String toString() => 'YaguraException($reason): $message';
}
