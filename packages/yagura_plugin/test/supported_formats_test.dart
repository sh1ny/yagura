import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';

import 'support.dart';

String _bindingWith(String format) => valheimWith(
  'launch:\n  args:',
  'bindings:\n  - file: serverDZ.cfg\n    format: $format\n    key: a\n'
      '    setting: serverName\n\nlaunch:\n  args:',
);

void main() {
  test('format_of_a_later_version', () {
    final result = loadPlugin(writePlugin(_bindingWith('ue-ini')));

    expect(result.status, PluginStatus.rejected);
    final reason = result.reasons.single;
    expect(reason.code, 'unsupported_in_this_version');
    expect(reason.message, contains('ue-ini'));
  });

  test('unknown_format_name', () {
    final result = loadPlugin(writePlugin(_bindingWith('toml')));

    expect(result.status, PluginStatus.rejected);
    final reason = result.reasons.single;
    expect(reason.message, contains('toml'));
    for (final format in ['json', 'ini', 'dayz-cfg', 'kv']) {
      expect(reason.message, contains(format));
    }
  });
}
