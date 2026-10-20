import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';

import '../support/admin_support.dart';
import '../support/daemon_support.dart';

void main() {
  test('valid_instance_created', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();

    final instance = await createValheim(daemon, name: 'Friends');

    expect(instance.id, isNotEmpty);
    expect(instance.state, InstanceState.notInstalled);
    expect(instance.pluginId, 'valheim');
    expect(instance.settings['serverName'], 'Friends');
    expect(instance.settings['worldName'], 'Dedicated'); // the default
    expect(instance.portNumbers, {'game': 2456, 'query': 2457});
    expect(instance.directory, p.join(env.data, 'instances', instance.id));
    expect(Directory(instance.directory).existsSync(), isTrue);
    expect(daemon.instances.get(instance.id).name, 'Friends');
  });

  test('setting_violates_the_schema', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final tooLong = 'x' * 65; // serverName allows at most 64 characters

    await expectLater(
      createValheim(daemon, settings: {'serverName': tooLong}),
      failsWith(
        'settings_invalid',
        messageHas: ['serverName'],
        details: {
          'fieldViolations': [
            {'field': 'serverName', 'description': 'length must be at most 64'},
          ],
        },
      ),
    );

    expect(daemon.instances.list(), isEmpty);
    expect(Directory(p.join(env.data, 'instances')).listSync(), isEmpty);
  });

  test('directory_outside_the_instance_roots', () async {
    final env = TestEnv();
    env.installValheim();
    final acl = FakeAclWriter();
    final daemon = await env.start(aclWriter: acl);
    final outside = p.join(env.root.path, 'elsewhere');
    // An administrator configured one root with `yagurad roots add`.
    final root = Directory(p.join(env.root.path, 'servers'))..createSync();
    daemon.roots.add(root.path);
    final writes = acl.calls.length;

    for (final directory in [
      outside,
      r'D:\',
      env.data,
      root.path, // the root itself is not an instance directory
      '${root.path}-sibling',
      p.join(root.path, '..', 'elsewhere'), // leaves the root by '..'
    ]) {
      await expectLater(
        createValheim(daemon, directory: directory),
        failsWith('directory_not_allowed'),
        reason: directory,
      );
    }

    expect(Directory(outside).existsSync(), isFalse);
    expect(Directory('${root.path}-sibling').existsSync(), isFalse);
    expect(daemon.instances.list(), isEmpty);
    // A refusal changes no ACL.
    expect(acl.calls, hasLength(writes));
    // The configured root is the one place besides the default.
    final inside = await createValheim(
      daemon,
      directory: p.join(root.path, 'valheim-main'),
    );
    expect(inside.directory, p.join(root.path, 'valheim-main'));
  });

  test('port_equal_to_the_daemon_api_port', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start(port: 50051);

    await expectLater(
      createValheim(daemon, ports: {'game': 50051}),
      failsWith(
        'port_conflict',
        messageHas: ['daemon API'],
        details: {'port': 50051},
      ),
    );

    expect(daemon.instances.list(), isEmpty);
  });

  test('port_collision_with_another_instance', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    await createValheim(daemon, name: 'First');

    await expectLater(
      createValheim(daemon, name: 'Second'),
      failsWith(
        'port_conflict',
        messageHas: ['First', '2456'],
        details: {'port': 2456, 'conflictingInstance': 'First'},
      ),
    );

    expect(daemon.instances.list().map((i) => i.name), ['First']);
  });

  test('directory_under_the_instance_root_is_accepted', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final directory = p.join(env.data, 'instances', 'mine');

    final instance = await createValheim(daemon, directory: directory);

    expect(instance.directory, directory);
    expect(Directory(directory).existsSync(), isTrue);
    await expectLater(
      createValheim(
        daemon,
        name: 'Other',
        ports: {'game': 3000},
        directory: p.join(directory, 'nested'),
      ),
      failsWith('directory_not_allowed'),
    );
  });

  test('concurrent_creates_are_serialised', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();

    final results = await Future.wait([
      for (var i = 0; i < 3; i++)
        createValheim(
          daemon,
          name: 'Same $i',
        ).then<Object>((instance) => instance, onError: (Object e) => e),
    ]);

    // All three use the default ports: exactly one wins.
    expect(results.whereType<Instance>(), hasLength(1));
    expect(daemon.instances.list(), hasLength(1));
  });

  test('reload_stores_defaults_of_fields_a_plugin_added', () async {
    final env = TestEnv();
    env.installValheim();
    final daemon = await env.start();
    final instance = await createValheim(daemon);
    expect(instance.settings, isNot(contains('motd')));

    env.editValheim(
      '  password:\n    type: secret',
      '  motd:\n    type: string\n    label: Message\n    default: hello\n'
          '  password:\n    type: secret',
    );
    await daemon.instances.reloadPlugins();

    expect(daemon.instances.get(instance.id).settings['motd'], 'hello');
    final file = File(p.join(instance.directory, 'instance.json'));
    expect(file.readAsStringSync(), contains('hello'));
  });
}
