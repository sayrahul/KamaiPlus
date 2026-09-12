// Regression test for a real, reported bug: "product ki quantity add karte
// time product disappear ho jata hai" / "naya product na list me aata hai na
// billing pe". Root cause traced by pulling a real test device's SQLite file
// directly: an OLDER version of quick_stock_update_modal.dart rebuilt a
// product's row from a fresh ProductModel(...) instead of copyWith(...) on
// every stock/price quick-update, silently resetting businessType to its
// constructor default ('grocery') no matter the product's real vertical.
// That code path is already fixed (see the `copyWith` comment in
// local_database.dart's neighbor, quick_stock_update_modal.dart), but a
// device that hit the bug before the fix shipped is left with rows like
// "Dolo 650 Paracetamol" permanently tagged business_type='grocery' —
// invisible to every pharmacy-scoped query, and indistinguishable from the
// product having "disappeared". `_migrateToV6` in local_database.dart
// repairs this once, for every device still carrying the damage.
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kamaiplus_pos/core/database/local_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  tearDown(() async {
    await LocalDatabase.instance.closeDatabase();
  });

  test('legacy mistagged products are repaired when the database upgrades to v6', () async {
    final userId = 'migration_v6_test_${DateTime.now().microsecondsSinceEpoch}';
    final safeId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final dbDir = await databaseFactory.getDatabasesPath();
    final dbPath = p.join(dbDir, 'kamaiplus_$safeId.db');

    // Manually build a v5 database containing exactly the corruption
    // pattern found on a real device: a correctly-tagged pharmacy product,
    // a mistagged duplicate of the SAME product wrongly tagged 'grocery',
    // and a second mistagged product that has NO correctly-tagged sibling
    // at all (the migration must repair it in place, not delete it).
    final legacyDb = await openDatabase(
      dbPath,
      version: 5,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            business_id TEXT NOT NULL,
            name TEXT NOT NULL,
            business_type TEXT DEFAULT 'grocery',
            stock_quantity REAL NOT NULL DEFAULT 0
          )
        ''');
      },
    );
    await legacyDb.insert('products', {
      'id': 'prod_pharmacy_correct',
      'business_id': 'biz_test',
      'name': 'Dolo 650 Paracetamol (Strip of 15)',
      'business_type': 'pharmacy',
      'stock_quantity': 50.0,
    });
    await legacyDb.insert('products', {
      'id': 'prod_pharmacy_corrupted_dupe',
      'business_id': 'biz_test',
      'name': 'Dolo 650 Paracetamol (Strip of 15)',
      'business_type': 'grocery',
      'stock_quantity': 50.0,
    });
    await legacyDb.insert('products', {
      'id': 'prod_pharmacy_only_copy',
      'business_id': 'biz_test',
      'name': 'Pantoprazole 40mg (Strip of 15)',
      'business_type': 'grocery',
      'stock_quantity': 25.0,
    });
    await legacyDb.close();

    // Reopen through LocalDatabase's real switchUser path — same file, but
    // now at the app's current schema version, which triggers onUpgrade.
    await LocalDatabase.instance.switchUser(userId);
    final db = await LocalDatabase.instance.database;

    final doloRows = await db.query(
      'products',
      where: 'name = ?',
      whereArgs: ['Dolo 650 Paracetamol (Strip of 15)'],
    );
    expect(
      doloRows.length,
      1,
      reason: 'the mistagged duplicate should be removed, leaving only the already-correct original',
    );
    expect(doloRows.first['id'], 'prod_pharmacy_correct');
    expect(doloRows.first['business_type'], 'pharmacy');

    final pantoRows = await db.query(
      'products',
      where: 'name = ?',
      whereArgs: ['Pantoprazole 40mg (Strip of 15)'],
    );
    expect(
      pantoRows.length,
      1,
      reason: 'the only copy must be re-tagged in place, never deleted — that would be real data loss',
    );
    expect(pantoRows.first['business_type'], 'pharmacy');
    expect(pantoRows.first['stock_quantity'], 25.0);
  });

  test('products with no matching seed-catalog name are left untouched', () async {
    final userId = 'migration_v6_test2_${DateTime.now().microsecondsSinceEpoch}';
    final safeId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final dbDir = await databaseFactory.getDatabasesPath();
    final dbPath = p.join(dbDir, 'kamaiplus_$safeId.db');

    final legacyDb = await openDatabase(
      dbPath,
      version: 5,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            business_id TEXT NOT NULL,
            name TEXT NOT NULL,
            business_type TEXT DEFAULT 'grocery',
            stock_quantity REAL NOT NULL DEFAULT 0
          )
        ''');
      },
    );
    // A merchant's own custom, non-seed product — its name isn't in
    // kDefaultProductsByVertical for any vertical, so it must never be
    // touched by the repair, no matter what it's tagged.
    await legacyDb.insert('products', {
      'id': 'prod_custom_1',
      'business_id': 'biz_test',
      'name': 'My Custom Chai Blend 250g',
      'business_type': 'grocery',
      'stock_quantity': 12.0,
    });
    await legacyDb.close();

    await LocalDatabase.instance.switchUser(userId);
    final db = await LocalDatabase.instance.database;

    final rows = await db.query('products', where: 'id = ?', whereArgs: ['prod_custom_1']);
    expect(rows.length, 1);
    expect(rows.first['business_type'], 'grocery');
    expect(rows.first['stock_quantity'], 12.0);
  });

  test('when a store profile exists, even a merchant\'s own custom-named mistagged products get swept into the store\'s one true (locked) vertical', () async {
    final userId = 'migration_v6_test3_${DateTime.now().microsecondsSinceEpoch}';
    final safeId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final dbDir = await databaseFactory.getDatabasesPath();
    final dbPath = p.join(dbDir, 'kamaiplus_$safeId.db');

    final legacyDb = await openDatabase(
      dbPath,
      version: 5,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            business_id TEXT NOT NULL,
            name TEXT NOT NULL,
            business_type TEXT DEFAULT 'grocery',
            stock_quantity REAL NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE store_profile (
            id TEXT PRIMARY KEY,
            store_name TEXT,
            business_type TEXT
          )
        ''');
      },
    );
    await legacyDb.insert('store_profile', {
      'id': 'default_store',
      'store_name': 'Rahul Pharmacy',
      'business_type': 'pharmacy',
    });
    // A merchant's own custom, non-seed-catalog product — mistagged
    // 'grocery' by the same historical bug, exactly like "test"/"qwerty"
    // entries found on a real device. There is no seed-catalog entry to
    // match this name against, so only the store-profile-driven sweep can
    // catch it.
    await legacyDb.insert('products', {
      'id': 'prod_custom_only_copy',
      'business_id': 'biz_test',
      'name': 'Ayurvedic Immunity Booster Syrup',
      'business_type': 'grocery',
      'stock_quantity': 8.0,
    });
    // A second custom product that already has a correctly-tagged sibling —
    // the mistagged copy should be deleted as a duplicate, not re-tagged
    // (which would create a visible double-entry in the merchant's list).
    await legacyDb.insert('products', {
      'id': 'prod_custom_dupe_correct',
      'business_id': 'biz_test',
      'name': 'Digital Thermometer',
      'business_type': 'pharmacy',
      'stock_quantity': 5.0,
    });
    await legacyDb.insert('products', {
      'id': 'prod_custom_dupe_wrong',
      'business_id': 'biz_test',
      'name': 'Digital Thermometer',
      'business_type': 'grocery',
      'stock_quantity': 0.0,
    });
    await legacyDb.close();

    await LocalDatabase.instance.switchUser(userId);
    final db = await LocalDatabase.instance.database;

    final booster = await db.query('products', where: 'id = ?', whereArgs: ['prod_custom_only_copy']);
    expect(booster.length, 1, reason: 'the only copy is re-tagged in place, not deleted');
    expect(booster.first['business_type'], 'pharmacy');
    expect(booster.first['stock_quantity'], 8.0);

    final thermometers = await db.query('products', where: 'name = ?', whereArgs: ['Digital Thermometer']);
    expect(thermometers.length, 1, reason: 'the mistagged duplicate is removed, leaving only the correct one');
    expect(thermometers.first['id'], 'prod_custom_dupe_correct');
    expect(thermometers.first['business_type'], 'pharmacy');
  });
}
