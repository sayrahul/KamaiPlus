// Refer & Earn, app side (ReferralService + the Pro reconcile it depends on).
//
// Drives the real local database through FFI SQLite and swaps only the
// network for a fake `referral` Cloud Function, so each test exercises what a
// merchant's phone actually does. Server-side rules (who gets how many days,
// abuse checks) are covered in functions/test/referral_core.test.js.
//
// Bugs pinned here:
//  * claims never reached a working server, so no days were ever added;
//  * the launch-time trial reconcile rewrote any plan that was not exactly
//    'trial' back to "trial, ends day 7" during the first week — wiping
//    referral days and even a paid plan — and after day 7 deactivated
//    referral days that had weeks left.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kamaiplus_pos/core/database/local_database.dart';
import 'package:kamaiplus_pos/models/models.dart';
import 'package:kamaiplus_pos/services/referral_service.dart';

final service = ReferralService.instance;

/// Starts a merchant on the normal 7-day trial, [daysAgo] days ago.
Future<DateTime> startTrial({int daysAgo = 0}) async {
  final start = DateTime.now().subtract(Duration(days: daysAgo));
  await SharedPreferences.getInstance().then((p) async {
    await p.setString('pro_trial_started_at', start.toIso8601String());
    await p.setBool('pro_trial_already_consumed', true);
  });
  await LocalDatabase.instance.saveStoreProfile(StoreProfileModel(
    storeName: 'Ravi Stores',
    businessType: 'grocery',
    isPro: true,
    proPlan: 'trial',
    proExpiry: start.add(const Duration(days: 7)).toIso8601String(),
    razorpayPaymentId: 'free_trial_7d',
    trialStartedAt: start.toIso8601String(),
  ));
  return start;
}

/// A fake `referral` function. Records every call.
class FakeServer {
  final calls = <Map<String, dynamic>>[];
  ReferralHttpResponse Function(Map<String, dynamic> body) reply;
  bool offline = false;

  FakeServer(this.reply);

  Future<ReferralHttpResponse> call(Map<String, dynamic> body) async {
    calls.add(body);
    if (offline) throw Exception('SocketException: network unreachable');
    return reply(body);
  }
}

