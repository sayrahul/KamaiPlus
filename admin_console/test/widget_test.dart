// Minimal smoke test — deliberately does not pump AdminConsoleApp/AuthGate
// directly: AuthGate's initState reaches for FirebaseAuth.instance, which
// has no app to talk to in a plain widget-test environment (no
// Firebase.initializeApp() call here, and setting up firebase_auth_mocks
// is out of scope for this v1 console). Testing LoginScreen in isolation
// sidesteps that — it renders without touching Firebase until a button is
// actually pressed — while still catching the real regression class this
// guards against: the app's own MaterialApp/theme failing to build at all.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_admin/screens/login_screen.dart';
import 'package:kamaiplus_admin/theme/admin_theme.dart';

void main() {
  testWidgets('Login screen renders the KamaiPlus Admin sign-in form', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AdminTheme.light,
      home: LoginScreen(onSignedIn: () {}),
    ));

    expect(find.text('KamaiPlus Admin'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
