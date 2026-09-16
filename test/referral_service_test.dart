import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/services/referral_service.dart';

void main() {
  group('Referral Service & Rewards (Module A Fixes)', () {
    final service = ReferralService.instance;

    test('Invite message includes 30 Days FREE PRO and code', () {
      final msg = service.buildInviteMessage('KAMAI9A2Z', storeName: 'Sharma General Store');
      expect(msg.contains('Sharma General Store'), true);
      expect(msg.contains('30 Days FREE PRO Access'), true);
      expect(msg.contains('KAMAI9A2Z'), true);
      expect(msg.contains('https://play.google.com/store/apps/details?id=com.kamaiplus.pos&referrer=KAMAI9A2Z'), true);
    });

    test('ReferralStats model correctly holds all counters and applied code', () {
      final stats = ReferralStats(
        totalInvited: 12,
        storesActivated: 5,
        freeDaysEarned: 150,
        appliedReferralCode: 'KAMAI7X8Y',
      );

      expect(stats.totalInvited, 12);
      expect(stats.storesActivated, 5);
      expect(stats.freeDaysEarned, 150);
      expect(stats.appliedReferralCode, 'KAMAI7X8Y');
    });

    test('Blank or empty referral code is rejected immediately', () async {
      final resEmpty = await service.applyReferralCode('');
      expect(resEmpty.success, false);
      expect(resEmpty.message.contains('Please enter a referral code'), true);

      final resSpaces = await service.applyReferralCode('   ');
      expect(resSpaces.success, false);
      expect(resSpaces.message.contains('Please enter a referral code'), true);
    });
  });
}
