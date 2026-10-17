import 'dart:io';

import '../errors.dart';

/// The default bind of dev mode (`daemon-security` spec).
const defaultDevBind = '127.0.0.1:7443';

/// Where the dev-mode listener binds.
class BindAddress {
  const BindAddress(this.address, this.port);

  final InternetAddress address;
  final int port;

  @override
  String toString() => '${address.address}:$port';
}

/// Parses `host:port` (`[::1]:7443` for IPv6) and checks that the daemon may
/// serve plaintext on it: a loopback address, or `localhost` when every
/// address it resolves to is loopback. Anything else fails
/// `dev_mode_requires_loopback`.
Future<BindAddress> parseDevBind(
  String bind, {
  Future<List<InternetAddress>> Function(String host) lookup =
      InternetAddress.lookup,
}) async {
  final (host, port) = _split(bind.trim());
  if (port < 0 || port > 65535) {
    throw _invalid(bind, 'the port of "$bind" is not between 0 and 65535');
  }

  final literal = InternetAddress.tryParse(host);
  if (literal != null) {
    if (!literal.isLoopback) throw _notLoopback(bind, [literal]);
    return BindAddress(literal, port);
  }
  final List<InternetAddress> resolved;
  try {
    resolved = await lookup(host);
  } on SocketException {
    throw _invalid(
      bind,
      'the bind host "$host" cannot be resolved, so it cannot be shown to be '
      'loopback',
    );
  }
  if (resolved.isEmpty || resolved.any((a) => !a.isLoopback)) {
    throw _notLoopback(bind, resolved);
  }
  // Prefer IPv4 so a client that tries one address finds the listener.
  final chosen = resolved.firstWhere(
    (a) => a.type == InternetAddressType.IPv4,
    orElse: () => resolved.first,
  );
  return BindAddress(chosen, port);
}

(String, int) _split(String bind) {
  if (bind.startsWith('[')) {
    final end = bind.indexOf(']');
    if (end < 0) throw _invalid(bind, 'unterminated "[" in "$bind"');
    final rest = bind.substring(end + 1);
    final port = rest.isEmpty ? 7443 : _port(bind, rest.substring(1));
    return (bind.substring(1, end), port);
  }
  final colon = bind.lastIndexOf(':');
  if (colon < 0) return (bind, 7443);
  if (bind.indexOf(':') != colon) {
    // A bare IPv6 address without brackets has no port.
    return (bind, 7443);
  }
  return (bind.substring(0, colon), _port(bind, bind.substring(colon + 1)));
}

int _port(String bind, String text) =>
    int.tryParse(text) ??
    (throw _invalid(bind, 'cannot read the port of "$bind"'));

YaguraException _invalid(String bind, String message) => YaguraException(
  'dev_mode_requires_loopback',
  '$message; use host:port, for example $defaultDevBind',
  details: {'bind': bind},
);

YaguraException _notLoopback(
  String bind,
  List<InternetAddress> resolved,
) => YaguraException(
  'dev_mode_requires_loopback',
  'dev mode serves plaintext, so it binds only to loopback addresses '
      '(127.0.0.1, ::1, or localhost); "$bind" '
      '${resolved.isEmpty ? 'resolves to nothing' : 'is or resolves to ${resolved.map((a) => a.address).join(', ')}'}',
  details: {'bind': bind},
);
