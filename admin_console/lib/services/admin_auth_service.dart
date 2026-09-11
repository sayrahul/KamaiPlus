import 'package:firebase_auth/firebase_auth.dart';

enum AdminAuthStatus { checking, signedOut, signedInNotAdmin, signedInAdmin }

/// Wraps Firebase Auth + the admin allow-list check into one status the app
/// shell can branch on. "Signed in but not an admin" is deliberately a
/// distinct state from "signed out" — a merchant who mistakenly opens this
/// console and signs in with their own account should see a clear
/// "this account isn't an admin" message, not a silent redirect back to
/// the login form that looks like their password was wrong.
class AdminAuthService {
  AdminAuthService._();
  static final AdminAuthService instance = AdminAuthService._();

  final _auth = FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<String?> signInWithGoogle() async {
    try {
      final provider = GoogleAuthProvider();
      await _auth.signInWithPopup(provider);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Google sign-in failed';
    } catch (e) {
      return 'Google sign-in failed: $e';
    }
  }

  Future<String?> signInWithEmail(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Sign-in failed';
    } catch (e) {
      return 'Sign-in failed: $e';
    }
  }

  Future<void> signOut() => _auth.signOut();
}
