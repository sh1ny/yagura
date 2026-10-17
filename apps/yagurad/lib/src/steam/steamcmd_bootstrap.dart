import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors.dart';

/// Downloads [uri] into [destination]; throws on any failure.
typedef ArchiveFetcher = Future<void> Function(Uri uri, File destination);

/// Where SteamCMD comes from and how it is fetched. The source and the
/// fetcher are injectable so tests bootstrap from a local server.
class SteamCmdBootstrap {
  SteamCmdBootstrap({Uri? source, ArchiveFetcher? fetch})
    : source = source ?? defaultSource,
      _fetch = fetch ?? downloadWithHttpClient;

  /// Valve's installer archive for this platform.
  static Uri get defaultSource => Uri.parse(
    Platform.isWindows
        ? 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'
        : 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz',
  );

  final Uri source;
  final ArchiveFetcher _fetch;

  /// Downloads the archive and unpacks it into [target]. Throws
  /// `steamcmd_unavailable` with the HTTP status or the network error; the
  /// caller removes [target] then, so no half-installed directory stays.
  Future<void> install(Directory target) async {
    target.createSync(recursive: true);
    final archive = File(p.join(target.path, 'steamcmd.download'));
    try {
      await _fetch(source, archive);
    } on YaguraException {
      rethrow;
    } on Object catch (e) {
      throw YaguraException(
        'steamcmd_unavailable',
        'SteamCMD could not be downloaded from $source: $e',
        details: {'source': '$source'},
      );
    }
    // `tar` reads zip and tar.gz alike (bsdtar ships with Windows 10+). Run in
    // the target so a drive letter in the path cannot be taken for a host.
    final result = await Process.run(
      Platform.isWindows
          ? p.join(
              Platform.environment['SystemRoot'] ?? r'C:\Windows',
              'System32',
              'tar.exe',
            )
          : 'tar',
      ['-xf', p.basename(archive.path)],
      workingDirectory: target.path,
    );
    if (result.exitCode != 0) {
      throw YaguraException(
        'steamcmd_unavailable',
        'the SteamCMD archive from $source could not be unpacked: '
            '${(result.stderr as String).trim()}',
        details: {'source': '$source'},
      );
    }
    archive.deleteSync();
  }

  /// Fetches with `dart:io`'s client; a non-200 status fails with it.
  static Future<void> downloadWithHttpClient(Uri uri, File destination) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..findProxy = HttpClient.findProxyFromEnvironment;
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw YaguraException(
          'steamcmd_unavailable',
          'SteamCMD could not be downloaded from $uri: HTTP '
              '${response.statusCode} ${response.reasonPhrase}',
          details: {'source': '$uri', 'httpStatus': response.statusCode},
        );
      }
      await response.pipe(destination.openWrite());
    } finally {
      client.close(force: true);
    }
  }
}
