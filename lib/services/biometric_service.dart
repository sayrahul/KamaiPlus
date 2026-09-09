import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Native Biometric Authentication Service (Fingerprint / Face Unlock / Screen Lock)
class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  final LocalAuthentication _auth = LocalAuthentication();

  /// Check if device has hardware support and at least one biometric enrolled
  Future<bool> isBiometricAvailable() async {
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool isDeviceSupported = await _auth.isDeviceSupported();
      return canAuthenticateWithBiometrics && isDeviceSupported;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Check if the device has enrolled biometrics (Fingerprint or Face)
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Prompt user for Biometric authentication (Fingerprint/Face)
  Future<bool> authenticateOwner({
    String reason = 'KamaiPlus Owner Verification: Please authenticate to continue',
  }) async {
    try {
      final bool canAuth = await _auth.isDeviceSupported();
      if (!canAuth) return true; // Graceful bypass if device has no hardware security

      return await _auth.authenticate(
        localizedReason: reason,
      );
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }
}
