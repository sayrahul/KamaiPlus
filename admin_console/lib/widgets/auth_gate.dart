import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/admin_auth_service.dart';
import '../services/admin_firestore_service.dart';
import '../theme/admin_theme.dart';
import '../screens/login_screen.dart';
import '../screens/admin_shell.dart';

/// Three real states, not two — "signed in but not on the admin allow-list"
/// gets its own explicit screen rather than silently bouncing back to
/// login, which would look like a wrong-password error to someone who
/// authenticated correctly but simply isn't an admin.
///
/// Listens live on admins/{uid} (via watchCurrentUserIsAdmin), not just a
/// one-time check on sign-in — if someone with Firebase Console access
/// revokes an admin's access mid-session, this drops them out of the
/// console immediately rather than leaving the AdminShell UI visible until
/// their next reload. Firestore rules are the actual security boundary
/// either way (every read/write is independently re-checked server-side);
/// this only keeps what's ON SCREEN honest in real time.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AdminAuthStatus _status = AdminAuthStatus.checking;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<bool>? _adminSub;

  @override
  void initState() {
    super.initState();
    _authSub = AdminAuthService.instance.authStateChanges.listen((_) => _onAuthChanged());
    _onAuthChanged();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _adminSub?.cancel();
    super.dispose();
  }

  void _onAuthChanged() {
    _adminSub?.cancel();
    final user = AdminAuthService.instance.currentUser;
    if (user == null) {
      setState(() => _status = AdminAuthStatus.signedOut);
      return;
    }
    setState(() => _status = AdminAuthStatus.checking);
    _adminSub = AdminFirestoreService.instance.watchCurrentUserIsAdmin().listen((isAdmin) {
      if (mounted) setState(() => _status = isAdmin ? AdminAuthStatus.signedInAdmin : AdminAuthStatus.signedInNotAdmin);
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case AdminAuthStatus.checking:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AdminAuthStatus.signedOut:
        return LoginScreen(onSignedIn: _onAuthChanged);
      case AdminAuthStatus.signedInNotAdmin:
        return _NotAdminScreen(onSignOut: () async {
          await AdminAuthService.instance.signOut();
          _onAuthChanged();
        });
      case AdminAuthStatus.signedInAdmin:
        return const AdminShell();
    }
  }
}

class _NotAdminScreen extends StatelessWidget {
  final VoidCallback onSignOut;
  const _NotAdminScreen({required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 48, color: AdminColors.inkFaint),
                const SizedBox(height: 16),
                Text('This account isn\'t an admin', style: AdminTheme.heading(20), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Signed in as $email, but this account isn\'t on the KamaiPlus admin allow-list. '
                  'Ask whoever has direct Firebase Console access to add your account to the "admins" collection.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AdminColors.inkMuted, height: 1.5),
                ),
                const SizedBox(height: 20),
                OutlinedButton(onPressed: onSignOut, child: const Text('Sign out')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
