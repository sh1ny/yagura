import 'dart:async';
import 'dart:io';

import '../errors.dart';
import '../instances/instance.dart';
import '../instances/instance_manager.dart';
import '../instances/instance_roots.dart';
import '../security/devices.dart';
import '../security/security.dart';
import 'admin_wire.dart';

/// The name the audit log records for what an administrator does on the host.
const hostAdminName = 'host-admin';

final _host = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$');

/// What the admin commands do inside the daemon (design D5).
///
/// The commands that change something (`pair`, `devices.revoke`,
/// `roots.add`, `roots.remove`) are audited as [hostAdminName], with the
/// reason when they are refused. Reading commands are not audited.
class AdminService {
  AdminService({
    required this.security,
    required this.roots,
    required this.instances,
    required this.apiPort,
    required this.status,
    Future<List<InternetAddress>> Function()? hostAddresses,
  }) : hostAddresses = hostAddresses ?? _interfaces;

  final DaemonSecurity security;
  final HostRoots roots;
  final InstanceManager instances;
  final int Function() apiPort;

  /// The facts about the daemon that only it knows (mode, data directory).
  final Map<String, Object?> Function() status;
  final Future<List<InternetAddress>> Function() hostAddresses;

  Future<Map<String, Object?>> handle(AdminRequest request) async {
    final args = request.args;
    switch (request.command) {
      case 'pair':
        return _audited('pair', '', () => _pair(args));
      case 'devices.list':
        return _devices();
      case 'devices.revoke':
        final target = _Target(_string(args, 'device'));
        return _audited('devices.revoke', target, () => _revoke(target));
      case 'status':
        return _status();
      case 'ports.check':
        return _checkPort(args['port']);
      case 'roots.list':
        return _roots();
      case 'roots.add':
        final path = _string(args, 'path');
        return _audited('roots.add', path, () {
          roots.add(path);
          return {'path': path};
        });
      case 'roots.remove':
        final path = _string(args, 'path');
        return _audited('roots.remove', path, () {
          roots.remove(path, instances: _rooted());
          return {'path': path};
        });
    }
    throw YaguraException(
      'admin_request_invalid',
      'unknown command "${request.command}"',
    );
  }

  static String _string(Map<String, Object?> args, String name) {
    final value = args[name];
    if (value is String && value.isNotEmpty) return value;
    throw YaguraException(
      'admin_request_invalid',
      'the argument "$name" is missing',
    );
  }

  Future<Map<String, Object?>> _audited(
    String command,
    Object target,
    FutureOr<Map<String, Object?>> Function() body,
  ) async {
    String targetText() => target is _Target ? target.text : '$target';
    void record(String result) => security.audit.record(
      deviceId: hostAdminName,
      address: '',
      method: 'admin/$command',
      target: targetText(),
      result: result,
    );
    final Map<String, Object?> result;
    try {
      result = await body();
    } on YaguraException catch (e) {
      record(e.reason);
      rethrow;
    } on Object {
      record('internal_error');
      rethrow;
    }
    record('ok');
    return result;
  }

  // ---- pair ---------------------------------------------------------------

  Future<Map<String, Object?>> _pair(Map<String, Object?> args) async {
    final (host, port) = await _address(args['address']);
    final issued = security.pairing.issueCode();
    final name = Uri.encodeComponent(Platform.localHostname);
    return {
      'pairing_string':
          'yagura://$host:$port?code=${issued.code}'
          '&ca=sha256:${security.identity.caFingerprint}&name=$name',
      'expires_at': issued.expiresAt.toUtc().toIso8601String(),
    };
  }

  /// The host and port to put in the pairing string.
  Future<(String, int)> _address(Object? option) async {
    if (option is String) {
      final parts = option.split(':');
      final port = parts.length == 2 ? int.tryParse(parts[1]) : null;
      if (parts.length > 2 ||
          !_host.hasMatch(parts[0]) ||
          (parts.length == 2 && (port == null || port < 1 || port > 65535))) {
        throw YaguraException(
          'admin_request_invalid',
          '--address wants <host> or <host>:<port>, got "$option"',
        );
      }
      return (parts[0], port ?? apiPort());
    }
    for (final address in await hostAddresses()) {
      if (address.type == InternetAddressType.IPv4 && !address.isLoopback) {
        return (address.address, apiPort());
      }
    }
    throw YaguraException(
      'address_required',
      'this host has no address to put in the pairing string; pass '
          '--address <host>[:<port>]',
    );
  }

