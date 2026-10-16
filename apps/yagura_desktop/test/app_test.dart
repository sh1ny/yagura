import 'package:flutter_test/flutter_test.dart';
import 'package:yagura_desktop/main.dart';
import 'package:yagura_desktop/src/providers.dart';

import 'support/fake_daemon.dart';

void main() {
  testWidgets('the app shows the daemon it is connected to', (tester) async {
    final harness = Harness(
      daemon: FakeDaemon(
        instances: [makeInstance(id: 'i1', name: 'Alpha')],
      ),
    );
    harness.connection.start();
    addTearDown(harness.connection.dispose);
    await tester.pumpWidget(YaguraApp(overrides: harness.overrides));
    await settle(tester);

    expect(find.text('Yagura'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.textContaining('Connected'), findsOneWidget);
    expect(kDevDaemonId, 'dev');
  });
}
