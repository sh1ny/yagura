import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';

import 'support.dart';

void main() {
  nestedTests();
  test('default_on_a_secret_rejected', () {
    final result = loadPlugin(
      writePlugin(
        valheimWith(
          '    type: secret\n',
          '    type: secret\n    default: changeme\n',
        ),
      ),
    );

    expect(result.status, PluginStatus.rejected);
    expect(result.reasons.first.path, 'settings.password.default');
  });

  test('a_secret_value_carries_secret_via_set_secret', () {
    final manifest = loadPlugin(writePlugin(valheimManifest())).manifest!;

    final refused = validateSettings(manifest, {'password': 'hunter2'});
    expect(refused.errors.single.path, 'password');
    expect(refused.errors.single.code, 'secret_via_set_secret');

    for (final placeholder in [
      {'secret': true, 'set': false},
      {'secret': true, 'set': true},
    ]) {
      final accepted = validateSettings(manifest, {'password': placeholder});
      expect(accepted.errors, isEmpty);
      expect(accepted.values, isNot(contains('password')));
    }
  });
}

String _nested(String field) => valheimWith(
  '  password:\n',
  '  servers:\n    type: list\n    label: Servers\n    fields:\n$field'
      '  password:\n',
);

void nestedTests() {
  test('nested_secret_rejected', () {
    final result = loadPlugin(
      writePlugin(_nested('      password: { type: secret }\n')),
    );

    expect(result.status, PluginStatus.rejected);
    expect(
      result.reasons.map((r) => r.message),
      contains(contains('servers.password')),
    );
  });

  test('nested_secret_in_an_object_at_depth_rejected', () {
    final result = loadPlugin(
      writePlugin(
        _nested(
          '      limits:\n        type: object\n        fields:\n'
          '          token: { type: secret }\n',
        ),
      ),
    );

    expect(result.status, PluginStatus.rejected);
    expect(
      result.reasons.map((r) => r.message),
      contains(contains('servers.limits.token')),
    );
  });
}
