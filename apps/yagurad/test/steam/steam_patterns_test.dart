import 'dart:io';

import 'package:test/test.dart';
import 'package:yagurad/src/steam/patterns.g.dart';
import 'package:yagurad/src/steam/steam.dart';
import 'package:yaml/yaml.dart';

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

  // The `login` group's rule (patterns.yaml): outcomes in table order, the
  // first that any stdout line matches wins. Task 5.3 implements it in the
  // daemon; this checks the table against the spike's transcripts
  // (docs/spikes/m3-steam-guard.md, SteamCMD build 1791918946).
  group('login outcomes classify the spike transcripts', () {
    final login = (loadYaml(steamPatternsYaml) as YamlMap)['login'] as YamlMap;
    String? classify(List<String> lines) {
      for (final outcome in login['outcomes'] as YamlList) {
        final match = RegExp((outcome as YamlMap)['match'] as String);
        if (lines.any(match.hasMatch)) return outcome['kind'] as String;
      }
      return null;
    }

    const loggedIn = "Logging in user '<user>' [U:1:0] to Steam Public...OK";
    final transcripts = {
      'email code asked': (
        [
          'This computer has not been authenticated for your account using '
              'Steam Guard.',
          'Please check your email for the message from Steam, and enter the '
              'Steam Guard',
          'Steam Guard code:ERROR (Account Logon Denied)',
        ],
        'guard_email',
      ),
      'email code accepted': (
        ['Steam Guard code provided.', loggedIn, 'Waiting for user info...OK'],
        'ok',
      ),
      'mobile approval given in the same run': (
        [
          'This account is protected by a Steam Guard mobile authenticator.',
          'Please confirm the login in the Steam Mobile app on your phone.',
          'Waiting for confirmation...',
          loggedIn,
          'Waiting for user info...OK',
        ],
        'ok',
      ),
      'mobile approval never given': (
        [
          'This account is protected by a Steam Guard mobile authenticator.',
          'Please confirm the login in the Steam Mobile app on your phone.',
          'Waiting for confirmation...',
        ],
        'guard_mobile',
      ),
      'cached login': (
        ['Logging in using cached credentials.', loggedIn],
        'ok',
      ),
      'cached login missing': (
        [
          'Logging in using cached credentials.',
          'Cached credentials not found.',
          'password:',
          'ERROR (Invalid Password)',
        ],
        'reauth_needed',
      ),
    };
    for (final MapEntry(key: name, value: (lines, kind))
        in transcripts.entries) {
      test(name, () => expect(classify(lines), kind));
    }

    test('the live mobile signal matches connection_log.txt', () {
      final live = RegExp((login['live'] as YamlMap)['guard_mobile'] as String);
      expect(
        live.hasMatch('[2026-10-20 17:20:56] Waiting for confirmation'),
        isTrue,
      );
    });
  });
}
