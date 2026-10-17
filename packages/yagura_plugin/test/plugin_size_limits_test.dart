import 'package:test/test.dart';
import 'package:yagura_plugin/yagura_plugin.dart';

import 'support.dart';

const _kib = 1024;
const _mib = 1024 * 1024;

/// A valid manifest padded with comment lines to exactly [bytes] bytes.
String _manifestOfSize(int bytes) {
  final base = valheimManifest();
  final padding = bytes - base.length - 2;
  return '$base#${'x' * padding}\n';
}

void main() {
  test('oversized_hooks_file', () {
    // Not valid JavaScript: the size check must come before any parsing.
    final result = loadPlugin(
      writePlugin(valheimManifest(), hooks: List.filled(3 * _mib, 0x78)),
    );

    expect(result.status, PluginStatus.rejected);
    final reason = result.reasons.single;
    expect(reason.code, 'file_too_large');
    expect(reason.path, 'hooks.js');
    expect(reason.message, contains('hooks.js'));
    expect(reason.message, contains('1 MiB'));
  });

  test('within_limits', () {
    final manifest = _manifestOfSize(20 * _kib);
    expect(manifest.length, 20 * _kib);

    final result = loadPlugin(
      writePlugin(manifest, hooks: List.filled(40 * _kib, 0x20)),
    );

    expect(result.reasons, isEmpty);
    expect(result.status, PluginStatus.loaded);
  });

  group('beyond the test map', () {
    test('oversized plugin.yaml is rejected before parsing', () {
      final result = loadPlugin(writePlugin('x' * (256 * _kib + 1)));

      expect(result.status, PluginStatus.rejected);
      final reason = result.reasons.single;
      expect(reason.code, 'file_too_large');
      expect(reason.path, 'plugin.yaml');
      expect(reason.message, contains('256 KiB'));
    });

    test('files exactly at the limits are accepted', () {
      final result = loadPlugin(
        writePlugin(
          _manifestOfSize(256 * _kib),
          hooks: List.filled(_mib, 0x20),
        ),
      );

      expect(result.reasons, isEmpty);
      expect(result.status, PluginStatus.loaded);
    });
  });
}
