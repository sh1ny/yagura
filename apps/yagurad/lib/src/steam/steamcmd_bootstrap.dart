import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors.dart';
import '../files/confined_fs.dart';
import '../operations/cancel_token.dart';

/// Downloads [uri] into [destination]; throws on any failure and
/// [OperationCancelled] once [cancel] fires, after the transfer was aborted.
/// The caller closes [destination].
typedef ArchiveFetcher = Future<void> Function(
  Uri uri,
  ConfinedWriter destination,
  CancelToken cancel,
);

/// Where SteamCMD comes from and how it is fetched. The source and the
/// fetcher are injectable so tests bootstrap from a local server.
class SteamCmdBootstrap {
  SteamCmdBootstrap({
    Uri? source,
    ArchiveFetcher? fetch,
    this.idleTimeout = const Duration(seconds: 60),
  }) : source = source ?? defaultSource,
       _fetch =
           fetch ??
           ((uri, destination, cancel) => downloadWithHttpClient(
             uri,
             destination,
             cancel,
             idleTimeout: idleTimeout,
           ));

  /// Valve's installer archive for this platform.
  static Uri get defaultSource => Uri.parse(
    Platform.isWindows
        ? 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'
        : 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz',
  );

  final Uri source;
  final ArchiveFetcher _fetch;

  /// How long the default download waits for the response or for the next
  /// bytes of it before it fails.
  final Duration idleTimeout;

  /// Downloads the archive and unpacks it into the directory [installation]
  /// of [fs] (the `<data>/steamcmd` root). Throws `steamcmd_unavailable` with
  /// the HTTP status or the network error; the caller removes the directory
  /// then, so no half-installed directory stays. Throws [OperationCancelled]
  /// once [cancel] fires, with the download or the unpacking stopped.
  Future<void> install(
    ConfinedFs fs,
    String installation, {
    CancelToken? cancel,
  }) async {
    cancel ??= CancelToken();
    fs.createDirectory(installation);
    final archive = '$installation/steamcmd.download';
    try {
      final writer = fs.openWrite(archive);
      try {
        await _fetch(source, writer, cancel);
      } finally {
        writer.close();
      }
    } on YaguraException {
      rethrow;
    } on OperationCancelled {
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
    final tar = await Process.start(
      Platform.isWindows
          ? p.join(
              Platform.environment['SystemRoot'] ?? r'C:\Windows',
              'System32',
              'tar.exe',
            )
          : 'tar',
      ['-xf', 'steamcmd.download'],
      workingDirectory: fs.absolute(installation),
    );
    unawaited(tar.stdout.drain<void>());
    final stderrText = tar.stderr
        .transform(const SystemEncoding().decoder)
        .join();
    unawaited(cancel.whenCancelled.then((_) => tar.kill()));
    final code = await tar.exitCode;
    cancel.throwIfCancelled();
    if (code != 0) {
      throw YaguraException(
        'steamcmd_unavailable',
        'the SteamCMD archive from $source could not be unpacked: '
            '${(await stderrText).trim()}',
        details: {'source': '$source'},
      );
    }
    fs.delete(archive);
  }

  /// Fetches with `dart:io`'s client; a non-200 status fails with it. The
  /// transfer fails when the response or the next bytes of it take longer than
  /// [idleTimeout], and is aborted when [cancel] fires.
  static Future<void> downloadWithHttpClient(
    Uri uri,
    ConfinedWriter destination,
    CancelToken cancel, {
    Duration idleTimeout = const Duration(seconds: 60),
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..findProxy = HttpClient.findProxyFromEnvironment;
    // Closing the client by force ends a request or body that has stalled.
    unawaited(cancel.whenCancelled.then((_) => client.close(force: true)));
    try {
      cancel.throwIfCancelled();
      final request = await client.getUrl(uri).timeout(idleTimeout);
      final response = await request.close().timeout(idleTimeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>().timeout(idleTimeout);
        throw YaguraException(
          'steamcmd_unavailable',
          'SteamCMD could not be downloaded from $uri: HTTP '
              '${response.statusCode} ${response.reasonPhrase}',
          details: {'source': '$uri', 'httpStatus': response.statusCode},
        );
      }
      await for (final chunk in response.timeout(idleTimeout)) {
        destination.add(chunk);
      }
    } on TimeoutException {
      cancel.throwIfCancelled();
      throw YaguraException(
        'steamcmd_unavailable',
        'SteamCMD could not be downloaded from $uri: no data for '
            '${idleTimeout.inSeconds} s',
        details: {'source': '$uri'},
      );
    } on Object {
      // A forced close surfaces as a socket error.
      cancel.throwIfCancelled();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}
