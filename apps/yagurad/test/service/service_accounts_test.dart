import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yagurad/src/service/account_purger.dart';
import 'package:yagurad/src/service/service_accounts.dart';

import '../support/acl_support.dart';

// Design D7, ADR 0015. The account calls go through AccountBackend, so the
// repair is tested with a fake; the Windows calls run in the `elevated` rows.

HostServiceAccounts _accounts(
  FakeAccountBackend backend,
  MemorySecretStore secrets, [
  int seed = 1,
]) => HostServiceAccounts(
  backend: backend,
  secrets: secrets,
  random: Random(seed),
);

void main() {
  group('password_encoding', () {
    test('32 bytes become 64 characters with all four classes', () {
      final random = Random(7);
      for (var i = 0; i < 200; i++) {
        final bytes = Uint8List.fromList([
          for (var j = 0; j < 32; j++) random.nextInt(256),
        ]);
        final password = generatePassword(bytes);
        expect(password, hasLength(64));
        expect(password, matches(RegExp('[A-Z]')));
        expect(password, matches(RegExp('[a-z]')));
        expect(password, matches(RegExp('[0-9]')));
        expect(password, matches(RegExp(r'[^A-Za-z0-9]')));
      }
    });

    test('all 256 bits of the input are in the output', () {
      final zero = generatePassword(Uint8List(32));
      for (var bit = 0; bit < 256; bit++) {
        final bytes = Uint8List(32)..[bit ~/ 8] = 0x80 >> (bit % 8);
        expect(generatePassword(bytes), isNot(zero), reason: 'bit $bit');
      }
    });

    test('anything but 32 bytes is refused', () {
      expect(() => generatePassword(Uint8List(31)), throwsArgumentError);
    });
  });

  group('the accounts', () {
    test('are created with a stored password, rights and Users only', () {
      final backend = FakeAccountBackend();
      final secrets = MemorySecretStore();

      _accounts(backend, secrets).ensure();

      for (final name in [gameServerAccount, steamAccount]) {
        final stored = secrets.get(serviceAccountSecretId(name));
        expect(stored, isNotNull, reason: 'stored under service-account:$name');
        expect(utf8.decode(stored!), backend.passwords[name]);
        expect(backend.rights[name], 1);
        expect(backend.groups[name], {'Users'});
      }
      expect(
        backend.passwords[gameServerAccount],
        isNot(backend.passwords[steamAccount]),
      );
    });

    test('the password is stored before the account has it', () {
      final backend = FakeAccountBackend();
      final secrets = MemorySecretStore();
      backend.failOn = 'create:$gameServerAccount';

      expect(() => _accounts(backend, secrets).ensure(), throwsA(anything));

      // An account created with a password nobody kept could not be used.
      expect(
        secrets.contains(serviceAccountSecretId(gameServerAccount)),
        isTrue,
      );
    });

    test('a second start sets the stored password again, without a logon', () {
      final backend = FakeAccountBackend();
      final secrets = MemorySecretStore();
      _accounts(backend, secrets).ensure();
      final password = backend.passwords[gameServerAccount];
      backend.calls.clear();

      _accounts(backend, secrets, 99).ensure();

      expect(backend.passwords[gameServerAccount], password, reason: 'same');
      expect(backend.calls, contains('setPassword:$gameServerAccount'));
      expect(backend.calls.where((c) => c.startsWith('create')), isEmpty);
    });

    test('a drifted password is repaired from the store', () {
      final backend = FakeAccountBackend();
      final secrets = MemorySecretStore();
      _accounts(backend, secrets).ensure();
      final stored = backend.passwords[steamAccount];
      backend.passwords[steamAccount] = 'changed by someone';

      _accounts(backend, secrets).ensure();

      expect(backend.passwords[steamAccount], stored);
    });

    test('other group memberships are removed', () {
      final backend = FakeAccountBackend();
      final secrets = MemorySecretStore();
      _accounts(backend, secrets).ensure();
      backend.groups[gameServerAccount]!.add('Administrators');

      _accounts(backend, secrets).ensure();

      expect(backend.groups[gameServerAccount], {'Users'});
    });

    test('rights are assigned again at every start', () {
      final backend = FakeAccountBackend();
      final secrets = MemorySecretStore();

      _accounts(backend, secrets).ensure();
      _accounts(backend, secrets).ensure();

      expect(backend.rights[gameServerAccount], 2);
    });

    test('a failure names the account', () {
      final backend = FakeAccountBackend()..failOn = 'rights:$steamAccount';

      expect(
        () => _accounts(backend, MemorySecretStore()).ensure(),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'text',
            allOf(contains('service_accounts'), contains(steamAccount)),
          ),
        ),
      );
    });

    test('are looked up by name', () {
      final backend = FakeAccountBackend();
      final accounts = _accounts(backend, MemorySecretStore())..ensure();

      expect(accounts.sidOf(gameServerAccount), isNotNull);
      expect(accounts.sidOf('nobody'), isNull);
      expect(accounts.passwordOf(gameServerAccount), hasLength(64));
    });
  });
}
