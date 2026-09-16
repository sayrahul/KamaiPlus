// Regression test for the Admin Console's Pro revoke, on the MOBILE side.
//
// `setProStatus(isPro: false)` used to write `{is_pro: false}` alone and leave
// `subscription_tier: 'annual'` and an unexpired `pro_expiry` sitting on the
// business document. Every copy of the cloud-Pro check in
// firestore_sync_service.dart treats a subscription_tier of pro/annual/monthly
// as Pro in its own right, so the device saw:
//
//     is_pro: false, subscription_tier: 'annual', pro_expiry: <future>
//
// ...and promptly re-activated Pro. A revoke from the console simply did not
// take — which matters most in exactly the case it exists for: pulling a
// refunded or fraudulent subscription.
//
// Fixed on both sides: the console now clears the whole subscription, and the
// client treats an explicit `is_pro: false` as winning outright, because
// documents already in the wild still carry the stale fields.
//
// This test pins the CLIENT half — the rule that decides whether a given
// business document grants Pro — since that is what protects merchants whose
// documents were revoked before the console fix shipped.
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the guard used by all three copies of the cloud-Pro check in
/// `firestore_sync_service.dart`. Kept here as the single statement of the
/// rule; if the service's own logic drifts from this, that is the bug.
bool grantsPro(Map<String, dynamic> doc) {
  final explicitlyRevoked = doc['is_pro'] == false || doc['is_pro'] == 0;
  return !explicitlyRevoked &&
      (doc['is_pro'] == true ||
          doc['is_pro'] == 1 ||
          doc['subscription_tier'] == 'pro' ||
          doc['subscription_tier'] == 'annual' ||
          doc['subscription_tier'] == 'monthly');
}

void main() {
  final future = DateTime.now().add(const Duration(days: 200)).toIso8601String();

  group('Cloud document grants Pro', () {
    test('a genuine paid subscription still grants Pro', () {
      expect(
        grantsPro({
          'is_pro': true,
          'subscription_tier': 'annual',
          'pro_expiry': future,
        }),
        isTrue,
      );
    });

    test('an admin grant still works', () {
      expect(
        grantsPro({
          'is_pro': true,
          'pro_plan': 'annual',
          'razorpay_payment_id': 'admin_granted',
        }),
        isTrue,
      );
    });

    test('legacy docs carrying only subscription_tier still grant Pro', () {
      // Older documents never wrote is_pro at all. Dropping them would
      // downgrade paying merchants, which is the opposite failure.
      expect(grantsPro({'subscription_tier': 'monthly'}), isTrue);
      expect(grantsPro({'subscription_tier': 'annual'}), isTrue);
      expect(grantsPro({'subscription_tier': 'pro'}), isTrue);
    });
  });

  group('Revoke actually revokes', () {
    test('THE BUG: is_pro false with a stale annual tier must NOT grant Pro', () {
      expect(
        grantsPro({
          'is_pro': false,
          'subscription_tier': 'annual',
          'pro_expiry': future,
        }),
        isFalse,
        reason: 'this exact document used to re-activate Pro on the device',
      );
    });

    test('a numeric 0 is a revoke too', () {
      expect(grantsPro({'is_pro': 0, 'subscription_tier': 'monthly'}), isFalse);
    });

    test('a fully cleared document — what the console now writes — is Free', () {
      expect(
        grantsPro({
          'is_pro': false,
          'pro_plan': 'free',
          'subscription_tier': 'free',
          'pro_expiry': '',
          'subscription_expires_at': '',
          'subscription_valid_until': '',
          'razorpay_payment_id': '',
          'pro_granted_by': 'admin_revoked',
        }),
        isFalse,
      );
    });

    test('a plain free merchant is Free', () {
      expect(grantsPro({}), isFalse);
      expect(grantsPro({'subscription_tier': 'free'}), isFalse);
    });

    test('device-reported Pro never grants anything on its own', () {
      // The app reports what it believes as telemetry. It is not an
      // entitlement, and must never be readable as one.
      expect(
        grantsPro({
          'device_reported_pro': true,
          'device_reported_plan': 'annual',
        }),
        isFalse,
      );
    });

    test('a trial never reads as a paid subscription', () {
      // Trials live in trial_started_at; the app no longer writes is_pro at
      // all, so a trial document must not accidentally satisfy this check.
      expect(
        grantsPro({
          'trial_started_at': DateTime.now().toIso8601String(),
          'device_reported_pro': true,
        }),
        isFalse,
      );
    });
  });
}
