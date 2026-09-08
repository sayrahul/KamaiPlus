import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/business_vertical_config.dart';
import '../core/database/local_database.dart';
import '../models/models.dart';

class AuthService {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // google_sign_in v7+ uses GoogleSignIn.instance singleton
  bool _googleSignInInitialized = false;

  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Initialize the GoogleSignIn singleton (call once on startup)
  Future<void> initGoogleSignIn() async {
    if (_googleSignInInitialized) return;
    try {
      await GoogleSignIn.instance.initialize(
        clientId: null, // Android uses google-services.json automatically
      );
      _googleSignInInitialized = true;
    } catch (e) {
      debugPrint('GoogleSignIn.instance.initialize error: $e');
    }
  }

  /// Sign In with Google Account via OAuth & Firebase Auth
  Future<UserCredential?> signInWithGoogle() async {
    try {
      await initGoogleSignIn();

      // 1. Trigger interactive Google OAuth picker (v7+ API)
      final googleUser = await GoogleSignIn.instance.authenticate();

      // 2. Obtain ID Token from authenticated account
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      // 3. Create Firebase Credential using idToken (sufficient for Firebase Auth)
      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      // 4. Sign in to Firebase Auth with Credential
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        // 5. Cache account details locally in SharedPreferences for offline speed
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_user_id', user.uid);
        await prefs.setString('auth_user_email', user.email ?? '');
        await prefs.setString('auth_user_name', user.displayName ?? '');
        await prefs.setBool('is_logged_in', true);
        await prefs.setBool('is_onboarded', true);
        if (user.photoURL != null) {
          await prefs.setString('auth_user_photo', user.photoURL!);
        }

        // 6. If local store profile has empty owner or email, pre-fill it gracefully
        final db = LocalDatabase.instance;
        final currentProfile = await db.getStoreProfile();
        final updatedProfile = StoreProfileModel(
          storeName: currentProfile.storeName,
          tagline: currentProfile.tagline,
          ownerName: currentProfile.ownerName.isEmpty
              ? (user.displayName ?? '')
              : currentProfile.ownerName,
          phone: currentProfile.phone,
          email: currentProfile.email.isEmpty
              ? (user.email ?? '')
              : currentProfile.email,
          upiVpa: currentProfile.upiVpa,
          category: currentProfile.category,
          businessType: currentProfile.businessType,
          address: currentProfile.address,
          pincode: currentProfile.pincode,
          gstin: currentProfile.gstin,
          fssai: currentProfile.fssai,
          logoUrl: (currentProfile.logoUrl.isEmpty && user.photoURL != null)
              ? user.photoURL!
              : currentProfile.logoUrl,
          upiAccountsJson: currentProfile.upiAccountsJson,
        );
        await db.saveStoreProfile(updatedProfile);
      }

      return userCredential;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        debugPrint('Google Sign-In canceled by user.');
        return null;
      }
      debugPrint('GoogleSignInException: ${e.description}');
      rethrow;
    } catch (e) {
      debugPrint('Error signing in with Google: $e');
      rethrow;
    }
  }

  /// Sign In silently in background on app start if already authenticated (v7+ API)
  Future<User?> signInSilently() async {
    try {
      await initGoogleSignIn();
      final googleUser = await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (googleUser != null) {
        final GoogleSignInAuthentication googleAuth = googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );
        final userCredential = await _auth.signInWithCredential(credential);
        return userCredential.user;
      }
      return _auth.currentUser;
    } catch (e) {
      debugPrint('Silent Google sign-in skipped: $e');
      return _auth.currentUser;
    }
  }

  /// Sign out from Firebase Auth & Google OAuth, clear session and reset database
  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {}
    try {
      await _auth.signOut();
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      debugPrint('Error clearing prefs during signOut: $e');
    }
    try {
      await LocalDatabase.instance.closeDatabase();
    } catch (_) {}
    try {
      BusinessVerticals.updateActiveBusinessType('grocery');
    } catch (_) {}
  }
}
