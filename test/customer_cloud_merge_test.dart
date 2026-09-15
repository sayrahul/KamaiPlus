// Regression test for the September 2026 audit finding: a customer's GSTIN,
// state code, address and VIP flag were silently erased seconds after being
// saved.
//
// Mechanism: customers are persisted with a full-row REPLACE (upsertCustomer),
// and FirestoreSyncService's live customers listener fires on the app's OWN
// writes too, because Firestore echoes every write straight back as a snapshot
// change. That listener used to rebuild CustomerModel from four cloud fields
// only (name, phone, balance, credit limit), so the echo of the merchant's own
// save wrote NULL over gstin/state_code/address and reset is_vip to false.
//
// Compounding it, pushCustomerToCloud never wrote gstin or state_code at all,
// so those fields could not survive a round trip even in principle.
//
// Losing gstin is a billing bug rather than a cosmetic one: processPosBill
// reads customer.gstin to set a B2B invoice's place of supply.
import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/models/models.dart';
import 'package:kamaiplus_pos/services/firestore_sync_service.dart';

void main() {
  CustomerModel localCustomer({
    String? gstin = '27ABCDE1234F1Z5',
    String? stateCode = '27',
    String? address = 'Shop 4, Main Bazaar',
    bool isVip = true,
    int balancePaise = 250000,
    int limitPaise = 900000,
  }) =>
      CustomerModel(
        id: 'cust_1',
        businessId: 'biz_test',
        name: 'Ramesh Traders',
        phone: '9876543210',
        address: address,
        gstin: gstin,
        stateCode: stateCode,
        currentBalancePaise: balancePaise,
        creditLimitPaise: limitPaise,
        isVip: isVip,
      );

  CustomerModel merge(Map<String, dynamic> cloud, CustomerModel? local) =>
      FirestoreSyncService.mergeCloudCustomer(
        id: 'cust_1',
        businessId: 'biz_test',
        data: cloud,
        local: local,
      );

  group('echo of the app\'s own write', () {
    test('a full payload round-trips every field intact', () {
      final local = localCustomer();

      // Exactly the shape pushCustomerToCloud now writes.
      final echoed = merge({
        'id': 'cust_1',
        'name': 'Ramesh Traders',
        'phone': '9876543210',
        'address': 'Shop 4, Main Bazaar',
        'gstin': '27ABCDE1234F1Z5',
        'state_code': '27',
        'current_balance': 250000,
        'current_balance_paise': 250000,
        'credit_limit_paise': 900000,
        'is_vip': true,
        'customer_type': 'vip',
      }, local);

      expect(echoed.gstin, '27ABCDE1234F1Z5');
      expect(echoed.stateCode, '27');
      expect(echoed.address, 'Shop 4, Main Bazaar');
      expect(echoed.isVip, isTrue);
      expect(echoed.currentBalancePaise, 250000);
      expect(echoed.creditLimitPaise, 900000);
    });

    test('a legacy doc missing the new fields keeps the device values', () {
      final local = localCustomer();

      // A document written by an older build of the app, or by the admin
      // console, which simply has no gstin/state_code/is_vip keys.
      final echoed = merge({
        'name': 'Ramesh Traders',
        'phone': '9876543210',
        'current_balance_paise': 250000,
        'credit_limit_paise': 900000,
      }, local);

      expect(echoed.gstin, '27ABCDE1234F1Z5',
          reason: 'an absent key must never blank a field the device holds');
      expect(echoed.stateCode, '27');
      expect(echoed.address, 'Shop 4, Main Bazaar');
      expect(echoed.isVip, isTrue);
    });

    test('a doc missing balance and limit does not zero a real khata balance', () {
      final echoed = merge({'name': 'Ramesh Traders'}, localCustomer());

      expect(echoed.currentBalancePaise, 250000,
          reason: 'wiping udhaar owed to the merchant is real financial loss');
      expect(echoed.creditLimitPaise, 900000,
          reason: 'a custom credit limit must not silently revert to the default');
    });
  });

  group('cloud changes still win', () {
    test('a deliberately cleared field is applied, not reverted', () {
      final echoed = merge({
        'name': 'Ramesh Traders',
        'phone': '9876543210',
        'gstin': '',
        'state_code': '',
        'address': '',
      }, localCustomer());

      expect(echoed.gstin, isNull,
          reason: 'present-but-empty means the merchant cleared it on purpose');
      expect(echoed.stateCode, isNull);
      expect(echoed.address, isNull);
    });

    test('an edit made on another device is applied', () {
      final echoed = merge({
        'name': 'Ramesh Traders & Sons',
        'phone': '9000000001',
        'gstin': '29XYZAB5678C1D2',
        'is_vip': false,
        'current_balance_paise': 0,
      }, localCustomer());

      expect(echoed.name, 'Ramesh Traders & Sons');
      expect(echoed.phone, '9000000001');
      expect(echoed.gstin, '29XYZAB5678C1D2');
      expect(echoed.isVip, isFalse);
      expect(echoed.currentBalancePaise, 0);
    });

    test('state code is derived from a new GSTIN when the cloud omits it', () {
      final echoed = merge({
        'name': 'Ramesh Traders',
        'gstin': '29XYZAB5678C1D2',
      }, localCustomer(stateCode: null));

      expect(echoed.stateCode, '29');
    });
  });

  group('legacy VIP encoding', () {
    test('customer_type vip is honoured when is_vip is absent', () {
      final echoed = merge({
        'name': 'Ramesh Traders',
        'customer_type': 'vip',
      }, localCustomer(isVip: false));

      expect(echoed.isVip, isTrue);
    });

    test('customer_type credit clears VIP when is_vip is absent', () {
      final echoed = merge({
        'name': 'Ramesh Traders',
        'customer_type': 'credit',
      }, localCustomer(isVip: true));

      expect(echoed.isVip, isFalse);
    });
  });

  test('a customer that exists only in the cloud still restores cleanly', () {
    final restored = merge({
      'name': 'New Cloud Customer',
      'phone': '9123456780',
      'gstin': '07LMNOP9999Q1R2',
      'current_balance_paise': 5000,
      'credit_limit_paise': 500000,
      'is_vip': false,
    }, null);

    expect(restored.name, 'New Cloud Customer');
    expect(restored.phone, '9123456780');
    expect(restored.gstin, '07LMNOP9999Q1R2');
    expect(restored.stateCode, '07');
    expect(restored.currentBalancePaise, 5000);
    expect(restored.isVip, isFalse);
  });
}
