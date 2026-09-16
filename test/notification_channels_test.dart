// One admin "Send" arrived on the merchant's phone as THREE notifications:
// two in the tray and one banner inside the app.
//
//   1. admin_console wrote admin_push_notifications/{id}
//        -> onAdminPushCreated pushed over FCM              -> tray alert
//   2. the same call ALSO mirrored to platform_settings/broadcast
//        -> the app's broadcast listener raised a local one  -> tray alert
//   3. the same listener set broadcastNotifier              -> in-app banner
//
// The fix has two halves, and this file guards the app half: the broadcast
// listener must surface the banner and NOTHING in the tray, so FCM is the only
// code path in the app that can produce a tray notification. (The admin half —
// no longer mirroring one channel onto the other — is guarded by the explicit
// sendPhoneAlert / showInAppBanner arguments on sendPushNotification.)

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final syncSource = File('lib/services/firestore_sync_service.dart').readAsStringSync();
  final adminSource = File('admin_console/lib/services/admin_firestore_service.dart').readAsStringSync();

  group('Broadcast listener owns the in-app banner only', () {
    test('the broadcast listener raises no tray notification', () {
      // Isolate the listener body so an unrelated notification call elsewhere
      // in this large file cannot mask a regression here.
      final start = syncSource.indexOf("_broadcastSub = firestore");
      expect(start, greaterThan(-1), reason: 'broadcast listener not found');
      final end = syncSource.indexOf('_globalConfigSub = firestore', start);
      expect(end, greaterThan(start));
      final listenerBody = syncSource.substring(start, end);

      expect(
        listenerBody.contains('showLocalNotification'),
        isFalse,
        reason: 'The banner IS this channel. Raising a tray notification here '
            'duplicates the FCM alert the admin already sent.',
      );
    });

    test('the listener still drives the in-app banner', () {
      expect(syncSource.contains('broadcastNotifier.value = data'), isTrue);
    });

    test('id 9901 — the old duplicate local notification — is gone', () {
      expect(syncSource.contains('id: 9901'), isFalse);
    });
  });

  group('Admin send does not mirror one channel onto the other', () {
    test('sendPushNotification takes an explicit channel for each surface', () {
      expect(adminSource.contains('bool sendPhoneAlert'), isTrue);
      expect(adminSource.contains('bool showInAppBanner'), isTrue);
    });

    test('the FCM write is conditional, not unconditional', () {
      final start = adminSource.indexOf('Future<void> sendPushNotification(');
      expect(start, greaterThan(-1));
      final end = adminSource.indexOf('/// Settings and automated push trigger', start);
      final body = adminSource.substring(start, end);

      expect(body.contains('if (sendPhoneAlert)'), isTrue,
          reason: 'a phone alert must only go out when the admin asked for one');
      expect(body.contains('if (showInAppBanner)'), isTrue,
          reason: 'the banner must only be published when the admin asked for one');

      // The exact line that caused the bug.
      expect(
        body.contains('// Also mirror to platform_settings/broadcast'),
        isFalse,
        reason: 'the unconditional mirror is what produced the second and third '
            'notification the merchant reported',
      );
    });
  });
}
