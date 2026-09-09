import 'package:in_app_update/in_app_update.dart';

/// Google Play Core In-App Update Service
class InAppUpdateService {
  InAppUpdateService._();
  static final InAppUpdateService instance = InAppUpdateService._();

  /// Silently checks for app updates on Google Play Store
  /// If available and flexible update is allowed, prompts the merchant
  Future<void> checkForUpdates() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        if (info.immediateUpdateAllowed) {
          await InAppUpdate.performImmediateUpdate();
        } else if (info.flexibleUpdateAllowed) {
          await InAppUpdate.startFlexibleUpdate();
          await InAppUpdate.completeFlexibleUpdate();
        }
      }
    } catch (_) {
      // Gracefully ignore on non-Play store debug/sideload builds
    }
  }
}
