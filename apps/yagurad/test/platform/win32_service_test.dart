@Tags(['windows'])
library;

import 'package:test/test.dart';
import 'package:yagurad/src/platform/win32_security.dart';
import 'package:yagurad/src/platform/win32_service.dart';

// Read-only queries of the service control manager and the process token.
void main() {
  test('a_service_that_does_not_exist_has_no_state', () {
    expect(queryServiceState('yagurad-no-such-service-0'), isNull);
  });

  test('a_service_windows_ships_has_a_state', () {
    // The DNS client service exists on every Windows install.
    final state = queryServiceState('Dnscache');

    expect(state, isNotNull);
    expect(
      state,
      anyOf(
        serviceStopped,
        serviceStartPending,
        serviceStopPending,
        serviceRunning,
      ),
    );
  });

  test('elevation_is_read_from_the_process_token', () {
    // Either answer is right; the call must work and be stable.
    expect(isElevated(), isElevated());
  });
}
