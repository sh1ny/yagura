import 'dart:convert';
import 'dart:io';

/// The last known size of each Steam app on this host, kept in a small JSON
/// file next to the SteamCMD installations. The disk check needs twice that
/// size free before a download starts.
class AppSizeStore {
  AppSizeStore(this.file);

  final File file;

  /// Last known size of [appId] in bytes, or null when never recorded.
  int? lastKnown(int appId) {
    final size = _read()['$appId'];
    return size is int ? size : null;
  }

  void record(int appId, int bytes) {
    final sizes = _read()..['$appId'] = bytes;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(sizes));
  }

  Map<String, Object?> _read() {
    try {
      return Map<String, Object?>.from(
        jsonDecode(file.readAsStringSync()) as Map,
      );
    } on Object {
      // Missing or damaged: the size is simply not known.
      return {};
    }
  }
}
