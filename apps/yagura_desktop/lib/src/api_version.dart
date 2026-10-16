/// API version handling and negotiation (daemon-protocol, "API version
/// negotiation").
library;

/// A `major.minor` API version as reported by `System.GetInfo`.
final class ApiVersion implements Comparable<ApiVersion> {
  const ApiVersion(this.major, this.minor);

  final int major;
  final int minor;

  /// Parses `"1.5"`; returns null for anything else.
  static ApiVersion? tryParse(String text) {
    if (text.split('.') case [final a, final b]) {
      final major = int.tryParse(a);
      final minor = int.tryParse(b);
      if (major != null && minor != null && major >= 0 && minor >= 0) {
        return ApiVersion(major, minor);
      }
    }
    return null;
  }

  @override
  int compareTo(ApiVersion other) =>
      major != other.major ? major - other.major : minor - other.minor;

  @override
  bool operator ==(Object other) =>
      other is ApiVersion && other.major == major && other.minor == minor;

  @override
  int get hashCode => Object.hash(major, minor);

  @override
  String toString() => '$major.$minor';
}

/// The API version this client implements. M1 speaks API 1.0: the services in
/// `proto/yagura/v1/` as of the first daemon. Raise the minor when the client
/// starts using a feature the daemon only has from that minor on.
const ApiVersion kClientApiVersion = ApiVersion(1, 0);

/// Outcome of comparing the client's version with the daemon's served ones.
sealed class Negotiation {
  const Negotiation();
}

/// A shared major exists. [daemonVersion] is the highest version the daemon
/// serves in that major; [effective] is the version to manage it over: the
/// shared major with the lower of the two minors. Features newer than it must
/// stay hidden.
final class Compatible extends Negotiation {
  const Compatible({required this.effective, required this.daemonVersion});

  final ApiVersion effective;
  final ApiVersion daemonVersion;

  /// Whether a feature introduced in [feature] may be used.
  bool supports(ApiVersion feature) =>
      feature.major == effective.major && feature.minor <= effective.minor;
}

/// No shared major; the client makes no further calls to this daemon.
final class Incompatible extends Negotiation {
  const Incompatible({required this.client, required this.daemon});

  final ApiVersion client;
  final List<ApiVersion> daemon;
}

/// The client supports the major of [client] and its minors up to
/// `client.minor`; [daemon] is every version the daemon serves.
Negotiation negotiate({
  required ApiVersion client,
  required Iterable<ApiVersion> daemon,
}) {
  final sameMajor = daemon.where((v) => v.major == client.major);
  if (sameMajor.isEmpty) {
    return Incompatible(client: client, daemon: daemon.toList()..sort());
  }
  final highest = sameMajor.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
  final minor = highest.minor < client.minor ? highest.minor : client.minor;
  return Compatible(
    effective: ApiVersion(client.major, minor),
    daemonVersion: highest,
  );
}
