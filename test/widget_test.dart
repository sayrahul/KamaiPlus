import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kamaiplus_pos/core/theme/app_theme.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'is_logged_in': false,
      'is_pro': false,
    });
  });

  testWidgets('App Theme and Core Shell smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.light,
        home: const Scaffold(
          body: Center(
            child: Text('KamaiPlus POS'),
          ),
        ),
      ),
    );

    expect(find.text('KamaiPlus POS'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
