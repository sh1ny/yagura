import 'package:flutter_test/flutter_test.dart';
import 'package:yagura_desktop/main.dart';

void main() {
  testWidgets('placeholder app renders', (tester) async {
    await tester.pumpWidget(const YaguraApp());
    expect(find.text('Yagura'), findsOneWidget);
  });
}
