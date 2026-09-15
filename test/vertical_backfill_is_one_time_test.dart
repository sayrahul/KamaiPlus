// Regression test for the highest-severity bug found in the September 2026
// architecture audit: "stock is added via Purchase/Restock, but after some
// time it gets deleted/reverts on its own".
//
// Root cause: _backfillBusinessVerticals was wired into sqflite's onOpen
// callback (onOpen -> _ensureExtraTables -> _backfillBusinessVerticals), so it
// ran on EVERY database open — i.e. every app launch. It issued unguarded
// global `UPDATE products SET business_type = ...` statements driven by
// `LIKE '%keyword%'` matching on product names, including '%Syrup%',
// '%Tablet%', '%Ointment%', '%Suit%', '%Dress%', '%Wire%' and '%Switch%'.
//
// The practical effect for a real merchant: a grocery store stocking
// "Rooh Afza Sharbat Syrup" had that row silently re-tagged
// business_type='pharmacy' on the next launch. Every merchant-facing stock
// screen (Products, Inventory, POS Billing, Home Pulse, Expiry Radar) filters
// through getAllProducts(businessType:), so the product — and the stock the
// merchant had just inwarded — vanished from the app. The row was still in
// SQLite; it was simply filtered out of every query. Because it needed an app
// restart to show up, it presented as stock disappearing "after some time".
//
// The fix has two halves, and this file pins both:
//   1. The merchant-data half of the backfill is now claimed ONCE per database
//      via the app_counters flag table, instead of running on every open.
//   2. Even when it does run, it only ever fills in rows that are genuinely
//      UNCLASSIFIED (business_type NULL or ''). It can no longer re-classify a
//      product that already carries a vertical.
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kamaiplus_pos/core/database/local_database.dart';
import 'package:kamaiplus_pos/models/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  tearDown(() async {
    await LocalDatabase.instance.closeDatabase();
  });

  /// Builds a pre-existing v5 database file containing [products], plus a
  /// store_profile locked to [storeVertical] — the shape a real device carries
  /// before it upgrades to the current schema.
  Future<String> seedLegacyDb(
    String userId, {
    required String storeVertical,
    required List<Map<String, Object?>> products,
  }) async {
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
            business_type TEXT,
            stock_quantity REAL NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE categories (
            id TEXT PRIMARY KEY,
            business_id TEXT,
            name TEXT NOT NULL,
            business_type TEXT
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
      'store_name': 'Test Store',
      'business_type': storeVertical,
    });
    for (final row in products) {
      await legacyDb.insert('products', row);
    }
    await legacyDb.close();
    return dbPath;
  }

  test('an already-classified product survives the upgrade + backfill untouched',
      () async {
    final userId = 'backfill_guard_${DateTime.now().microsecondsSinceEpoch}';
    await seedLegacyDb(
      userId,
      storeVertical: 'grocery',
      products: [
        {
          'id': 'prod_rooh_afza',
          'business_id': 'biz_test',
          'name': 'Rooh Afza Sharbat Syrup 750ml',
          'business_type': 'grocery',
          'stock_quantity': 40.0,
        },
        {
          'id': 'prod_hajmola',
          'business_id': 'biz_test',
          'name': 'Hajmola Digestive Tablet Bottle',
          'business_type': 'grocery',
          'stock_quantity': 25.0,
        },
      ],
    );

    await LocalDatabase.instance.switchUser(userId);
    final db = await LocalDatabase.instance.database;

    final rows = await db.query('products', orderBy: 'id');
    expect(rows.length, 2, reason: 'no merchant product may be deleted');
    for (final row in rows) {
      expect(
        row['business_type'],
        'grocery',
        reason:
            '"${row['name']}" matches a pharmacy keyword but was already tagged '
            'grocery — the backfill must not re-classify an existing vertical',
      );
    }
    expect(rows.firstWhere((r) => r['id'] == 'prod_rooh_afza')['stock_quantity'],
        40.0);
    expect(
        rows.firstWhere((r) => r['id'] == 'prod_hajmola')['stock_quantity'], 25.0);
  });

  test('unclassified legacy rows adopt the STORE\'s vertical, not a hardcoded grocery',
      () async {
    final userId = 'backfill_fallback_${DateTime.now().microsecondsSinceEpoch}';
    await seedLegacyDb(
      userId,
      storeVertical: 'restaurant',
      products: [
        {
          'id': 'prod_legacy_blank',
          'business_id': 'biz_test',
          'name': 'House Special Thali',
          'business_type': '',
          'stock_quantity': 10.0,
        },
        {
          'id': 'prod_legacy_null',
          'business_id': 'biz_test',
          'name': 'Chef Special Platter',
          'business_type': null,
          'stock_quantity': 5.0,
        },
      ],
    );

    await LocalDatabase.instance.switchUser(userId);
    final db = await LocalDatabase.instance.database;

    final rows = await db.query('products', orderBy: 'id');
    for (final row in rows) {
      expect(
        row['business_type'],
        'restaurant',
        reason:
            'an unclassified row belongs to the store\'s own locked vertical; '
            'defaulting it to grocery hid it from every non-grocery store',
      );
    }
  });

  test('relaunching the app repeatedly never drifts a product out of its vertical',
      () async {
    final userId = 'backfill_relaunch_${DateTime.now().microsecondsSinceEpoch}';
    await LocalDatabase.instance.switchUser(userId);

    final db = await LocalDatabase.instance.database;
    await db.insert(
      'store_profile',
      {'id': 'default_store', 'business_type': 'grocery'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Exactly what a merchant inwarding stock produces: a real product whose
    // name happens to collide with three different verticals' keyword rules.
    await LocalDatabase.instance.upsertProduct(ProductModel(
      id: 'prod_inwarded',
      businessId: 'biz_test',
      name: 'Dabur Honitus Cough Syrup 100ml',
      sellingPricePaise: 12000,
      mrpPaise: 13500,
      purchasePricePaise: 9000,
      stockQuantity: 36.0,
      unit: 'pcs',
      businessType: 'grocery',
    ));

    // Simulate three app relaunches. Each one reopens the database file and
    // fires the onOpen chain that used to corrupt the row.
    for (var launch = 1; launch <= 3; launch++) {
      await LocalDatabase.instance.reloadDatabase();

      final visible =
          await LocalDatabase.instance.getAllProducts(businessType: 'grocery');
      expect(
        visible.any((p) => p.id == 'prod_inwarded'),
        isTrue,
        reason: 'inwarded stock vanished from the grocery catalog on relaunch #$launch',
      );
      final product = visible.firstWhere((p) => p.id == 'prod_inwarded');
      expect(product.businessType, 'grocery', reason: 'drifted on relaunch #$launch');
      expect(product.stockQuantity, 36.0, reason: 'stock changed on relaunch #$launch');
    }
  });
}
