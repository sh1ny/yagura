import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/steam/steam.dart';

import '../support/temp_support.dart';

void main() {
  late Directory temp;
  late YaguraDatabase database;

  setUp(() {
    temp = createCanonicalTempSync('yagura_steam_state_');
    database = YaguraDatabase.open(p.join(temp.path, 'yagura.db'));
    addTearDown(() {
      database.close();
      temp.deleteSync(recursive: true);
    });
  });

  for (final (name, make) in <(String, SteamState Function())>[
    ('memory', MemorySteamState.new),
    ('database', () => DatabaseSteamState(database, () => DateTime(2026))),
  ]) {
    test('the $name state remembers readiness and app sizes', () {
      final state = make();
      expect(state.isReady('anonymous'), isFalse);
      expect(state.lastKnownSize(896660), isNull);

      state.markReady('anonymous');
      state.recordSize(896660, 1000);
      state.recordSize(896660, 2000);

      expect(state.isReady('anonymous'), isTrue);
      expect(state.isReady('other'), isFalse);
      expect(state.lastKnownSize(896660), 2000);
      state.markNotReady('anonymous');
      expect(state.isReady('anonymous'), isFalse);
    });
  }

  test('the database state survives a reopen', () {
    DatabaseSteamState(database)
      ..markReady('anonymous')
      ..recordSize(1, 5);
    database.close();
    database = YaguraDatabase.open(p.join(temp.path, 'yagura.db'));

    final state = DatabaseSteamState(database);
    expect(state.isReady('anonymous'), isTrue);
    expect(state.lastKnownSize(1), 5);
  });
}
