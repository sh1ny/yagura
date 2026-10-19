import 'package:test/test.dart';
import 'package:yagurad/src/platform/win32_logon.dart';

// A window station or desktop named `YaguraSrv` or `YaguraSteam` that already
// exists is opened, not created. Its owner keeps `WRITE_DAC` whatever DACL the
// daemon sets, so an object some other account created first would stay under
// that account's control (design D7: "A game server cannot then hook or
// message SteamCMD's windows"). The account the object is for already has full
// access to it, so owning it grants that account nothing new.
const _srv = 'S-1-5-21-1-2-3-2001';
const _steam = 'S-1-5-21-1-2-3-2002';

void main() {
  test('an_object_owned_by_system_or_administrators_is_trusted', () {
    expect(untrustedWindowObjectOwner('O:SY', _srv), isNull);
    expect(untrustedWindowObjectOwner('O:BA', _srv), isNull);
    expect(untrustedWindowObjectOwner('O:S-1-5-18', _srv), isNull);
    expect(untrustedWindowObjectOwner('O:S-1-5-32-544', _srv), isNull);
  });

  test('an_object_owned_by_its_own_account_is_trusted', () {
    expect(untrustedWindowObjectOwner('O:$_srv', _srv), isNull);
    expect(untrustedWindowObjectOwner('O:$_steam', _steam), isNull);
  });

  test('an_object_owned_by_another_account_is_named', () {
    // yagura-srv owning the SteamCMD desktop, and the other way round.
    expect(untrustedWindowObjectOwner('O:$_srv', _steam), _srv);
    expect(untrustedWindowObjectOwner('O:$_steam', _srv), _steam);
    expect(
      untrustedWindowObjectOwner('O:S-1-5-21-1-2-3-1001', _srv),
      'S-1-5-21-1-2-3-1001',
    );
    expect(untrustedWindowObjectOwner('O:BU', _srv), 'S-1-5-32-545');
    expect(untrustedWindowObjectOwner('O:WD', _srv), 'S-1-1-0');
  });

  test('an_object_without_a_readable_owner_is_not_trusted', () {
    expect(untrustedWindowObjectOwner('', _srv), 'nobody');
    expect(untrustedWindowObjectOwner('D:(A;;GA;;;SY)', _srv), 'nobody');
  });

  // 0xC0000142 (STATUS_DLL_INIT_FAILED) in every process started on a desktop
  // whose account had only object-specific rights: the account gets full
  // access, and the owner rule above keeps that safe.
  test('the_account_has_full_access_to_its_station_and_desktop', () {
    expect(windowObjectSddl(_srv), 'D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;$_srv)');
  });
}
