import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../errors.dart';
import '../version.dart';
import 'install_layout.dart';
import 'winsw_config.dart';

/// The bundle `yagurad service install` installs: the directory that holds
/// `bin/yagurad.exe`, `lib/` and `winsw/` (WinSW and its configuration
/// template).
class Bundle {
  const Bundle({required this.root, required this.version});

  /// The bundle the running executable belongs to. Fails `bundle_invalid`
  /// when the executable is not `<bundle>\bin\yagurad.exe` (under
  /// `dart run` it is the Dart VM).
  ///
  /// The version is [daemonVersion], or the content of a `VERSION` file in
  /// the bundle root when there is one: the packaging step that assembles the
  /// bundle can name the release it is.
  factory Bundle.running({String? executable}) {
    final exe = executable ?? Platform.resolvedExecutable;
    final bin = p.dirname(exe);
    if (p.basename(exe).toLowerCase() != 'yagurad.exe' ||
        p.basename(bin).toLowerCase() != 'bin') {
      throw YaguraException(
        'bundle_invalid',
        'service install runs from an extracted bundle, as '
            '<bundle>\\bin\\yagurad.exe; this is $exe',
      );
    }
    final root = p.dirname(bin);
    var version = daemonVersion;
    final file = File(p.join(root, 'VERSION'));
    if (file.existsSync()) {
      version = file.readAsStringSync().trim();
      if (!isVersionName(version)) {
        throw YaguraException(
          'bundle_invalid',
          'the VERSION file of the bundle holds "$version", not a version '
              'such as 1.2.3',
        );
      }
    }
    return Bundle(root: root, version: version);
  }

  final String root;
  final String version;

  String get winswExecutable => p.join(root, 'winsw', 'WinSW.NET461.exe');
  String get winswTemplate => p.join(root, 'winsw', 'yagurad.xml.template');

  /// Fails `bundle_invalid` unless the bundle holds the pinned WinSW and the
  /// template.
  void validate() {
    final winsw = File(winswExecutable);
    if (!winsw.existsSync() || !File(winswTemplate).existsSync()) {
      throw YaguraException(
        'bundle_invalid',
        'the bundle at $root lacks winsw\\WinSW.NET461.exe or '
            'winsw\\yagurad.xml.template',
      );
    }
    final actual = sha256.convert(winsw.readAsBytesSync()).toString();
    if (actual != winswSha256) {
      throw YaguraException(
        'bundle_invalid',
        'winsw\\WinSW.NET461.exe in the bundle is not WinSW $winswVersion '
            '(SHA-256 $winswSha256, found $actual)',
      );
    }
  }

  /// Copies the bundle, without `winsw/`, to [destination].
  void copyTo(String destination) {
    final base = Directory(root);
    for (final entity in base.listSync(recursive: true, followLinks: false)) {
      final relative = p.relative(entity.path, from: root);
      if (p.split(relative).first == 'winsw') continue;
      final target = p.join(destination, relative);
      if (entity is Directory) {
        Directory(target).createSync(recursive: true);
      } else if (entity is File) {
        Directory(p.dirname(target)).createSync(recursive: true);
        entity.copySync(target);
      }
    }
  }

  String readTemplate() => File(winswTemplate).readAsStringSync();
}
