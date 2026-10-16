import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';

import 'support.dart';

void main() {
  test('manifest_deadline_above_the_cap', () {
    final result = loadPlugin(
      writePlugin(
        valheimWith('stop:\n', 'hooks:\n  timeout_seconds: 300\n\nstop:\n'),
      ),
    );

    expect(result.status, PluginStatus.rejected);
    final reason = result.reasons.single;
    expect(reason.path, 'hooks.timeout_seconds');
    expect(reason.message, contains('60'));
  });

  group('beyond the test map', () {
    test('the default deadline is 5 seconds', () {
      final result = loadPlugin(writePlugin(valheimManifest()));

      expect(result.manifest!.hooksTimeoutSeconds, 5);
    });

    test('a deadline at the cap is accepted', () {
      final result = loadPlugin(
        writePlugin(
          valheimWith('stop:\n', 'hooks:\n  timeout_seconds: 60\n\nstop:\n'),
        ),
      );

      expect(result.manifest!.hooksTimeoutSeconds, 60);
    });
  });
}
