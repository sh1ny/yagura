import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The install guide (task 8.3).
const installDoc = '../../docs/install.md';

/// The sources that decide what `yagurad service` can print.
const _sources = ['lib/src/service', 'lib/src/cli/service_command.dart'];

/// Reasons these commands relay from other components.
const _relayed = [
  'elevation_required',
  'port_conflict',
  'bind_invalid',
  // The admin channel (data-directory.md) as `configure`, `status`, the
  // readiness wait and the purge probe see it.
  'access_denied',
  'admin_channel_untrusted',
  'admin_channel_busy',
  'admin_request_timeout',
  'admin_connection_closed',
  'admin_api_unsupported',
];

final _emitter = RegExp(r"YaguraException\(\s*'([a-z][a-z0-9_]*)'");

Set<String> reasonsOfTheServiceCommands() {
  final found = <String>{..._relayed};
  for (final source in _sources) {
    final files = FileSystemEntity.isDirectorySync(source)
        ? Directory(source).listSync(recursive: true).whereType<File>()
        : [File(source)];
    for (final file in files) {
      if (p.extension(file.path) != '.dart') continue;
      for (final match in _emitter.allMatches(file.readAsStringSync())) {
        found.add(match[1]!);
      }
    }
  }
  return found;
}

void main() {
  final doc = File(installDoc).readAsStringSync();

  test('every_service_command_is_in_the_install_guide', () {
    for (final command in [
      'yagurad service install',
      'yagurad service install --bind',
      'yagurad service install --service-name',
      'yagurad service configure --bind',
      'yagurad service status',
      'yagurad service uninstall',
      'yagurad service uninstall --purge-accounts',
      'yagurad pair',
      'Restart-Service yagurad',
    ]) {
      expect(doc, contains(command), reason: command);
    }
  });

  test('every_reason_a_service_command_can_print_is_in_the_install_guide', () {
    final reasons = reasonsOfTheServiceCommands();

    expect(
      reasons,
      containsAll([
        'service_exists',
        'service_not_installed',
        'servers_running',
        'bundle_invalid',
        'elevation_required',
      ]),
      reason: 'the scan finds the reasons of the design',
    );
    expect(
      [
        for (final reason in reasons)
          if (!doc.contains('`$reason`')) reason,
      ],
      isEmpty,
      reason: 'add these to the reasons table of $installDoc',
    );
  });

  test('the_guide_names_the_pinned_wrapper_version', () {
    final readme = File('../../tool/winsw/README.md').readAsStringSync();
    expect(readme, contains('2.12.0'));
    expect(doc, contains('2.12.0'));
  });
}
