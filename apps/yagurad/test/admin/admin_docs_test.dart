import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The operator notes that document the admin CLI (task 7.4).
const operatorDoc = '../../docs/data-directory.md';

/// The sources that decide what the admin commands can print: the commands,
/// the channel and the roots.
const _sources = [
  'lib/src/admin',
  'lib/src/cli/admin_commands.dart',
  'lib/src/instances/instance_roots.dart',
];

/// Reasons the daemon relays from other components when an admin command
/// reaches them.
const _relayed = ['device_not_found', 'device_name_invalid'];

final _emitter = RegExp(r"YaguraException\(\s*'([a-z][a-z0-9_]*)'");

Set<String> reasonsOfTheAdminCommands() {
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
  final doc = File(operatorDoc).readAsStringSync();

  test('every_admin_command_is_in_the_operator_doc', () {
    for (final command in [
      'yagurad pair',
      'yagurad pair --address',
      'yagurad devices list',
      'yagurad devices revoke',
      'yagurad status',
      'yagurad roots add',
      'yagurad roots remove',
      'yagurad roots list',
    ]) {
      expect(doc, contains('`$command'), reason: command);
    }
  });

  test('every_reason_an_admin_command_can_print_is_in_the_operator_doc', () {
    final reasons = reasonsOfTheAdminCommands();

    expect(
      reasons,
      containsAll([
        'daemon_not_running',
        'access_denied',
        'elevation_required',
        'admin_channel_untrusted',
        'admin_channel_squatted',
        'root_not_protected',
        'root_in_use',
      ]),
      reason: 'the scan finds the reasons of the design',
    );
    expect(
      [
        for (final reason in reasons)
          if (!doc.contains('`$reason`')) reason,
      ],
      isEmpty,
      reason: 'add these to the admin commands section of $operatorDoc',
    );
  });
}
