import 'dart:io';

import 'package:path/path.dart' as p;

/// The service name `yagurad service install` registers.
const defaultServiceName = 'yagurad';

/// The marker file inside a version directory made by an install.
const installMarkerName = '.yagura-install';

final _versionName = RegExp(r'^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$');

/// Whether [name] names a version directory (`0.1.0`, `1.2.3-rc.1`).
bool isVersionName(String name) => _versionName.hasMatch(name);

/// Orders two versions: negative when [a] is older than [b]. The numeric
/// core decides first; a pre-release is older than its release.
int compareVersions(String a, String b) {
  List<int> core(String v) => [
    for (final part in v.split('-').first.split('.')) int.tryParse(part) ?? 0,
  ];
  final x = core(a);
  final y = core(b);
  for (var i = 0; i < 3; i++) {
    final c = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (c != 0) return c;
  }
  final preA = a.contains('-') ? a.substring(a.indexOf('-') + 1) : null;
  final preB = b.contains('-') ? b.substring(b.indexOf('-') + 1) : null;
  if (preA == null && preB == null) return 0;
  if (preA == null) return 1;
  if (preB == null) return -1;
  return preA.compareTo(preB);
}

/// Where a service installation lives (design D6):
///
/// ```text
/// <root>\<service>.exe        the WinSW wrapper
/// <root>\<service>.xml        its configuration
/// <root>\<version>\bin\yagurad.exe   one copy of the bundle per version
/// <root>\logs\                the wrapper's log
/// ```
class InstallLayout {
  const InstallLayout({
    required this.root,
    this.serviceName = defaultServiceName,
  });

  /// `%ProgramFiles%\Yagura`, with [environment] standing in for the process
  /// environment in tests.
  factory InstallLayout.standard({
    String serviceName = defaultServiceName,
    required Map<String, String> environment,
  }) => InstallLayout(
    root: p.join(environment['ProgramFiles'] ?? r'C:\Program Files', 'Yagura'),
    serviceName: serviceName,
  );

  final String root;
  final String serviceName;

  String get winswExecutable => p.join(root, '$serviceName.exe');
  String get configFile => p.join(root, '$serviceName.xml');
  String get logDirectory => p.join(root, 'logs');

  String versionDirectory(String version) => p.join(root, version);

  /// The file that says a version directory was made by this service's
  /// install (it holds the service name). The sweeper and uninstall delete
  /// only version directories that carry it: the install root may be shared
  /// with another service or hold other software's versioned folders.
  String markerFile(String version) =>
      p.join(versionDirectory(version), installMarkerName);

  /// Records that this service's install owns the version directory.
  void markVersionDirectory(String version) =>
      File(markerFile(version)).writeAsStringSync(serviceName);

  /// Whether the version directory carries this service's marker.
  bool ownsVersionDirectory(String version) {
    final marker = File(markerFile(version));
    try {
      return marker.existsSync() &&
          marker.readAsStringSync().trim() == serviceName;
    } on FileSystemException {
      return false;
    }
  }

  /// The service named in the marker of the version directory, or null when
  /// there is no marker.
  String? markerOwner(String version) {
    final marker = File(markerFile(version));
    try {
      return marker.existsSync() ? marker.readAsStringSync().trim() : null;
    } on FileSystemException {
      return null;
    }
  }

  /// Deletes the version directory. When a file in it cannot be deleted (a
  /// relay executes from it), the directory stays with its marker, so that it
  /// is still known to be this service's; the failure is rethrown.
  void deleteVersionDirectory(String version) {
    final directory = Directory(versionDirectory(version));
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // The recursive delete may have removed the marker before it failed.
      if (directory.existsSync() && markerOwner(version) == null) {
        try {
          markVersionDirectory(version);
        } on FileSystemException {
          // Best effort: without it the directory is left alone for good.
        }
      }
      rethrow;
    }
  }

  String executable(String version) =>
      p.join(versionDirectory(version), 'bin', 'yagurad.exe');

  /// The layout of an installation that holds [executable]
  /// (`<root>\<version>\bin\yagurad.exe`), with that version; null when the
  /// executable is not in a version directory (a dev build, `dart run`).
  static (InstallLayout, String)? containing(String executable) {
    final bin = p.dirname(executable);
    final version = p.dirname(bin);
    if (p.basename(bin).toLowerCase() != 'bin' ||
        p.basename(executable).toLowerCase() != 'yagurad.exe' ||
        !isVersionName(p.basename(version))) {
      return null;
    }
    return (InstallLayout(root: p.dirname(version)), p.basename(version));
  }
}
