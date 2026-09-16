// Two separate merchant-reported bugs, both about state that looked saved and
// was not:
//
//  1. The Note & Tally cash counter reverted to all zeros on reopen. The count
//     lived in a `setState` field on CashRegisterScreen, and the Home tab's
//     entry point passed neither an initial value nor an onSaved callback —
//     so "Confirm Count" appeared to save and saved nothing.
//
//  2. Sales return accepted the string literals '1234' and '0000' regardless
//     of the owner's actual PIN. Changing the PIN behind the eye button changed
//     nothing about refunds: the factory default stayed valid forever, on the
//     one screen that hands cash back over the counter.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kamaiplus_pos/services/cash_tally_draft_service.dart';
import 'package:kamaiplus_pos/services/owner_pin_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CashTallyDraftService', () {
    test('a confirmed count survives being reloaded', () async {
      await CashTallyDraftService.instance.save(
        denominations: {500: 4, 200: 3, 100: 2, 50: 0, 20: 1, 10: 0, 5: 0, 2: 0, 1: 0},
        countedPaise: 282000, // 2000 + 600 + 200 + 20 = 2820
        expectedPaise: 282000,
      );

      final draft = await CashTallyDraftService.instance.load();
      expect(draft, isNotNull);
      expect(draft!.denominations[500], 4);
      expect(draft.denominations[200], 3);
      expect(draft.denominations[100], 2);
      expect(draft.countedPaise, 282000);
    });

    test('no count today reads as null rather than an empty tally', () async {
      expect(await CashTallyDraftService.instance.load(), isNull);
    });

    test('variance against the expected drawer is recorded, not recomputed later', () async {
      await CashTallyDraftService.instance.save(
        denominations: {500: 2},
        countedPaise: 100000,
        expectedPaise: 120000,
      );

      final draft = await CashTallyDraftService.instance.load();
      // The expected figure moves with every sale. Storing it with the count
      // is what keeps the variance a statement about the moment of counting.
      expect(draft!.expectedPaise, 120000);
      expect(draft.variancePaise, -20000, reason: '₹200 short');
      expect(draft.isMatched, isFalse);
    });

    test('an exact count reports as matched', () async {
      await CashTallyDraftService.instance.save(
        denominations: {100: 5},
        countedPaise: 50000,
        expectedPaise: 50000,
      );
      final draft = await CashTallyDraftService.instance.load();
      expect(draft!.isMatched, isTrue);
      expect(draft.variancePaise, 0);
    });

    test('an excess is positive and a shortfall negative', () async {
      await CashTallyDraftService.instance.save(
        denominations: {500: 3},
        countedPaise: 150000,
        expectedPaise: 120000,
      );
      final draft = await CashTallyDraftService.instance.load();
      expect(draft!.variancePaise, 30000);
    });

    test('clearing removes today\'s count', () async {
      await CashTallyDraftService.instance.save(
        denominations: {100: 1},
        countedPaise: 10000,
        expectedPaise: 10000,
      );
      expect(await CashTallyDraftService.instance.load(), isNotNull);

      await CashTallyDraftService.instance.clearToday();
      expect(await CashTallyDraftService.instance.load(), isNull);
    });

    test('a draft stored under a previous day is not shown as today\'s count', () async {
      // Yesterday's drawer count presented as today's opening figure would be
      // worse than showing nothing — it looks authoritative and is wrong.
      SharedPreferences.setMockInitialValues({
        'cash_tally_draft_2020-01-01':
            '{"denominations":{"500":10},"counted_paise":500000,"expected_paise":500000,"saved_at":"2020-01-01T10:00:00.000"}',
      });
      expect(await CashTallyDraftService.instance.load(), isNull);
    });

    test('saving prunes drafts from earlier days', () async {
      SharedPreferences.setMockInitialValues({
        'cash_tally_draft_2020-01-01': '{"denominations":{"500":10},"counted_paise":1,"expected_paise":1,"saved_at":"2020-01-01T10:00:00.000"}',
        'cash_tally_draft_2020-01-02': '{"denominations":{"500":10},"counted_paise":1,"expected_paise":1,"saved_at":"2020-01-02T10:00:00.000"}',
        'unrelated_setting': 'keep me',
      });

      await CashTallyDraftService.instance.save(
        denominations: {100: 1},
        countedPaise: 10000,
        expectedPaise: 10000,
      );

      final prefs = await SharedPreferences.getInstance();
      final drafts = prefs.getKeys().where((k) => k.startsWith('cash_tally_draft_')).toList();
      expect(drafts.length, 1, reason: 'a new key every day would grow forever');
      expect(prefs.getString('unrelated_setting'), 'keep me');
    });

    test('corrupt stored JSON reads as no draft instead of throwing', () async {
      SharedPreferences.setMockInitialValues({
        'cash_tally_draft_${_todayKeyIst()}': 'not json at all',
      });
      expect(await CashTallyDraftService.instance.load(), isNull);
    });
  });

  group('OwnerPinService', () {
    test('a fresh install accepts the documented default', () async {
      expect(await OwnerPinService.instance.verify('1234'), isTrue);
      expect(await OwnerPinService.instance.isUsingDefaultPin(), isTrue);
    });

    test('once the owner sets a PIN, only that PIN works', () async {
      await OwnerPinService.instance.setPin('8642');

      expect(await OwnerPinService.instance.verify('8642'), isTrue);
      // This is the bug: the return flow used to accept 1234 forever.
      expect(await OwnerPinService.instance.verify('1234'), isFalse,
          reason: 'the old default must stop working once a PIN is set');
      expect(await OwnerPinService.instance.isUsingDefaultPin(), isFalse);
    });

    test("'0000' is not a second master PIN", () async {
      // The return flow accepted '0000' alongside '1234', so a shop that had
      // dutifully changed their PIN still had two publicly-known codes that
      // authorised a cash refund.
      expect(await OwnerPinService.instance.verify('0000'), isFalse);

      await OwnerPinService.instance.setPin('8642');
      expect(await OwnerPinService.instance.verify('0000'), isFalse);
    });

    test('the PIN set on the eye button is the PIN the return flow reads', () async {
      // One key, one source of truth — that is the whole fix.
      await OwnerPinService.instance.setPin('4321');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('owner_cashier_pin'), '4321',
          reason: 'must stay the key the privacy modal already used, or every '
              'install silently resets to the default');
    });

    test('wrong-length input is rejected without touching storage', () async {
      await OwnerPinService.instance.setPin('8642');
      for (final bad in ['', '1', '123', '12345', '86420']) {
        expect(await OwnerPinService.instance.verify(bad), isFalse);
      }
      expect(await OwnerPinService.instance.verify('8642'), isTrue);
    });

    test('a PIN that is not four digits is not saved', () async {
      await OwnerPinService.instance.setPin('8642');
      await OwnerPinService.instance.setPin('12');
      expect(await OwnerPinService.instance.getPin(), '8642',
          reason: 'a rejected change must not silently blank the PIN');
    });

    test('surrounding whitespace does not defeat verification', () async {
      await OwnerPinService.instance.setPin('8642');
      expect(await OwnerPinService.instance.verify(' 8642 '), isTrue);
    });
  });
}

String _todayKeyIst() {
  final ist = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  return '${ist.year.toString().padLeft(4, '0')}-'
      '${ist.month.toString().padLeft(2, '0')}-'
      '${ist.day.toString().padLeft(2, '0')}';
}
