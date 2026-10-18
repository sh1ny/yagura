import 'dart:io';

/// The key under which a remote address is counted: IPv4 by address, IPv6 by
/// /64 (a host owns its whole prefix), an IPv4-mapped IPv6 address as the
/// IPv4 address inside it. Used by the pairing throttle and the listener's
/// connection limits.
String addressKey(InternetAddress? address) {
  if (address == null) return 'unknown';
  final raw = address.rawAddress;
  if (address.type == InternetAddressType.IPv6 && raw.length == 16) {
    final mapped =
        raw.sublist(0, 10).every((b) => b == 0) &&
        raw[10] == 0xff &&
        raw[11] == 0xff;
    if (mapped) return raw.sublist(12).join('.');
    return '${raw.sublist(0, 8).map((b) => b.toRadixString(16)).join(':')}/64';
  }
  return address.address;
}
