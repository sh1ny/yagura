import 'dart:async';

import 'package:path/path.dart' as p;

import '../admin/admin_client.dart';
import '../admin/admin_transport.dart';
import '../errors.dart';

const _usagePair = 'usage: yagurad pair [--address <host>[:<port>]]';
const _usageDevices = 'usage: yagurad devices list | revoke <device>';
const _usageStatus = 'usage: yagurad status';
const _usageRoots = 'usage: yagurad roots add <path> | remove <path> | list';

const _exitFailure = 1;
const _exitUsage = 64;

/// The host commands `pair`, `devices`, `status` and `roots`, which talk to
/// the running service over the admin channel and never open the database.
/// Returns the process exit code.
Future<int> runAdminCommand(
  String command,
  List<String> arguments, {
  required AdminConnector connector,
  required StringSink out,
  required StringSink err,
}) async {
  final client = AdminClient(connector);

  Future<int> run(
    String name,
    Map<String, Object?> args,
    void Function(Map<String, Object?> result) show,
  ) async {
    try {
      show(await client.call(name, args));
      return 0;
    } on YaguraException catch (e) {
      err.writeln('yagurad: ${e.reason}: ${e.message}');
      return _exitFailure;
    }
  }

  int usage(String text) {
    err.writeln(text);
    return _exitUsage;
  }

  switch (command) {
    case 'pair':
      String? address;
      if (arguments.length == 2 && arguments[0] == '--address') {
        address = arguments[1];
      } else if (arguments.length == 1 &&
          arguments[0].startsWith('--address=')) {
        address = arguments[0].substring('--address='.length);
      } else if (arguments.isNotEmpty) {
        return usage(_usagePair);
      }
      return run('pair', {'address': ?address}, (result) {
        out
          ..writeln(result['pairing_string'])
          ..writeln(
            'The code is valid until ${result['expires_at']} and replaces '
            'any earlier one.',
          );
      });
    case 'devices':
      switch (arguments) {
        case ['list']:
          return run('devices.list', {}, (result) {
            final devices = (result['devices']! as List)
                .cast<Map<String, Object?>>();
            if (devices.isEmpty) out.writeln('no devices');
            for (final d in devices) {
              out.writeln(
                [
                  d['id'],
                  d['name'],
                  d['state'],
                  if ('${d['last_seen_at']}'.isNotEmpty)
                    'last seen ${d['last_seen_at']}',
                  if ('${d['revoked_by']}'.isNotEmpty)
                    'revoked by ${d['revoked_by']}',
                ].join('  '),
              );
            }
          });
        case ['revoke', final device]:
          return run('devices.revoke', {'device': device}, (result) {
            out.writeln('revoked device ${result['name']} (${result['id']})');
          });
      }
      return usage(_usageDevices);
    case 'status':
      if (arguments.isNotEmpty) return usage(_usageStatus);
      return run('status', {}, (result) {
        for (final MapEntry(:key, :value) in result.entries) {
          out.writeln('$key: $value');
        }
      });
    case 'roots':
      switch (arguments) {
        case ['list']:
          return run('roots.list', {}, (result) {
            for (final r
                in (result['roots']! as List).cast<Map<String, Object?>>()) {
              out.writeln(
                r['default'] == true ? '${r['path']}  (default)' : r['path'],
              );
            }
          });
        case ['add', final path]:
          final absolute = p.normalize(p.absolute(path));
          return run('roots.add', {'path': absolute}, (result) {
            out.writeln('added instance root ${result['path']}');
          });
        case ['remove', final path]:
          final absolute = p.normalize(p.absolute(path));
          return run('roots.remove', {'path': absolute}, (result) {
            out.writeln('removed instance root ${result['path']}');
          });
      }
      return usage(_usageRoots);
  }
  return usage('yagurad: unknown command "$command"');
}
