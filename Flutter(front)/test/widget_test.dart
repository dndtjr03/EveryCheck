import 'package:everycheck/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const EveryCheckApp());
    await tester.pump();
  });
}