  // ---- devices ------------------------------------------------------------

  Map<String, Object?> _devices() => {
    'devices': [
      for (final d in security.devices.list())
        {
          'id': d.id,
          'name': d.name,
          'state': d.revoked ? 'revoked' : 'active',
          'enrolled_at': d.enrolledAt.toUtc().toIso8601String(),
          'last_seen_at': d.lastSeenAt?.toUtc().toIso8601String() ?? '',
          'last_address': d.lastAddress,
          'revoked_by': d.revokedBy,
        },
    ],
  };

  Map<String, Object?> _revoke(_Target target) {
    final device = _resolve(target.text);
    target.text = device.id;
    final revoked = security.revokeDevice(device.id, hostAdminName);
    return {'id': revoked.id, 'name': revoked.name};
  }

  // A device by id, else the one active device of that name. Unlike a
  // device revoking another, the host may revoke the last one.
  DeviceRecord _resolve(String given) {
    final all = security.devices.list();
    for (final d in all) {
      if (d.id == given) return d;
    }
    final named = [
      for (final d in all)
        if (!d.revoked && d.name == given) d,
    ];
    if (named.length == 1) return named.single;
    if (named.isEmpty) {
      throw YaguraException(
        'device_not_found',
        'no active device is named or has the id "$given"',
        details: {'device': given},
      );
    }
    throw YaguraException(
      'device_ambiguous',
      'several devices are named "$given"; use one of the ids: '
          '${named.map((d) => d.id).join(', ')}',
      details: {
        'device': given,
        'ids': [for (final d in named) d.id],
      },
    );
  }

  // ---- roots --------------------------------------------------------------

  Map<String, Object?> _roots() => {
    'roots': [
      for (final r in roots.list())
        {
          'path': r.path,
          'default': r.isDefault,
          'added_at': r.addedAt?.toUtc().toIso8601String() ?? '',
        },
    ],
  };

  List<RootedInstance> _rooted() => [
    for (final i in instances.list())
      (id: i.id, name: i.name, directory: i.directory),
  ];

  // ---- status -------------------------------------------------------------

  Map<String, Object?> _status() => {
    ...status(),
    'api_port': apiPort(),
    'devices': security.devices.activeCount,
    'instances': instances.list().length,
    // Whoever uninstalls the service and its accounts needs these stopped
    // (every state in which a process of a service account may run).
    'running_servers': [
      for (final i in instances.list())
        if (_serverStates.contains(i.state)) i.name,
    ],
  };

  static const _serverStates = {
    InstanceState.installing,
    InstanceState.running,
    InstanceState.starting,
    InstanceState.stopping,
    InstanceState.updating,
  };

  /// `service configure` asks whether [port] can be the API port: no
  /// instance may use it (the daemon applies the same rule to its own port).
  Map<String, Object?> _checkPort(Object? port) {
    if (port is! int || port < 1 || port > 65535) {
      throw YaguraException(
        'admin_request_invalid',
        'the argument "port" wants a number from 1 to 65535',
      );
    }
    for (final instance in instances.list()) {
      for (final used in instance.ports) {
        if (used.number == port) {
          throw YaguraException(
            'port_conflict',
            'port ${used.name} of "${instance.name}" uses $port, so it '
                'cannot be the API port',
            details: {
              'port': port,
              'conflictingInstance': instance.name,
              'conflictingInstanceId': instance.id,
              'conflictingPortName': used.name,
            },
          );
        }
      }
    }
    return {};
  }

  static Future<List<InternetAddress>> _interfaces() async => [
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4))
      ...i.addresses,
  ];
}

/// A target that the command fills in once it knows it.
class _Target {
  _Target(this.text);

  String text;
}
