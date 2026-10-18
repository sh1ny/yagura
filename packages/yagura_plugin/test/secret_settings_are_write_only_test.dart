import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';

import 'support.dart';

void main() {
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
