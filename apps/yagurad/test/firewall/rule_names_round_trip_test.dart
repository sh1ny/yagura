import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';
// The schema constant is the one definition of what a port name may be.
// ignore: implementation_imports
import 'package:yagura_plugin/src/manifest_schema.g.dart' show manifestSchemaV1;
import 'package:yagurad/src/firewall/firewall_backend.dart';
import 'package:yagurad/src/firewall/rule_names.dart';

void main() {
  final schema = jsonDecode(manifestSchemaV1) as Map<String, Object?>;
  final portName =
      (((schema['definitions']! as Map)['port']! as Map)['properties']!
              as Map)['name']!
          as Map;
  final allowed = RegExp(portName['pattern']! as String);
  final random = Random(11);

  String instanceId() =>
      'inst-${[for (var i = 0; i < 12; i++) random.nextInt(16).toRadixString(16)].join()}';

  // Every shape the plugin schema allows: a letter, then letters, digits and
  // underscores, of any length.
  Iterable<String> portNames() sync* {
    const letters = 'abcdefghijklmnopqrstuvwxyz';
    const rest = '${letters}0123456789_';
    for (final first in letters.split('')) {
      yield first;
    }
    for (final c in rest.split('')) {
      yield 'a$c';
    }
    for (var i = 0; i < 300; i++) {
      final length = 1 + random.nextInt(60);
      yield letters[random.nextInt(letters.length)] +
          [for (var j = 0; j < length; j++) rest[random.nextInt(rest.length)]]
              .join();
    }
    yield 'a${'_' * 200}';
  }

  test('every_port_name_the_schema_allows_builds_an_owned_name', () {
    var checked = 0;
    for (final name in portNames()) {
      expect(allowed.hasMatch(name), isTrue, reason: 'generator: $name');
      for (final protocol in ['tcp', 'udp']) {
        final id = instanceId();
        final built = buildRuleName(
          RuleName(owner: id, portName: name, protocol: protocol),
        );
        final parsed = parseRuleName(built);
        expect(parsed, isNotNull, reason: built);
        expect(parsed!.instanceId, id);
        expect(parsed.portName, name);
        expect(parsed.protocol, protocol);
        expect(buildRuleName(parsed), built);
        expect(RegExp(ownedRuleNamePattern).hasMatch(built), isTrue);
        expect(
          ActualRule(name: built, protocol: protocol, port: '1').owned,
          isTrue,
        );
        checked++;
      }
    }
    expect(checked, greaterThan(600));
  });

  test('the_daemons_own_rule_is_owned', () {
    final parsed = parseRuleName(apiRuleName)!;
    expect(parsed.owner, daemonRuleOwner);
    expect(parsed.instanceId, isNull);
    expect(parsed.portName, 'api');
    expect(parsed.protocol, 'tcp');
  });

  test('a_name_outside_the_scheme_is_not_owned', () {
    final id = instanceId();
    for (final name in [
      '',
      'Valheim manual',
      'Yagura',
      'Yagura/',
      'Yagura/daemon/api',
      'Yagura/daemon/api/icmp',
      'Yagura/$id/game',
      'Yagura/$id/game/udp/extra',
      'Yagura/$id//udp',
      'Yagura/$id/Game/udp',
      'Yagura/$id/game/UDP',
      'yagura/$id/game/udp',
      'Yagura/inst-ABCDEF012345/game/udp',
      'Yagura/inst-0123456789a/game/udp',
      'Yagura/inst-0123456789abc/game/udp',
      'Yagura/inst-0123456789ab/ga me/udp',
      'Yagura/other/game/udp',
      ' Yagura/$id/game/udp',
      'Yagura/$id/game/udp\n',
      'Yagura/$id/game/udp ',
    ]) {
      expect(parseRuleName(name), isNull, reason: jsonEncode(name));
    }
  });
}
