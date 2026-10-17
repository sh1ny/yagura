import 'dart:io';

import 'package:test/test.dart';
import 'package:yagurad/src/steam/patterns.g.dart';
import 'package:yagurad/src/steam/steam.dart';

void main() {
  test('the embedded pattern table matches patterns.yaml', () {
    final source = File('lib/src/steam/patterns.yaml').readAsStringSync();
    expect(
      steamPatternsYaml.replaceAll('\r\n', '\n'),
      source.replaceAll('\r\n', '\n'),
      reason: 'run: dart run tool/embed_steam_patterns.dart',
    );
  });

  group('SteamPatterns', () {
    final patterns = SteamPatterns.embedded();

    test('parses a progress line', () {
      final progress = patterns.progressFor(
        ' Update state (0x61) downloading, progress: 45.12 (1234 / 2736)',
      )!;
      expect(progress.step, 'download');
      expect(progress.percent, 45.12);
      expect(progress.bytesDone, 1234);
      expect(progress.bytesTotal, 2736);
    });

    test('maps verifying and committing to their own steps', () {
      expect(
        patterns
            .progressFor(
              ' Update state (0x81) verifying update, progress: 1.0 (1 / 2)',
            )!
            .step,
        'verify',
      );
      expect(
        patterns
            .progressFor(
              ' Update state (0x101) committing, progress: 1.0 (1 / 2)',
            )!
            .step,
        'commit',
      );
    });

    test('ignores other lines', () {
      expect(patterns.progressFor('Loading Steam API...OK'), isNull);
      expect(
        patterns.stepFor('Connecting anonymously to Steam Public...OK'),
        'steam_login',
      );
      expect(patterns.stepFor('Waiting for user info...OK'), isNull);
    });

    test('recognises success and known failures', () {
      expect(
        patterns.isSuccess("Success! App '896660' fully installed."),
        isTrue,
      );
      expect(
        patterns.isSuccess("Success! App '896660' already up to date."),
        isTrue,
      );
      final failure = patterns.classify([
        "ERROR! Failed to install app '223350' (No subscription)",
      ], appId: 223350)!;
      expect(failure.reason, 'steam_no_subscription');
      expect(failure.message, contains('223350'));
      expect(patterns.classify(['all fine'], appId: 1), isNull);
    });
  });
}
