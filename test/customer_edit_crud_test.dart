// Covers the Update half of Customer CRM, which shipped missing: the customer
// detail sheet offered a delete (bin) icon and nothing else, and a repo-wide
// search for editCustomer / _showEditCustomer / updateCustomer returned nothing
// at all. Create, Read and Delete existed; Update did not.
//
// The fix reuses LocalDatabase.upsertCustomer rather than adding a second write
// path — it is already keyed on id with ConflictAlgorithm.replace, so it IS the
// update. These tests pin the properties the edit screen depends on, all of
// which are ways an "edit" could quietly corrupt data:
//
//   * keeping the id, so an edit updates instead of inserting a twin and
//     stranding the original's khata ledger;
//   * carrying currentBalancePaise forward, since udhaar owed is ledger-derived
//     money that a name or credit-limit change must never rewrite;
//   * the duplicate-phone check not firing on the customer being edited.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kamaiplus_pos/core/database/local_database.dart';
import 'package:kamaiplus_pos/models/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await LocalDatabase.instance
        .switchUser('cust_edit_${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() async {
    await LocalDatabase.instance.closeDatabase();
  });

  CustomerModel seed() => CustomerModel(
        id: 'cust_1',
        businessId: 'biz_starter_pos',
        name: 'Ramesh Kumar',
        phone: '9876543210',
        address: 'Shop 4, Main Bazaar',
        gstin: '27ABCDE1234F1Z5',
        stateCode: '27',
        currentBalancePaise: 250000,
        creditLimitPaise: 500000,
        isVip: false,
      );

  test('editing updates in place instead of creating a twin', () async {
    await LocalDatabase.instance.upsertCustomer(seed());

    // What the edit modal now saves: same id, changed details.
    await LocalDatabase.instance.upsertCustomer(CustomerModel(
      id: 'cust_1',
      businessId: 'biz_starter_pos',
      name: 'Ramesh Kumar & Sons',
      phone: '9876500000',
      address: 'Shop 4, Main Bazaar',
      gstin: '27ABCDE1234F1Z5',
      stateCode: '27',
      currentBalancePaise: 250000,
      creditLimitPaise: 900000,
      isVip: true,
    ));

    final all = await LocalDatabase.instance.getAllCustomers();
    expect(all.length, 1, reason: 'a new id here would orphan the khata ledger');
    expect(all.first.name, 'Ramesh Kumar & Sons');
    expect(all.first.phone, '9876500000');
    expect(all.first.creditLimitPaise, 900000);
    expect(all.first.isVip, isTrue);
  });

  test('an edit does not disturb the khata balance or its ledger', () async {
    await LocalDatabase.instance.upsertCustomer(seed());

    await LocalDatabase.instance.recordCustomerLedgerEntry(
      customer: seed(),
      type: 'credit',
      amountPaise: 250000,
      description: 'Opening udhaar',
    );

    final before = await LocalDatabase.instance.getCustomerById('cust_1');
    final ledgerBefore =
        await LocalDatabase.instance.getLedgerForCustomer('cust_1');
    expect(ledgerBefore, isNotEmpty);

    // Edit only the name, carrying the balance forward as the modal does.
    await LocalDatabase.instance.upsertCustomer(CustomerModel(
      id: 'cust_1',
      businessId: 'biz_starter_pos',
      name: 'Ramesh Traders',
      phone: before!.phone,
      address: before.address,
      gstin: before.gstin,
      stateCode: before.stateCode,
      currentBalancePaise: before.currentBalancePaise,
      creditLimitPaise: before.creditLimitPaise,
      isVip: before.isVip,
    ));

    final after = await LocalDatabase.instance.getCustomerById('cust_1');
    expect(after!.name, 'Ramesh Traders');
    expect(after.currentBalancePaise, before.currentBalancePaise,
        reason: 'renaming a customer must not move money');

    final ledgerAfter =
        await LocalDatabase.instance.getLedgerForCustomer('cust_1');
    expect(ledgerAfter.length, ledgerBefore.length,
        reason: 'the ledger belongs to the id, which the edit preserved');
  });

  test('fields absent from the edit form survive the save', () async {
    await LocalDatabase.instance.upsertCustomer(seed());
    final before = await LocalDatabase.instance.getCustomerById('cust_1');

    // The form has no address input. Carrying it forward is what stops the
    // full-row replace from blanking it.
    await LocalDatabase.instance.upsertCustomer(CustomerModel(
      id: 'cust_1',
      businessId: 'biz_starter_pos',
      name: 'Ramesh Kumar',
      phone: '9876543210',
      address: before!.address,
      gstin: '29XYZAB5678C1D2',
      stateCode: '29',
      currentBalancePaise: before.currentBalancePaise,
      creditLimitPaise: before.creditLimitPaise,
      isVip: before.isVip,
    ));

    final after = await LocalDatabase.instance.getCustomerById('cust_1');
    expect(after!.address, 'Shop 4, Main Bazaar');
    expect(after.gstin, '29XYZAB5678C1D2');
    expect(after.stateCode, '29');
  });

  test('the duplicate-phone lookup finds the customer being edited', () async {
    await LocalDatabase.instance.upsertCustomer(seed());

    // Saving an edit without changing the phone hits this lookup. The screen
    // compares ids so that finding yourself is not treated as a clash.
    final found =
        await LocalDatabase.instance.findCustomerByPhone('9876543210');
    expect(found, isNotNull);
    expect(found!.id, 'cust_1',
        reason: 'the screen must recognise this as the same customer, not a '
            'different one already using the number');
  });

  test('a genuine phone clash is still a different customer', () async {
    await LocalDatabase.instance.upsertCustomer(seed());
    await LocalDatabase.instance.upsertCustomer(CustomerModel(
      id: 'cust_2',
      businessId: 'biz_starter_pos',
      name: 'Suresh',
      phone: '9000000002',
    ));

    final found =
        await LocalDatabase.instance.findCustomerByPhone('9000000002');
    expect(found!.id, 'cust_2');
    expect(found.id, isNot('cust_1'));
  });

  test('deleting a customer takes their ledger with them', () async {
    await LocalDatabase.instance.upsertCustomer(seed());
    await LocalDatabase.instance.recordCustomerLedgerEntry(
      customer: seed(),
      type: 'credit',
      amountPaise: 100000,
      description: 'Udhaar',
    );

    await LocalDatabase.instance.deleteCustomer('cust_1');

    expect(await LocalDatabase.instance.getCustomerById('cust_1'), isNull);
    expect(await LocalDatabase.instance.getLedgerForCustomer('cust_1'), isEmpty,
        reason: 'this is exactly why the delete dialog now warns when the '
            'customer still owes money — the proof goes too');
  });
}
