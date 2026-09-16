// Two things verified together because both were "looks wired up, isn't".
//
// 1. THE 7-DAY TRIAL. Signup does start it correctly (signup_store_screen.dart
//    writes proPlan 'trial', a +7d expiry and trialStartedAt). Nothing ever
//    ENDED it: `ensureFreeTrialGranted` — the only code that deactivates an
//    expired trial and clears the cached `is_pro` flag — was reached solely by
//    opening the Pro upgrade modal. A merchant who never opened that screen
//    kept `is_pro: true` in SharedPreferences forever, so anything reading the
//    cached flag (invoice_pdf_service) still treated them as Pro on day 300.
//    It is now reconciled on every launch from main.dart.
//
// 2. KHATA SETTLEMENT CASH. The Cash Register's expected cash is
//    opening float + cash SALES − expenses. A customer clearing old udhar in
//    cash is none of those, so settlements were invisible to the drawer and
//    the physical count came out over "expected" by exactly that amount.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kamaiplus_pos/core/database/local_database.dart';
import 'package:kamaiplus_pos/models/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDatabase.instance
        .switchUser('trial_settle_${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() async {
    await LocalDatabase.instance.closeDatabase();
  });

  /// Mirrors what signup_store_screen.dart writes, with a controllable start
  /// date so an expired trial can be exercised without waiting a week.
  Future<void> seedTrialStartedAt(DateTime start) async {
    final profile = StoreProfileModel(
      storeName: 'Test Kirana',
      ownerName: 'Owner',
      phone: '9000000000',
      businessType: 'grocery',
      isPro: true,
      proPlan: 'trial',
      proExpiry: start.add(const Duration(days: 7)).toIso8601String(),
      razorpayPaymentId: 'free_trial_7d',
      trialStartedAt: start.toIso8601String(),
    );
    await LocalDatabase.instance.saveStoreProfile(profile);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pro_trial_started_at', start.toIso8601String());
    await prefs.setBool('pro_trial_already_consumed', true);
    await prefs.setBool('is_pro', true);
  }

  group('7-day free trial', () {
    test('a fresh store gets a trial that is active today', () async {
      final profile = await LocalDatabase.instance.ensureFreeTrialGranted();

      expect(profile.isProEffective, isTrue);
      expect(profile.isTrialActive, isTrue);
      expect(profile.trialStartedAt, isNotEmpty);

      final expiry = DateTime.parse(profile.proExpiry);
      final days = expiry.difference(DateTime.now()).inDays;
      expect(days, inInclusiveRange(6, 7));
    });

    test('day 6 is still Pro', () async {
      await seedTrialStartedAt(DateTime.now().subtract(const Duration(days: 6)));

      final profile = await LocalDatabase.instance.ensureFreeTrialGranted();
      expect(profile.isProEffective, isTrue);
      expect(profile.isTrialActive, isTrue);
    });

    test('day 8 ends the trial — Pro locks and the cached flag is cleared', () async {
      await seedTrialStartedAt(DateTime.now().subtract(const Duration(days: 8)));

      await LocalDatabase.instance.ensureFreeTrialGranted();

      final after = await LocalDatabase.instance.getStoreProfile();
      expect(after.isProEffective, isFalse, reason: 'Pro features must lock on day 8');

      // The leak: this flag stayed true forever because nothing ever ran the
      // deactivation path outside the Pro upgrade modal.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('is_pro'), isFalse);
    });

    test('an expired trial is never silently restarted', () async {
      await seedTrialStartedAt(DateTime.now().subtract(const Duration(days: 30)));

      // Several launches in a row must not hand out a second free week.
      for (var i = 0; i < 3; i++) {
        await LocalDatabase.instance.ensureFreeTrialGranted();
      }

      final after = await LocalDatabase.instance.getStoreProfile();
      expect(after.isProEffective, isFalse);
    });

    test('a PAID plan is never downgraded by the trial reconciliation', () async {
      final paidExpiry = DateTime.now().add(const Duration(days: 300));
      await LocalDatabase.instance.saveStoreProfile(StoreProfileModel(
        storeName: 'Paid Store',
        businessType: 'grocery',
        isPro: true,
        proPlan: 'annual',
        proExpiry: paidExpiry.toIso8601String(),
        razorpayPaymentId: 'pay_real_123',
      ));

      await LocalDatabase.instance.ensureFreeTrialGranted();

      final after = await LocalDatabase.instance.getStoreProfile();
      expect(after.isProEffective, isTrue);
      expect(after.proPlan, 'annual');
      expect(after.isTrialActive, isFalse, reason: 'a paid plan is not a trial');
    });

    test('running it repeatedly on an active trial does not extend it', () async {
      final start = DateTime.now().subtract(const Duration(days: 3));
      await seedTrialStartedAt(start);

      for (var i = 0; i < 3; i++) {
        await LocalDatabase.instance.ensureFreeTrialGranted();
      }

      final after = await LocalDatabase.instance.getStoreProfile();
      final expiry = DateTime.parse(after.proExpiry);
      final expected = start.add(const Duration(days: 7));
      expect(expiry.difference(expected).inMinutes.abs(), lessThan(2),
          reason: 'expiry must stay pinned to the original start date');
    });
  });

  group('Khata settlement cash reaches the drawer', () {
    Future<CustomerModel> debtor(String id, int owedPaise) async {
      final c = CustomerModel(
        id: id,
        businessId: 'biz_settle',
        name: 'Debtor $id',
        phone: '90000000${id.length}',
        currentBalancePaise: owedPaise,
      );
      await LocalDatabase.instance.upsertCustomer(c);
      return c;
    }

    DateTime todayStart() {
      final n = DateTime.now();
      return DateTime(n.year, n.month, n.day);
    }

    test('a CASH settlement counts as cash in the drawer', () async {
      final c = await debtor('c1', 500000);

      await LocalDatabase.instance.settleMultipleCustomerSaleBills(
        saleIds: ['sale_x'],
        customer: c,
        totalAmountPaise: 500000,
        paymentMode: 'Cash Settle',
        cashReceivedPaise: 500000,
      );

      final cash = await LocalDatabase.instance
          .getSettlementCashBetween(todayStart(), todayStart().add(const Duration(days: 1)));
      expect(cash, 500000, reason: '₹5,000 physically entered the drawer');

      final after =
          (await LocalDatabase.instance.getAllCustomers()).firstWhere((x) => x.id == c.id);
      expect(after.currentBalancePaise, 0, reason: 'and the udhar is cleared');
    });

    test('a UPI settlement adds nothing to the drawer', () async {
      final c = await debtor('c2', 300000);

      await LocalDatabase.instance.settleMultipleCustomerSaleBills(
        saleIds: ['sale_y'],
        customer: c,
        totalAmountPaise: 300000,
        paymentMode: 'UPI Settle',
        cashReceivedPaise: 0,
      );

      final cash = await LocalDatabase.instance
          .getSettlementCashBetween(todayStart(), todayStart().add(const Duration(days: 1)));
      expect(cash, 0, reason: 'UPI money never touches the cash drawer');

      final after =
          (await LocalDatabase.instance.getAllCustomers()).firstWhere((x) => x.id == c.id);
      expect(after.currentBalancePaise, 0, reason: 'but the udhar is still cleared');
    });

    test('a SPLIT settlement only counts its cash half', () async {
      final c = await debtor('c3', 400000);

      await LocalDatabase.instance.settleMultipleCustomerSaleBills(
        saleIds: ['sale_z'],
        customer: c,
        totalAmountPaise: 400000,
        paymentMode: 'Split Settle',
        cashReceivedPaise: 150000,
      );

      final cash = await LocalDatabase.instance
          .getSettlementCashBetween(todayStart(), todayStart().add(const Duration(days: 1)));
      expect(cash, 150000);
    });

    test('cash recorded can never exceed the amount settled', () async {
      final c = await debtor('c4', 100000);

      // A caller passing the full tendered note rather than the amount due.
      await LocalDatabase.instance.settleMultipleCustomerSaleBills(
        saleIds: ['sale_w'],
        customer: c,
        totalAmountPaise: 100000,
        paymentMode: 'Cash Settle',
        cashReceivedPaise: 200000,
      );

      final cash = await LocalDatabase.instance
          .getSettlementCashBetween(todayStart(), todayStart().add(const Duration(days: 1)));
      expect(cash, 100000, reason: 'change handed back is not drawer money');
    });

    test("yesterday's settlement does not inflate today's drawer", () async {
      final c = await debtor('c5', 250000);
      await LocalDatabase.instance.settleMultipleCustomerSaleBills(
        saleIds: ['sale_v'],
        customer: c,
        totalAmountPaise: 250000,
        paymentMode: 'Cash Settle',
        cashReceivedPaise: 250000,
      );

      final yStart = todayStart().subtract(const Duration(days: 1));
      final cashYesterday =
          await LocalDatabase.instance.getSettlementCashBetween(yStart, todayStart());
      expect(cashYesterday, 0);
    });

    test('a settlement made before this column existed reads as zero cash', () async {
      // Legacy ledger rows carry no cash_amount_paise. Guessing that an old
      // entry was cash would invent drawer money that was never counted.
      final c = await debtor('c6', 90000);
      final db = await LocalDatabase.instance.database;
      await db.insert('ledger_transactions', {
        'id': 'legacy_1',
        'business_id': 'biz_settle',
        'customer_id': c.id,
        'type': 'debit',
        'amount_paise': 90000,
        'balance_after_paise': 0,
        'description': 'Legacy Settle',
        'reference_id': 'old',
        'created_at': DateTime.now().toIso8601String(),
        'sync_status': 'synced',
      });

      final cash = await LocalDatabase.instance
          .getSettlementCashBetween(todayStart(), todayStart().add(const Duration(days: 1)));
      expect(cash, 0);
    });
  });
}