ReferralHttpResponse grant(DateTime expiry, {String plan = 'referral_bonus'}) => ReferralHttpResponse(200, {
      'ok': true,
      'already_redeemed': false,
      'code': 'KAMAIASHA',
      'referee_bonus_days': 15,
      'pro_plan': plan,
      'pro_expiry': expiry.toUtc().toIso8601String(),
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDatabase.instance.switchUser('referral_test_${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() async {
    service.transportOverride = null;
    await LocalDatabase.instance.closeDatabase();
  });

  test('invite message promises the invitee 7-day trial + 15 days', () {
    final msg = service.buildInviteMessage('KAMAI9A2Z', storeName: 'Sharma General Store');
    expect(msg, contains('Sharma General Store'));
    expect(msg, contains('22 Days FREE PRO'));
    expect(msg, contains('7-day trial + 15 bonus days'));
    expect(msg, contains('KAMAI9A2Z'));
    expect(msg, contains('https://play.google.com/store/apps/details?id=com.kamaiplus.pos&referrer=KAMAI9A2Z'));
  });

  test('blank, malformed and own codes are refused without a network call', () async {
    final server = FakeServer((_) => fail('must not reach the server'));
    service.transportOverride = server.call;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('merchant_referral_code', 'KAMAIRAVI');

    expect((await service.applyReferralCode('   ')).message, contains('Please enter a referral code'));
    expect((await service.applyReferralCode('hello123')).errorCode, 'INVALID_FORMAT');
    expect((await service.applyReferralCode('kamairavi')).errorCode, 'SELF');
    expect(server.calls, isEmpty);
  });

  test('a successful claim moves the Pro counter to trial end + 15 days at once', () async {
    final start = await startTrial();
    final expected = start.add(const Duration(days: 22));
    final server = FakeServer((_) => grant(expected));
    service.transportOverride = server.call;

    final result = await service.applyReferralCode(' kamai asha ');

    expect(result.success, isTrue);
    expect(result.message, contains('+15 days'));
    expect(server.calls.single, {'action': 'redeem', 'code': 'KAMAIASHA'});

    final profile = await LocalDatabase.instance.getStoreProfile();
    expect(profile.proExpiryDate!.isAtSameMomentAs(expected), isTrue, reason: 'the counter reads pro_expiry');
    expect(profile.proPlan, 'referral_bonus');
    expect(profile.isTrialActive, isTrue, reason: 'free Pro — the countdown card must stay visible');
    expect((await service.getCachedStats()).appliedReferralCode, 'KAMAIASHA');

    final again = await service.applyReferralCode('KAMAIMEEN');
    expect(again.errorCode, 'ALREADY_REDEEMED');
  });

  test('launch reconcile keeps referral days during the first week and after it', () async {
    // Day 2 of the trial, 15 referral days on top.
    var start = await startTrial(daysAgo: 2);
    service.transportOverride = FakeServer((_) => grant(start.add(const Duration(days: 22)))).call;
    await service.applyReferralCode('KAMAIASHA');

    var profile = await LocalDatabase.instance.ensureFreeTrialGranted();
    expect(profile.proPlan, 'referral_bonus', reason: 'used to be reset to "trial" on every launch in week one');
    expect(profile.proExpiryDate!.isAtSameMomentAs(start.add(const Duration(days: 22))), isTrue);

    // Day 10: the 7-day trial is over, the referral days are not.
    SharedPreferences.setMockInitialValues({});
    await LocalDatabase.instance.switchUser('referral_test_b_${DateTime.now().microsecondsSinceEpoch}');
    start = await startTrial(daysAgo: 10);
    service.transportOverride = FakeServer((_) => grant(start.add(const Duration(days: 22)))).call;
    await service.applyReferralCode('KAMAIASHA');

    profile = await LocalDatabase.instance.ensureFreeTrialGranted();
    expect(profile.isProEffective, isTrue, reason: 'used to be deactivated the day after day 7');
    expect(profile.proExpiryDate!.isAtSameMomentAs(start.add(const Duration(days: 22))), isTrue);
  });

  test('the inviter\'s +30 days (arriving from the cloud) survive launch too', () async {
    final start = await startTrial(daysAgo: 3);
    // What FirestoreSyncService's live listener writes when the server
    // credits this merchant for an invite.
    final rewarded = start.add(const Duration(days: 37));
    await LocalDatabase.instance.activateProMembership(
      plan: 'referral_bonus',
      paymentId: 'admin_granted',
      expiryDate: rewarded,
    );

    final profile = await LocalDatabase.instance.ensureFreeTrialGranted();
    expect(profile.proExpiryDate!.isAtSameMomentAs(rewarded), isTrue);
  });

  test('a plan bought during the trial week is no longer reset to the trial', () async {
    await startTrial(daysAgo: 1);
    final paidTill = DateTime.now().add(const Duration(days: 365));
    await LocalDatabase.instance.activateProMembership(plan: 'annual', paymentId: 'pay_123', expiryDate: paidTill);

    final profile = await LocalDatabase.instance.ensureFreeTrialGranted();
    expect(profile.proPlan, 'annual');
    expect(profile.proExpiryDate!.isAtSameMomentAs(paidTill), isTrue);
  });

  test('referral time that has run out is switched off like an expired trial', () async {
    final start = await startTrial(daysAgo: 30);
    await LocalDatabase.instance.activateProMembership(
      plan: 'referral_bonus',
      paymentId: 'ref_bonus_KAMAIASHA',
      expiryDate: start.add(const Duration(days: 22)),
    );

    final profile = await LocalDatabase.instance.ensureFreeTrialGranted();
    expect(profile.isProEffective, isFalse);
    expect((await SharedPreferences.getInstance()).getBool('is_pro'), isFalse);
  });

  test('offline claim is kept and completed automatically once online', () async {
    final start = await startTrial();
    final server = FakeServer((_) => grant(start.add(const Duration(days: 22))))..offline = true;
    service.transportOverride = server.call;

    final offline = await service.applyReferralCode('KAMAIASHA');
    expect(offline.success, isFalse);
    expect(offline.retryable, isTrue);
    expect((await service.getCachedStats()).pendingReferralCode, 'KAMAIASHA');

    server.offline = false;
    final later = await service.redeemPendingReferral();
    expect(later!.success, isTrue);
    expect((await service.getCachedStats()).pendingReferralCode, isNull);
    final profile = await LocalDatabase.instance.getStoreProfile();
    expect(profile.proExpiryDate!.isAtSameMomentAs(start.add(const Duration(days: 22))), isTrue);
    expect(await service.redeemPendingReferral(), isNull, reason: 'nothing left to do');
  });

  test('a code the server rejects is not kept and changes nothing', () async {
    final start = await startTrial();
    service.transportOverride = FakeServer((_) => const ReferralHttpResponse(404, {
          'code': 'NOT_FOUND',
          'error': 'Invalid referral code. Please check the code and try again.',
        })).call;

    final result = await service.applyReferralCode('KAMAIZZZZ');
    expect(result.success, isFalse);
    expect(result.retryable, isFalse);
    expect(result.message, contains('Invalid referral code'));

    final stats = await service.getCachedStats();
    expect(stats.pendingReferralCode, isNull);
    expect(stats.appliedReferralCode, isNull);
    final profile = await LocalDatabase.instance.getStoreProfile();
    expect(profile.proExpiryDate!.isAtSameMomentAs(start.add(const Duration(days: 7))), isTrue);
  });

  test('a code "applied" by the old app is sent to the server once', () async {
    final start = await startTrial(daysAgo: 1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('referral_applied_code', 'KAMAIASHA'); // old signup stored only this
    final server = FakeServer((_) => grant(start.add(const Duration(days: 22))));
    service.transportOverride = server.call;

    expect((await service.redeemPendingReferral())!.success, isTrue);
    expect(await service.redeemPendingReferral(), isNull, reason: 'confirmed now; never re-sent');
    expect(server.calls, hasLength(1));
  });

  test('an old applied code the server does not know is cleared so a valid one can be entered', () async {
    await startTrial(daysAgo: 1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('referral_applied_code', 'KAMAI1234'); // typed freely under the old flow
    service.transportOverride = FakeServer((_) => const ReferralHttpResponse(404, {'code': 'NOT_FOUND', 'error': 'Invalid'})).call;

    await service.redeemPendingReferral();
    expect((await service.getCachedStats()).appliedReferralCode, isNull);
  });

  test('stats come from the server and fall back to the cache offline', () async {
    final server = FakeServer((body) {
      expect(body['action'], 'status');
      return const ReferralHttpResponse(200, {
        'code': 'KAMAIASHA',
        'activated_count': 3,
        'free_days_earned': 90,
        'applied_code': null,
      });
    });
    service.transportOverride = server.call;

    final live = await service.getStats();
    expect(live.isLive, isTrue);
    expect(live.code, 'KAMAIASHA');
    expect(live.storesActivated, 3);
    expect(live.freeDaysEarned, 90);

    server.offline = true;
    final cached = await service.getStats();
    expect(cached.isLive, isFalse);
    expect(cached.code, 'KAMAIASHA');
    expect(cached.freeDaysEarned, 90);
  });
}
