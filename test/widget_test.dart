import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/main.dart';

void main() {
  testWidgets('KamaiPlusApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const KamaiPlusApp());
    expect(find.byType(KamaiPlusApp), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
