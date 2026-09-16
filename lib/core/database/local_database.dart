import 'dart:io';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/models.dart';
import '../utils/money_formatter.dart';
import '../utils/gst_helper.dart';
import '../constants/master_catalog_data.dart';
import '../constants/default_products.dart';
import '../state/app_data_bus.dart';


class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();
  static Database? _database;
  static String _activeDbName = 'kamaiplus_local.db';
  static const _uuid = Uuid();

  LocalDatabase._init();

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    await _resolveActiveDbName();
    _database = await _initDB(_activeDbName);
    return _database!;
  }

  /// Automatically resolves and locks onto the active store database on device,
  /// preventing fallback to empty demo db if SharedPreferences was cleared.
  Future<void> _resolveActiveDbName() async {
    if (_activeDbName != 'kamaiplus_local.db') {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      String? cachedUserId = prefs.getString('auth_user_id');
      if (cachedUserId == null || cachedUserId.trim().isEmpty) {
        try {
          cachedUserId = FirebaseAuth.instance.currentUser?.uid;
        } catch (_) {}
      }
      if (cachedUserId != null && cachedUserId.trim().isNotEmpty) {
        final safeId = cachedUserId.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
        _activeDbName = 'kamaiplus_$safeId.db';
        return;
      }

      // Auto-discover existing configured store database on device
      final dbPath = await getDatabasesPath();
      final dir = Directory(dbPath);
      if (await dir.exists()) {
        final files = await dir.list().toList();
        for (final file in files) {
          final name = p.basename(file.path);
          if (name.startsWith('kamaiplus_') && name.endsWith('.db') && name != 'kamaiplus_local.db') {
            _activeDbName = name;
            return;
          }
        }
      }
    } catch (_) {}
  }

  /// Switch the active SQLite database to a user-scoped database file.
  /// Each user/email gets their own isolated local database: `kamaiplus_<safeId>.db`.
  Future<void> switchUser(String? userId) async {
    String targetDb;
    if (userId != null && userId.trim().isNotEmpty) {
      final safeId = userId.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      targetDb = 'kamaiplus_$safeId.db';
    } else {
      await _resolveActiveDbName();
      targetDb = _activeDbName;
    }

    if (_activeDbName == targetDb && _database != null && _database!.isOpen) {
      return;
    }

    if (_database != null) {
      try {
        await _database!.close();
      } catch (_) {}
      _database = null;
    }

    _activeDbName = targetDb;
    _database = await _initDB(_activeDbName);
  }

  /// Closes database connection on sign-out without switching to demo db
  Future<void> closeDatabase() async {
    if (_database != null) {
      try {
        await _database!.close();
      } catch (_) {}
      _database = null;
    }
    // Retain _activeDbName so store data is never lost or switched to demo db
  }

  /// Returns the absolute filesystem path to the currently active SQLite database file
  Future<String> getActiveDatabasePath() async {
    await database;
    final dbPath = await getDatabasesPath();
    return p.join(dbPath, _activeDbName);
  }

  /// Safely reopens database after file restore and notifies all listeners
  Future<void> reloadDatabase() async {
    if (_database != null) {
      try {
        await _database!.close();
      } catch (_) {}
      _database = null;
    }
    await database;
    AppDataBus.instance.bumpAll();
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 7,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateToV2(db);
        }
        if (oldVersion < 3) {
          await _migrateToV3(db);
        }
        if (oldVersion < 4) {
          await _migrateToV4(db);
        }
        if (oldVersion < 5) {
          await _migrateToV5(db);
        }
        if (oldVersion < 6) {
          await _repairMistaggedProductsOnDb(db);
        }
        // v7: one more repair pass, for installs that were ALREADY on v6.
        // Those were repaired once at the v6 upgrade and then silently
        // re-corrupted on every subsequent launch by
        // _backfillBusinessVerticals, which re-tagged a merchant's own
        // products by name keyword on every single database open — so a
        // grocery store's "Rooh Afza Syrup" became business_type 'pharmacy'
        // and disappeared from Products/Inventory/POS, which all filter on
        // that column. That re-tagging is now one-time and only ever fills
        // in UNCLASSIFIED rows; this pass heals the damage it already did.
        if (oldVersion < 7) {
          await _repairMistaggedProductsOnDb(db);
        }
      },
      onOpen: (db) async {
        await _ensureExtraTables(db);
        await _seedMasterCatalogIfEmpty(db);
      },
    );
  }

  Future<void> _migrateToV2(Database db) async {
    try {
      await db.execute('ALTER TABLE store_profile ADD COLUMN business_type TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE products ADD COLUMN batch_number TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE products ADD COLUMN expiry_date TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE products ADD COLUMN size TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE products ADD COLUMN color TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE products ADD COLUMN imei_serial TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE products ADD COLUMN hsn_code TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE products ADD COLUMN is_loose_item INTEGER DEFAULT 0');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE products ADD COLUMN is_favorite INTEGER DEFAULT 0');
    } catch (_) {}
    try {
      // Single-quoted — a double-quoted DEFAULT is the same misfeature fixed
      // elsewhere in this file for 'both' (see DEVELOPMENT_LOG.md): SQLite
      // reads double quotes as an identifier reference on a strict build.
      await db.execute("ALTER TABLE products ADD COLUMN business_type TEXT DEFAULT 'grocery'");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE categories ADD COLUMN business_type TEXT DEFAULT 'grocery'");
    } catch (_) {}
  }

  Future<void> _migrateToV3(Database db) async {
    try {
      // Lets a pharmacy strip know how many tablets it actually contains
      // (10 / 15 / 20 / 30 all exist in the real world) so billing can sell
      // a handful of tablets instead of only whole or half strips.
      // Null means "unknown" — falls back to the existing whole/half-strip
      // chips in quantity_config.dart, never a crash or a wrong assumption.
      await db.execute('ALTER TABLE products ADD COLUMN sub_units_per_pack INTEGER');
    } catch (_) {}
  }

  Future<void> _migrateToV4(Database db) async {
    try {
      // Clothing fit/size-chart notes (Phase 4 of the KamaiPlus Playbook) —
      // e.g. "Runs small, order one size up" or "True to size". A free-text
      // field rather than a structured size chart: avoids a new
      // image-picker/table dependency this phase doesn't need, and covers
      // the actual complaint (customers guessing sizes wrong) either way.
      await db.execute('ALTER TABLE products ADD COLUMN fit_notes TEXT');
    } catch (_) {}
  }

  Future<void> _migrateToV5(Database db) async {
    // Real multi-batch FEFO (First-Expiry-First-Out) for Pharmacy — see
    // ProductBatchModel's doc comment for why a single ProductModel.expiryDate
    // field can't represent "this medicine has two deliveries on the shelf
    // with two different expiry dates", which the single-batch nudge added
    // earlier (feature #61) could not.
    await _createProductBatchesTable(db);

    // Backfill: every existing product with real stock becomes its own
    // single batch, carrying forward whatever batch_number/expiry_date it
    // already had. This keeps the aggregate (existing stock_quantity)
    // exactly unchanged — a batch is only ADDED here, nothing is
    // recomputed or overwritten on the products table itself.
    try {
      final existing = await db.query('products', where: 'stock_quantity > 0');
      final now = DateTime.now().toIso8601String();
      for (final row in existing) {
        final qty = (row['stock_quantity'] as num?)?.toDouble() ?? 0.0;
        if (qty <= 0) continue;
        await db.insert('product_batches', {
          'id': 'batch_legacy_${row['id']}',
          'product_id': row['id'],
          'business_id': row['business_id'],
          'batch_number': row['batch_number'],
          'quantity': qty,
          'expiry_date': row['expiry_date'],
          'purchase_price_paise': row['purchase_price_paise'] ?? 0,
          'created_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    } catch (_) {}
  }

  /// One-time repair for legacy data damage from a since-fixed bug: an
  /// earlier version of `quick_stock_update_modal.dart` rebuilt a product's
  /// row from a fresh `ProductModel(...)` instead of `copyWith(...)` on
  /// every stock/price quick-update, silently resetting `businessType` to
  /// its constructor default ('grocery') no matter what vertical the
  /// product actually belonged to. That code path is long fixed (see the
  /// `copyWith` comment in `_saveInward`/`_saveAdjustment`), but devices
  /// that hit the bug before the fix shipped are still carrying rows like
  /// "Dolo 650 Paracetamol" tagged `business_type='grocery'` — invisible to
  /// every pharmacy-scoped query, which reads as "my product/quantity
  /// update made the item disappear" even though the code doing the update
  /// today is correct.
  ///
  /// Every starter-catalog product name is unique to exactly one vertical
  /// (see `kDefaultProductsByVertical`), so a row whose name matches a seed
  /// name but whose `business_type` doesn't match that seed's vertical is
  /// unambiguously mistagged. If a correctly-tagged sibling with the same
  /// name already exists (the common case — the corruption created a
  /// second, wrong-tagged copy rather than corrupting the only copy), the
  /// mistagged row is a pure duplicate and is removed; otherwise it's the
  /// only copy, so it's simply re-tagged rather than deleted, so no stock
  /// data is ever lost.
  ///
  /// Runs automatically on schema upgrade (see `_migrateToV6` below), but
  /// upgrade only fires for a database that already existed at an older
  /// version — a brand-new install's database is created directly at the
  /// latest version via `onCreate`, so it never goes through `onUpgrade` at
  /// all. Such a device can still end up with mistagged products from a
  /// cloud restore (see the `business_type` fix in
  /// `firestore_sync_service.dart`'s `initialCloudRestore`/live product
  /// listener, needed because cloud docs pushed before that fix never
  /// carried the field at all) — `initialCloudRestore` calls this same
  /// public method directly right after pulling products, so a fresh
  /// device gets the identical repair without needing a schema bump.
  Future<void> repairMistaggedProducts() async {
    final db = await database;
    await _repairMistaggedProductsOnDb(db);
  }

  Future<void> _repairMistaggedProductsOnDb(Database db) async {
    try {
      final correctVertical = <String, String>{};
      for (final entry in kDefaultProductsByVertical.entries) {
        for (final seed in entry.value) {
          correctVertical[seed.name] = entry.key;
        }
      }
      if (correctVertical.isEmpty) return;

      final rows = await db.query('products');
      for (final row in rows) {
        final name = row['name'] as String?;
        final currentType = row['business_type'] as String?;
        final id = row['id'] as String?;
        if (name == null || id == null) continue;
        final trueType = correctVertical[name];
        if (trueType == null || trueType == currentType) continue;

        final siblingCount = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM products WHERE name = ? AND business_type = ? AND id != ?',
              [name, trueType, id],
            )) ??
            0;
        if (siblingCount > 0) {
          await db.delete('products', where: 'id = ?', whereArgs: [id]);
        } else {
          await db.update(
            'products',
            {'business_type': trueType},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    } catch (_) {}

    // Second, broader pass: a store's business type is now permanently
    // locked at signup (store_profile_screen.dart no longer offers changing
    // it), so a store can only ever have ONE true vertical for its entire
    // lifetime. That makes the repair above generalize cleanly beyond just
    // starter-catalog names: ANY product tagged with a business_type other
    // than the store's own permanent one (and not 'both', and not the
    // legacy-unclassified blank value getAllProducts already falls back to)
    // is provably orphaned — there is no longer a legitimate way for a
    // second vertical's products to exist in this store. This is what
    // actually catches a merchant's own manually-added products (not just
    // seed-catalog items) that got mistagged by the same historical bug.
    try {
      await _ensureStoreProfileTable(db);
      final profileRows = await db.query(
        'store_profile',
        where: 'id = ?',
        whereArgs: ['default_store'],
        limit: 1,
      );
      if (profileRows.isEmpty) return;
      final trueType = (profileRows.first['business_type'] as String?)?.trim().toLowerCase();
      if (trueType == null || trueType.isEmpty) return;

      final rows2 = await db.query('products');
      for (final row in rows2) {
        final id = row['id'] as String?;
        final name = row['name'] as String?;
        final currentType = (row['business_type'] as String?)?.trim().toLowerCase();
        if (id == null || name == null) continue;
        if (currentType == null || currentType.isEmpty || currentType == trueType || currentType == 'both') {
          continue;
        }

        final siblingCount = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM products WHERE name = ? AND business_type = ? AND id != ?',
              [name, trueType, id],
            )) ??
            0;
        if (siblingCount > 0) {
          await db.delete('products', where: 'id = ?', whereArgs: [id]);
        } else {
          await db.update(
            'products',
            {'business_type': trueType},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _createProductBatchesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_batches (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        business_id TEXT NOT NULL,
        batch_number TEXT,
        quantity REAL NOT NULL,
        expiry_date TEXT,
        purchase_price_paise INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _ensureExtraTables(Database db) async {
    await _migrateToV2(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS store_profile (
        id TEXT PRIMARY KEY,
        store_name TEXT,
        tagline TEXT,
        owner_name TEXT,
        phone TEXT,
        email TEXT,
        upi_vpa TEXT,
        category TEXT,
        business_type TEXT,
        address TEXT,
        pincode TEXT,
        gstin TEXT,
        fssai TEXT,
        logo_url TEXT,
        upi_accounts_json TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expenses (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        title TEXT NOT NULL,
        amount_paise INTEGER NOT NULL,
        category TEXT NOT NULL,
        created_at TEXT NOT NULL,
        note TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_movements (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        movement_type TEXT NOT NULL,
        quantity REAL NOT NULL,
        previous_stock REAL NOT NULL,
        new_stock REAL NOT NULL,
        reference_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_orders (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        invoice_no TEXT,
        supplier_name TEXT NOT NULL,
        supplier_phone TEXT,
        category TEXT,
        amount_paise INTEGER NOT NULL DEFAULT 0,
        due_paise INTEGER NOT NULL DEFAULT 0,
        payment_status TEXT,
        status TEXT NOT NULL DEFAULT 'In-Transit',
        items_count INTEGER NOT NULL DEFAULT 0,
        items_json TEXT,
        order_date TEXT NOT NULL,
        expected_date TEXT,
        stock_applied_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        category TEXT NOT NULL,
        current_balance_paise INTEGER NOT NULL,
        gstin TEXT,
        sync_status TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cash_register_shifts (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        opening_cash_paise INTEGER NOT NULL,
        cash_sales_paise INTEGER NOT NULL,
        cash_expenses_paise INTEGER NOT NULL,
        expected_closing_paise INTEGER NOT NULL,
        actual_closing_paise INTEGER NOT NULL,
        difference_paise INTEGER NOT NULL,
        status TEXT NOT NULL,
        opened_at TEXT NOT NULL,
        closed_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_counters (
        key TEXT PRIMARY KEY,
        last_val INTEGER NOT NULL DEFAULT 0
      )
    ''');
    try {
      await db.execute('ALTER TABLE customers ADD COLUMN address TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE customers ADD COLUMN gstin TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE customers ADD COLUMN state_code TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE customers ADD COLUMN is_vip INTEGER DEFAULT 0');
    } catch (_) {}
    try {
      // Customer birthday as 'MM-DD' — day and month only, deliberately no
      // year. A shopkeeper knows "Ramesh ka birthday 14 August hai"; they do
      // not know, and have no business storing, the year. Added because the
      // Birthday campaign in growth_campaigns_screen.dart had no real field
      // to read and was selecting its audience with `name.length % 3 == 0`.
      await db.execute('ALTER TABLE customers ADD COLUMN birthday TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE sales ADD COLUMN customer_gstin TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE sales ADD COLUMN place_of_supply TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE sales ADD COLUMN split_cash_paise INTEGER DEFAULT 0');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE sales ADD COLUMN split_upi_paise INTEGER DEFAULT 0');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE sales ADD COLUMN split_credit_paise INTEGER DEFAULT 0');
    } catch (_) {}
    await db.execute('''
      CREATE TABLE IF NOT EXISTS doctors (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        name TEXT NOT NULL,
        qualification TEXT,
        registration_number TEXT,
        phone TEXT
      )
    ''');
    try {
      await db.execute('ALTER TABLE sales ADD COLUMN doctor_name TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE sales ADD COLUMN table_number TEXT');
    } catch (_) {}

    // Master Catalog Table for Instant Offline SKUs (<2ms lookups)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS master_catalog (
        barcode TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        mrp_paise INTEGER NOT NULL,
        selling_price_paise INTEGER NOT NULL,
        unit TEXT DEFAULT 'pcs',
        tax_rate REAL DEFAULT 0.0,
        business_type TEXT DEFAULT 'grocery',
        brand TEXT,
        hsn_code TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_master_barcode ON master_catalog(barcode)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_master_name ON master_catalog(name)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_master_category ON master_catalog(category)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_master_biz_type ON master_catalog(business_type)');

    // Security Audit Log Table for High-Impact Actions (Refunds, Stock Overrides, Deletions)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_logs (
        id TEXT PRIMARY KEY,
        business_id TEXT,
        action TEXT NOT NULL,
        details TEXT NOT NULL,
        amount_paise INTEGER DEFAULT 0,
        user_pin TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_logs(created_at)');

    // Sale Returns (Partial & Full Returns / Credit Notes)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_returns (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        return_number TEXT NOT NULL,
        items_returned_json TEXT NOT NULL,
        total_refund_paise INTEGER NOT NULL,
        refund_method TEXT NOT NULL,
        reason TEXT,
        created_at TEXT NOT NULL,
        sync_status TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_returns_sale_id ON sale_returns(sale_id)');

    // Product Variant support (Parent-Child multi-SKU matrix)
    try {
      await db.execute('ALTER TABLE products ADD COLUMN parent_id TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE products ADD COLUMN has_variants INTEGER DEFAULT 0');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE products ADD COLUMN variant_label TEXT');
    } catch (_) {}
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_parent_id ON products(parent_id)');

    await _seedMasterCatalogIfEmpty(db);
    await _backfillBusinessVerticals(db);
  }

  /// Automatic vertical isolation: classifies unassigned categories & products
  /// into their correct business verticals so pharmacy/clothing/hardware items NEVER mix into grocery.
  /// True once [flagKey]'s one-shot migration has already completed on this
  /// database.
  ///
  /// Backed by the existing `app_counters` key/value table (the same one
  /// getNextInvoiceSequence uses) rather than SharedPreferences, deliberately:
  /// the app keeps a separate database file per signed-in user
  /// (see _resolveActiveDbName/switchUser), so a device-global preference would
  /// let one user's completed migration suppress another user's pending one.
  /// A flag stored inside the database file follows that file.
  ///
  /// Reads fail OPEN (returns false, so the migration runs). Paired with
  /// _setOneTimeFlag being written only after the work actually succeeded, that
  /// means a transient error costs one harmless extra pass rather than
  /// permanently skipping a migration the database still needs.
  Future<bool> _isOneTimeFlagSet(Database db, String flagKey) async {
    try {
      final rows = await db.query(
        'app_counters',
        where: 'key = ?',
        whereArgs: [flagKey],
        limit: 1,
      );
      return rows.isNotEmpty &&
          ((rows.first['last_val'] as num?)?.toInt() ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }

  /// Marks [flagKey]'s one-shot migration as done. Call this only after the
  /// migration has actually completed — never up front, or a mid-way failure
  /// would leave the database half-migrated with no second attempt.
  Future<void> _setOneTimeFlag(Database db, String flagKey) async {
    try {
      await db.insert(
        'app_counters',
        {'key': flagKey, 'last_val': 1},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  /// This store's permanently-locked business vertical, or null when no profile
  /// has been saved yet (a brand-new install, before signup completes).
  ///
  /// Reads the table directly instead of going through getStoreProfile() so it
  /// is safe to call from inside onOpen, before `instance.database` has
  /// finished resolving.
  Future<String?> _storeVerticalOrNull(Database db) async {
    try {
      await _ensureStoreProfileTable(db);
      final rows = await db.query(
        'store_profile',
        where: 'id = ?',
        whereArgs: ['default_store'],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final type = (rows.first['business_type'] as String?)?.trim().toLowerCase();
      return (type == null || type.isEmpty) ? null : type;
    } catch (_) {
      return null;
    }
  }

  /// Tags health & hygiene crossover items in the seeded reference catalog as
  /// sellable in BOTH grocery and pharmacy. Touches `master_catalog` only —
  /// never a merchant's own `products` rows — so it is idempotent and stays
  /// outside the one-time backfill flag, ensuring it still applies after
  /// _seedMasterCatalogIfEmpty re-seeds an emptied catalog.
  Future<void> _promoteCrossoverMasterCatalogItems(Database db) async {
    try {
      await db.execute('''
        UPDATE master_catalog SET business_type = 'both'
        WHERE (
          name LIKE '%Dettol%' OR name LIKE '%Savlon%' OR name LIKE '%Lifebuoy%'
          OR name LIKE '%Vicks%' OR name LIKE '%Moov%' OR name LIKE '%Volini%'
          OR name LIKE '%Band-Aid%' OR name LIKE '%Boroline%' OR name LIKE '%Glucose%'
          OR name LIKE '%Horlicks%' OR name LIKE '%Bournvita%' OR name LIKE '%Complan%'
          OR name LIKE '%Toothpaste%' OR name LIKE '%Colgate%' OR name LIKE '%Close Up%'
          OR name LIKE '%Sensodyne%' OR name LIKE '%Eno%' OR name LIKE '%Pudin Hara%'
          OR name LIKE '%Strepsils%' OR name LIKE '%Iodex%' OR name LIKE '%Sanitizer%'
          OR name LIKE '%Diaper%' OR name LIKE '%Pampers%' OR name LIKE '%Johnson%Baby%'
        );
      ''');
    } catch (_) {}
  }

  Future<void> _backfillBusinessVerticals(Database db) async {
    // Crossover reference-catalog tagging is NOT part of the one-time backfill:
    // it only ever touches master_catalog (seed reference data, re-created by
    // _seedMasterCatalogIfEmpty), never a merchant's own products, so it stays
    // idempotent and safe to re-apply after a re-seed.
    await _promoteCrossoverMasterCatalogItems(db);

    // Everything below rewrites the merchant's OWN product/category rows, so it
    // runs EXACTLY ONCE per database. It used to run on every single database
    // open (onOpen -> _ensureExtraTables -> here), re-classifying already-tagged
    // products by name keyword every launch. That is what made freshly inwarded
    // stock vanish: a grocery store's "Rooh Afza Syrup" matched LIKE '%Syrup%',
    // got re-tagged 'pharmacy', and every screen that filters on business_type
    // (Products, Inventory, POS, Home Pulse, Expiry Radar) stopped showing it.
    if (await _isOneTimeFlagSet(db, 'vertical_backfill_v1')) return;

    // Whatever is still unclassified at the end belongs to THIS store's own
    // permanently-locked vertical — never a hardcoded 'grocery', which used to
    // strand every non-grocery store's legacy rows in a vertical they cannot see.
    final fallbackType = await _storeVerticalOrNull(db) ?? 'grocery';

    // Each phase is isolated so one failing statement (an older install missing
    // a table an ALTER-only migration never created, say) cannot abort the
    // phases after it — in particular the fallback stamp below, which is what
    // actually decides whether legacy rows are visible to this store at all.
    var completed = true;

    try {
      // 1. Classify categories
      await db.execute('''
        UPDATE categories SET business_type = 'pharmacy' 
        WHERE (business_type IS NULL OR business_type = '')
           AND (id LIKE '%pharma%' OR id LIKE '%med%' 
           OR name LIKE '%Pharma%' OR name LIKE '%Medicine%' 
           OR name LIKE '%Tablets%' OR name LIKE '%Syrup%' 
           OR name LIKE '%First Aid%' OR name LIKE '%Ayurvedic%' 
           OR name LIKE '%Ointment%' OR name LIKE '%Generic%');
      ''');
      await db.execute('''
        UPDATE categories SET business_type = 'clothing' 
        WHERE (business_type IS NULL OR business_type = '')
           AND (id LIKE '%cloth%' OR name LIKE '%Men%' OR name LIKE '%Women%' 
           OR name LIKE '%Kids%' OR name LIKE '%Wear%' OR name LIKE '%Apparel%'
           OR name LIKE '%Saree%' OR name LIKE '%Shirt%' OR name LIKE '%Jeans%');
      ''');
      await db.execute('''
        UPDATE categories SET business_type = 'hardware' 
        WHERE (business_type IS NULL OR business_type = '')
           AND (id LIKE '%hard%' OR name LIKE '%Paint%' OR name LIKE '%Tool%' 
           OR name LIKE '%Plumbing%' OR name LIKE '%Electrical%' OR name LIKE '%Pipe%'
           OR name LIKE '%Sanitary%');
      ''');
      await db.execute('''
        UPDATE categories SET business_type = 'restaurant' 
        WHERE (business_type IS NULL OR business_type = '')
           AND (id LIKE '%rest%' OR name LIKE '%Starter%' OR name LIKE '%Beverage%' 
           OR name LIKE '%Main Course%' OR name LIKE '%Curry%' OR name LIKE '%Roti%'
           OR name LIKE '%Dessert%');
      ''');
      // Unclassified categories are stamped with the store's own vertical in
      // step 4 below, alongside unclassified products — same rule, one place.

      // 2. Sync products with their category's business_type
      await db.execute('''
        UPDATE products SET business_type = (
          SELECT categories.business_type FROM categories WHERE categories.id = products.category_id
        )
        WHERE (business_type IS NULL OR business_type = '')
          AND category_id IS NOT NULL AND (
          SELECT categories.business_type FROM categories WHERE categories.id = products.category_id
        ) IS NOT NULL;
      ''');

      // 3. Keyword-based strict classification for products (prevents cross-vertical mixing)
      await db.execute('''
        UPDATE products SET business_type = 'pharmacy'
        WHERE (business_type IS NULL OR business_type = '')
           AND ((
          name LIKE '%Dolo%' OR name LIKE '%Paracetamol%' OR name LIKE '%Cetirizine%' 
          OR name LIKE '%Azithromycin%' OR name LIKE '%Pantoprazole%' OR name LIKE '%Syrup%' 
          OR name LIKE '%Tablet%' OR name LIKE '%Capsule%' OR name LIKE '%Ointment%' 
          OR name LIKE '%Vicks%' OR name LIKE '%Moov%' OR name LIKE '%Volini%' 
          OR name LIKE '%Band-Aid%' OR name LIKE '%Crocin%' OR name LIKE '%Combiflam%' 
          OR name LIKE '%Digene%' OR name LIKE '%Betadine%' OR name LIKE '%Strepsils%' 
          OR name LIKE '%Disprin%' OR name LIKE '%Eno%' OR name LIKE '%Benadryl%'
          OR name LIKE '%Ascoril%' OR name LIKE '%Inhaler%'
        ));
      ''');

      await db.execute('''
        UPDATE products SET business_type = 'clothing'
        WHERE (business_type IS NULL OR business_type = '')
           AND ((
          name LIKE '%Shirt%' OR name LIKE '%T-Shirt%' OR name LIKE '%Jeans%' 
          OR name LIKE '%Saree%' OR name LIKE '%Kurti%' OR name LIKE '%Trouser%'
          OR name LIKE '%Suit%' OR name LIKE '%Dress%' OR name LIKE '%Legging%'
          OR name LIKE '%Shoes%' OR name LIKE '%Sandals%' OR name LIKE '%Innerwear%'
          OR name LIKE '%Dupatta%'
        ));
      ''');

      await db.execute('''
        UPDATE products SET business_type = 'hardware'
        WHERE (business_type IS NULL OR business_type = '')
           AND ((
          name LIKE '%PVC Pipe%' OR name LIKE '%Hammer%' OR name LIKE '%Apex Emulsion%' 
          OR name LIKE '%Wire%' OR name LIKE '%Switch%' OR name LIKE '%MCB%'
          OR name LIKE '%Cement%' OR name LIKE '%Screwdriver%' OR name LIKE '%Nut Bolt%'
          OR name LIKE '%Washbasin%' OR name LIKE '%LED Bulb%' OR name LIKE '%LED Batten%'
        ));
      ''');

      await db.execute('''
        UPDATE products SET business_type = 'restaurant'
        WHERE (business_type IS NULL OR business_type = '')
           AND ((
          name LIKE '%Masala Chai%' OR name LIKE '%Cold Coffee%' OR name LIKE '%Samosa%' 
          OR name LIKE '%Spring Roll%' OR name LIKE '%Paneer Butter%' OR name LIKE '%Dal Makhani%'
          OR name LIKE '%Butter Naan%' OR name LIKE '%Jeera Rice%' OR name LIKE '%Burger%'
          OR name LIKE '%Gulab Jamun%' OR name LIKE '%Kulfi%'
        ));
      ''');

    } catch (_) {
      completed = false;
    }

    // 4. Anything still unclassified becomes this store's own vertical. Kept in
    // its own try so it still runs even if a classification statement above
    // failed — an unclassified row is invisible to a store whose vertical has
    // any tagged rows at all (see getAllProducts' fallback), so this is the
    // step that must not be skipped.
    try {
      await db.execute(
        "UPDATE products SET business_type = ? WHERE business_type IS NULL OR business_type = ''",
        [fallbackType],
      );
      await db.execute(
        "UPDATE categories SET business_type = ? WHERE business_type IS NULL OR business_type = ''",
        [fallbackType],
      );
    } catch (_) {
      completed = false;
    }

    // Only now is the migration recorded as done. If any phase failed, the flag
    // stays unset and the next launch retries — safe, because every statement
    // above only ever fills in rows that are still unclassified.
    if (completed) {
      await _setOneTimeFlag(db, 'vertical_backfill_v1');
    }
  }


  /// Seeds default starter categories & products for a specific business vertical if not already present.
  Future<void> seedVerticalStarterData(String businessType) async {
    final cleanType = businessType.trim().toLowerCase();
    final seeds = kDefaultProductsByVertical[cleanType];
    if (seeds == null || seeds.isEmpty) return;

    final db = await database;
    final existingCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM products WHERE business_type = ?', [cleanType]),
    ) ?? 0;

    if (existingCount > 0) return; // Already seeded for this vertical

    final defaultBizId = 'biz_${cleanType}_store';
    final Map<String, String> categoryMap = {};

    for (final seed in seeds) {
      if (!categoryMap.containsKey(seed.categoryName)) {
        final catRows = await db.query(
          'categories',
          where: 'name = ? AND business_type = ?',
          whereArgs: [seed.categoryName, cleanType],
          limit: 1,
        );

        String catId;
        if (catRows.isNotEmpty) {
          catId = catRows.first['id'] as String;
        } else {
          catId = 'cat_${cleanType}_${_uuid.v4().substring(0, 8)}';
          await db.insert('categories', {
            'id': catId,
            'business_id': defaultBizId,
            'name': seed.categoryName,
            'business_type': cleanType,
          });
        }
        categoryMap[seed.categoryName] = catId;
      }

      final prodId = 'prod_${cleanType}_${_uuid.v4().substring(0, 8)}';
      await db.insert('products', {
        'id': prodId,
        'business_id': defaultBizId,
        'name': seed.name,
        'category_id': categoryMap[seed.categoryName],
        'selling_price_paise': seed.sellingPricePaise,
        'mrp_paise': seed.mrpPaise,
        'purchase_price_paise': seed.purchasePricePaise,
        'stock_quantity': seed.stockQuantity,
        'tax_rate': seed.taxRate,
        'is_tax_inclusive': 1,
        'unit': seed.unit,
        'sync_status': 'synced',
        'business_type': cleanType,
      });
    }
  }

  Future<void> _seedMasterCatalogIfEmpty(Database db) async {
    try {
      final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM master_catalog');
      final count = Sqflite.firstIntValue(countResult) ?? 0;
      if (count == 0) {
        final batch = db.batch();
        for (final item in kMasterCatalogSeed) {
          batch.insert(
            'master_catalog',
            item.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await batch.commit(noResult: true);
      }
    } catch (_) {}
  }


  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        name TEXT NOT NULL,
        business_type TEXT DEFAULT 'grocery'
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        name TEXT NOT NULL,
        barcode TEXT,
        category_id TEXT,
        selling_price_paise INTEGER NOT NULL,
        mrp_paise INTEGER NOT NULL,
        purchase_price_paise INTEGER NOT NULL,
        stock_quantity REAL NOT NULL,
        tax_rate REAL NOT NULL,
        is_tax_inclusive INTEGER NOT NULL,
        unit TEXT NOT NULL,
        batch_number TEXT,
        expiry_date TEXT,
        size TEXT,
        color TEXT,
        imei_serial TEXT,
        hsn_code TEXT,
        is_loose_item INTEGER DEFAULT 0,
        is_favorite INTEGER DEFAULT 0,
        sync_status TEXT NOT NULL,
        business_type TEXT DEFAULT 'grocery',
        sub_units_per_pack INTEGER,
        fit_notes TEXT,
        parent_id TEXT,
        has_variants INTEGER DEFAULT 0,
        variant_label TEXT
      )
    ''');

    await _createProductBatchesTable(db);


    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        address TEXT,
        current_balance_paise INTEGER NOT NULL,
        credit_limit_paise INTEGER NOT NULL,
        is_vip INTEGER DEFAULT 0,
        sync_status TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE doctors (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        name TEXT NOT NULL,
        qualification TEXT,
        registration_number TEXT,
        phone TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        invoice_number TEXT NOT NULL,
        customer_id TEXT,
        customer_name TEXT,
        customer_phone TEXT,
        doctor_name TEXT,
        table_number TEXT,
        subtotal_paise INTEGER NOT NULL,
        tax_amount_paise INTEGER NOT NULL,
        discount_paise INTEGER NOT NULL,
        total_amount_paise INTEGER NOT NULL,
        payment_method TEXT NOT NULL,
        split_cash_paise INTEGER DEFAULT 0,
        split_upi_paise INTEGER DEFAULT 0,
        split_credit_paise INTEGER DEFAULT 0,
        status TEXT NOT NULL,
        items_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        sync_status TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_returns (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        return_number TEXT NOT NULL,
        items_returned_json TEXT NOT NULL,
        total_refund_paise INTEGER NOT NULL,
        refund_method TEXT NOT NULL,
        reason TEXT,
        created_at TEXT NOT NULL,
        sync_status TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_returns_sale_id ON sale_returns(sale_id)');

    await db.execute('''
      CREATE TABLE ledger_transactions (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        type TEXT NOT NULL,
        amount_paise INTEGER NOT NULL,
        balance_after_paise INTEGER NOT NULL,
        description TEXT NOT NULL,
        reference_id TEXT,
        created_at TEXT NOT NULL,
        sync_status TEXT NOT NULL
      )
    ''');

    // Always ensure Master Catalog is pre-loaded with top Indian retail SKUs
    await _seedMasterCatalogIfEmpty(db);

    // Pre-populate starter retail items & customers ONLY for default demo db
    if (_activeDbName == 'kamaiplus_local.db') {
      await _seedStarterData(db);
    }
  }

  Future<void> _seedStarterData(Database db) async {
    const defaultBizId = 'biz_starter_pos';

    // Categories
    final categories = [
      {'id': 'cat_grocery', 'business_id': defaultBizId, 'name': 'Grocery & Staples', 'business_type': 'grocery'},
      {'id': 'cat_dairy', 'business_id': defaultBizId, 'name': 'Dairy & Bakery', 'business_type': 'grocery'},
      {'id': 'cat_snacks', 'business_id': defaultBizId, 'name': 'Snacks & Beverages', 'business_type': 'grocery'},
      {'id': 'cat_personal', 'business_id': defaultBizId, 'name': 'Personal Care', 'business_type': 'grocery'},
    ];
    for (var cat in categories) {
      await db.insert('categories', cat);
    }

    // Starter Products (in integer paise: 1 INR = 100 paise)
    final products = [
      {
        'id': 'prod_1',
        'business_id': defaultBizId,
        'name': 'Aashirvaad Shudh Chakki Atta (5kg)',
        'barcode': '8901030383701',
        'category_id': 'cat_grocery',
        'selling_price_paise': 24500, // ₹245.00
        'mrp_paise': 26000,           // ₹260.00
        'purchase_price_paise': 22000,
        'stock_quantity': 40.0,
        'tax_rate': 0.0,
        'is_tax_inclusive': 1,
        'unit': 'bag',
        'sync_status': 'synced',
        'business_type': 'grocery',
      },
      {
        'id': 'prod_2',
        'business_id': defaultBizId,
        'name': 'Amul Butter Pasteurised (500g)',
        'barcode': '8901262010054',
        'category_id': 'cat_dairy',
        'selling_price_paise': 27500, // ₹275.00
        'mrp_paise': 28500,
        'purchase_price_paise': 25000,
        'stock_quantity': 25.0,
        'tax_rate': 12.0,
        'is_tax_inclusive': 1,
        'unit': 'pcs',
        'sync_status': 'synced',
        'business_type': 'grocery',
      },
      {
        'id': 'prod_3',
        'business_id': defaultBizId,
        'name': 'Tata Salt Vacuum Evaporated (1kg)',
        'barcode': '8904043901007',
        'category_id': 'cat_grocery',
        'selling_price_paise': 2800, // ₹28.00
        'mrp_paise': 3000,
        'purchase_price_paise': 2400,
        'stock_quantity': 100.0,
        'tax_rate': 0.0,
        'is_tax_inclusive': 1,
        'unit': 'pkt',
        'sync_status': 'synced',
        'business_type': 'grocery',
      },
      {
        'id': 'prod_4',
        'business_id': defaultBizId,
        'name': 'Fortune Sunlite Sunflower Oil (1L)',
        'barcode': '8906007280014',
        'category_id': 'cat_grocery',
        'selling_price_paise': 15500, // ₹155.00
        'mrp_paise': 17000,
        'purchase_price_paise': 14000,
        'stock_quantity': 50.0,
        'tax_rate': 5.0,
        'is_tax_inclusive': 1,
        'unit': 'pouch',
        'sync_status': 'synced',
        'business_type': 'grocery',
      },
      {
        'id': 'prod_5',
        'business_id': defaultBizId,
        'name': 'Maggi 2-Minute Masala Noodles (70g)',
        'barcode': '8901058852234',
        'category_id': 'cat_snacks',
        'selling_price_paise': 1400, // ₹14.00
        'mrp_paise': 1400,
        'purchase_price_paise': 1150,
        'stock_quantity': 120.0,
        'tax_rate': 12.0,
        'is_tax_inclusive': 1,
        'unit': 'pcs',
        'sync_status': 'synced',
        'business_type': 'grocery',
      },
      {
        'id': 'prod_6',
        'business_id': defaultBizId,
        'name': 'Dettol Original Bathing Soap (125g)',
        'barcode': '8901396317524',
        'category_id': 'cat_personal',
        'selling_price_paise': 6500, // ₹65.00
        'mrp_paise': 6800,
        'purchase_price_paise': 5400,
        'stock_quantity': 60.0,
        'tax_rate': 18.0,
        'is_tax_inclusive': 1,
        'unit': 'pcs',
        'sync_status': 'synced',
        'business_type': 'grocery',
      },
    ];
    for (var prod in products) {
      await db.insert('products', prod);
    }

    // Starter Regular Customers
    final customers = [
      {
        'id': 'cust_1',
        'business_id': defaultBizId,
        'name': 'Ramesh Kumar',
        'phone': '9820012345',
        'current_balance_paise': 45000, // ₹450.00 Udhar
        'credit_limit_paise': 500000,   // ₹5,000.00 limit
        'sync_status': 'synced',
      },
      {
        'id': 'cust_2',
        'business_id': defaultBizId,
        'name': 'Anita Sharma',
        'phone': '9819098765',
        'current_balance_paise': 120000, // ₹1,200.00 Udhar
        'credit_limit_paise': 1000000,
        'sync_status': 'synced',
      },
      {
        'id': 'cust_3',
        'business_id': defaultBizId,
        'name': 'Suresh Patel',
        'phone': '9892055555',
        'current_balance_paise': 0,
        'credit_limit_paise': 300000,
        'sync_status': 'synced',
      },
    ];
    for (var cust in customers) {
      await db.insert('customers', cust);
    }
  }

  // --- QUERY APIS ---

  Future<List<ProductModel>> getAllProducts({String? businessType}) async {
    final db = await instance.database;
    if (businessType != null && businessType.isNotEmpty) {
      final result = await db.query(
        'products',
        where: "business_type = ? OR business_type = 'both'",
        whereArgs: [businessType],
        orderBy: 'is_favorite DESC, name ASC',
      );
      if (result.isNotEmpty) {
        return result.map((json) => ProductModel.fromMap(json)).toList();
      }
      // Nothing tagged for this vertical. Fall back ONLY to genuinely
      // unclassified rows (pre-dating the vertical feature) — never to
      // another vertical's tagged products.
      final unclassified = await db.query(
        'products',
        where: "business_type IS NULL OR business_type = ''",
        orderBy: 'is_favorite DESC, name ASC',
      );
      return unclassified.map((json) => ProductModel.fromMap(json)).toList();
    }
    final allResult = await db.query('products', orderBy: 'is_favorite DESC, name ASC');
    return allResult.map((json) => ProductModel.fromMap(json)).toList();
  }

  Future<List<CategoryModel>> getAllCategories({String? businessType}) async {
    final db = await instance.database;
    if (businessType != null && businessType.isNotEmpty) {
      final result = await db.query(
        'categories',
        where: "business_type = ? OR business_type = 'both'",
        whereArgs: [businessType],
        orderBy: 'name ASC',
      );
      if (result.isNotEmpty) {
        return result.map((json) => CategoryModel.fromMap(json)).toList();
      }
      // Same fix as getAllProducts: never fall back to another vertical's categories.
      final unclassified = await db.query(
        'categories',
        where: "business_type IS NULL OR business_type = ''",
        orderBy: 'name ASC',
      );
      if (unclassified.isNotEmpty) {
        return unclassified.map((json) => CategoryModel.fromMap(json)).toList();
      }
      // A vertical was explicitly requested and genuinely has nothing — an empty
      // category list is correct here, not every other vertical's categories.
      return [];
    }
    final allCats = await db.query('categories', orderBy: 'name ASC');
    return allCats.map((json) => CategoryModel.fromMap(json)).toList();
  }

  Future<List<CustomerModel>> getAllCustomers() async {
    final db = await instance.database;
    final result = await db.query('customers', orderBy: 'name ASC');
    return result.map((json) => CustomerModel.fromMap(json)).toList();
  }

  Future<ProductModel?> findProductByBarcode(String barcode, {String? businessType}) async {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) return null;
    final db = await instance.database;
    String whereClause = 'barcode = ?';
    List<dynamic> whereArgs = [cleanBarcode];
    if (businessType != null && businessType.isNotEmpty) {
      whereClause += " AND (business_type = ? OR business_type = 'both')";
      whereArgs.add(businessType);
    }
    final result = await db.query(
      'products',
      where: whereClause,
      whereArgs: whereArgs,
      limit: 1,
    );
    if (result.isNotEmpty) {
      return ProductModel.fromMap(result.first);
    }
    return null;
  }

  // --- MASTER CATALOG APIS (<2ms indexed offline lookup) ---

  /// Fast indexed barcode lookup in Master Catalog (<2ms)
  Future<MasterProductModel?> findMasterProductByBarcode(
    String barcode, {
    String? businessType,
  }) async {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) return null;
    final db = await instance.database;
    String whereClause = 'barcode = ?';
    List<dynamic> whereArgs = [cleanBarcode];
    if (businessType != null && businessType.isNotEmpty) {
      whereClause += " AND (business_type = ? OR business_type = 'both')";
      whereArgs.add(businessType);
    }
    final result = await db.query(
      'master_catalog',
      where: whereClause,
      whereArgs: whereArgs,
      limit: 1,
    );
    if (result.isNotEmpty) {
      return MasterProductModel.fromMap(result.first);
    }
    // No cross-vertical fallback: a barcode scanned in Clothing/Hardware
    // (where master_catalog deliberately has no entries — see the Phase 2
    // catalog-depth decision) must never resolve to a Grocery/Pharmacy row
    // that happens to share the same barcode. That was exactly the same
    // isolation bug already fixed once for getAllProducts/getAllCategories
    // (see DEVELOPMENT_LOG.md's case study) — returning null here lets the
    // caller fall through to its "new barcode, add manually" flow instead.
    return null;
  }

  /// Fast substring / prefix search in Master Catalog for POS autocomplete
  Future<List<MasterProductModel>> searchMasterCatalog(
    String query, {
    String? businessType,
    String? category,
    int limit = 25,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];
    final db = await instance.database;

    String whereClause = '(name LIKE ? OR barcode LIKE ?)';
    List<dynamic> whereArgs = ['%$cleanQuery%', '%$cleanQuery%'];

    if (businessType != null && businessType.isNotEmpty) {
      whereClause += " AND (business_type = ? OR business_type = 'both')";
      whereArgs.add(businessType);
    }

    if (category != null && category.isNotEmpty) {
      whereClause += ' AND category = ?';
      whereArgs.add(category);
    }

    final result = await db.query(
      'master_catalog',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: "CASE WHEN name LIKE '$cleanQuery%' THEN 0 ELSE 1 END, name ASC",
      limit: limit,
    );

    return result.map((row) => MasterProductModel.fromMap(row)).toList();
  }

  /// Insert or update an item in the local master catalog (e.g. from cloud barcode resolution)
  Future<void> insertMasterProduct(MasterProductModel item) async {
    final db = await instance.database;
    await db.insert(
      'master_catalog',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Total count of items available in the offline master catalog
  Future<int> getMasterCatalogCount() async {
    final db = await instance.database;
    final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM master_catalog');
    return Sqflite.firstIntValue(countResult) ?? 0;
  }

  /// 1-Tap import from Master Catalog into the active store inventory.
  /// If already in store, returns the existing product without creating duplicates.
  Future<ProductModel> importMasterProductToStore(
    MasterProductModel masterItem, {
    String? businessId,
    String? targetVertical,
    double initialStock = 99999.0, // Default: Unlimited / Uncounted
    int? customSellingPricePaise,
  }) async {
    final effectiveVertical = masterItem.businessType == 'both'
        ? 'both'
        : ((targetVertical != null && targetVertical.isNotEmpty)
            ? targetVertical
            : masterItem.businessType);

    // Vertical-scoped duplicate check. This used to call
    // findProductByBarcode(barcode) with no vertical, so a barcode already
    // imported into the Grocery catalog was returned verbatim when the SAME
    // barcode was scanned in Pharmacy — the pharmacy billed a grocery row it
    // could not see in its own catalog, and any stock deduction landed on the
    // other vertical's product. Same cross-vertical leak class as the
    // getAllProducts regression in DEVELOPMENT_LOG.md's case study.
    final existing = await findProductByBarcode(
      masterItem.barcode,
      businessType: effectiveVertical == 'both' ? null : effectiveVertical,
    );
    if (existing != null) {
      return existing;
    }

    String bizId = businessId ?? '';
    if (bizId.isEmpty) {
      final db = await instance.database;
      final existingRows = await db.query('products', columns: ['business_id'], limit: 1);
      if (existingRows.isNotEmpty && existingRows.first['business_id'] != null) {
        bizId = existingRows.first['business_id'] as String;
      } else {
        bizId = 'biz_default_retail';
      }
    }

    String? categoryId;
    if (masterItem.category.isNotEmpty && masterItem.category.toLowerCase() != 'general') {
      final db = await instance.database;
      // Vertical-scoped too, matching findOrCreateCategoryId. Without the
      // business_type clause an import could silently attach the product to a
      // same-named category belonging to a different vertical, which then
      // hides the product behind a category pill it never shows under.
      final existingCat = await db.query(
        'categories',
        where: "LOWER(TRIM(name)) = ? AND (business_type = ? OR business_type = 'both')",
        whereArgs: [masterItem.category.trim().toLowerCase(), effectiveVertical],
        limit: 1,
      );
      if (existingCat.isNotEmpty) {
        categoryId = existingCat.first['id'] as String?;
      } else {
        final newCatId = 'cat_${DateTime.now().millisecondsSinceEpoch}';
        await db.insert('categories', {
          'id': newCatId,
          'business_id': bizId,
          'name': masterItem.category.trim(),
          'business_type': effectiveVertical,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        categoryId = newCatId;
      }
    }

    final newProduct = masterItem.toProductModel(
      businessId: bizId,
      categoryId: categoryId,
      initialStock: initialStock,
      customSellingPricePaise: customSellingPricePaise,
    ).copyWith(
      businessType: effectiveVertical,
    );

    await upsertProduct(newProduct);
    return newProduct;
  }


  Future<int> getNextInvoiceSequence() async {
    final db = await instance.database;
    return await db.transaction((txn) async {
      // Ensure counter exists; if first time, seed from existing max sales count
      final row = await txn.query(
        'app_counters',
        where: 'key = ?',
        whereArgs: ['invoice_sequence'],
        limit: 1,
      );

      int nextVal = 1;
      if (row.isEmpty) {
        final countRes = await txn.rawQuery('SELECT COUNT(*) as count FROM sales');
        final currentSalesCount = Sqflite.firstIntValue(countRes) ?? 0;
        nextVal = currentSalesCount + 1;
        await txn.insert('app_counters', {
          'key': 'invoice_sequence',
          'last_val': nextVal,
        });
      } else {
        final currentVal = (row.first['last_val'] as num?)?.toInt() ?? 0;
        nextVal = currentVal + 1;
        await txn.update(
          'app_counters',
          {'last_val': nextVal},
          where: 'key = ?',
          whereArgs: ['invoice_sequence'],
        );
      }
      return nextVal;
    });
  }

  // --- ATOMIC MULTI-TABLE POS TRANSACTION (Sub-10ms) ---
  Future<SaleModel> processPosBill({
    required String businessId,
    required List<CartItemModel> cartItems,
    required String paymentMethod,
    CustomerModel? customer,
    String? doctorName,
    String? tableNumber,
    int discountPaise = 0,
    int splitCashPaise = 0,
    int splitUpiPaise = 0,
    int splitCreditPaise = 0,
  }) async {
    final db = await instance.database;

    final seq = await getNextInvoiceSequence();
    final String invoiceNumber = 'INV-${seq.toString().padLeft(3, '0')}';
    final saleId = _uuid.v4();

    int subtotalPaise = 0;
    int totalTaxPaise = 0;
    int grandTotalPaise = 0;
    List<Map<String, dynamic>> itemsList = [];

    for (var item in cartItems) {
      subtotalPaise += item.grossTotalPaise;
      if (item.product.taxRate > 0) {
        final gst = MoneyFormatter.calculateGst(
          grossOrBasePaise: item.grossTotalPaise,
          taxRatePercent: item.product.taxRate,
          isInclusive: item.product.isTaxInclusive,
        );
        totalTaxPaise += gst['totalGst'] ?? 0;
        grandTotalPaise += gst['grossTotal'] ?? item.grossTotalPaise;
      } else {
        grandTotalPaise += item.grossTotalPaise;
      }
      itemsList.add(item.toMap());
    }

    final totalAmountPaise = grandTotalPaise - discountPaise;

    final sale = SaleModel(
      id: saleId,
      businessId: businessId,
      invoiceNumber: invoiceNumber,
      customerId: customer?.id,
      customerName: customer?.name,
      customerPhone: customer?.phone,
      customerGstin: customer?.gstin,
      placeOfSupply: customer?.stateCode ?? (customer?.gstin != null ? GstHelper.getStateFromGstin(customer!.gstin) : null),
      doctorName: doctorName,
      tableNumber: tableNumber,
      subtotalPaise: subtotalPaise,
      taxAmountPaise: totalTaxPaise,
      discountPaise: discountPaise,
      totalAmountPaise: totalAmountPaise,
      paymentMethod: paymentMethod,
      splitCashPaise: splitCashPaise,
      splitUpiPaise: splitUpiPaise,
      splitCreditPaise: splitCreditPaise,
      items: itemsList,
      createdAt: DateTime.now(),
      syncStatus: 'pending',
    );

    // ATOMIC SQLite TRANSACTION: Ensures all tables mutate together safely
    await db.transaction((txn) async {
      // 1. Insert Sale record
      await txn.insert('sales', sale.toMap());

      // 2. Decrement inventory stock for each sold product & record audit movement
      for (var item in cartItems) {
        await txn.rawUpdate('''
          UPDATE products
          SET stock_quantity = stock_quantity - ?
          WHERE id = ?
        ''', [item.quantity, item.product.id]);

        final movement = InventoryMovementModel(
          id: _uuid.v4(),
          businessId: businessId,
          productId: item.product.id,
          productName: item.product.name,
          movementType: 'SALE',
          quantity: item.quantity,
          previousStock: item.product.stockQuantity,
          newStock: item.product.stockQuantity - item.quantity,
          referenceId: saleId,
          createdAt: DateTime.now(),
        );
        await txn.insert('inventory_movements', movement.toMap());
      }

      // 3. If full Credit OR Split Credit, update customer balance and record ledger entry
      final creditDue = paymentMethod == 'credit'
          ? totalAmountPaise
          : (paymentMethod == 'split' ? splitCreditPaise : 0);

      if (creditDue > 0 && customer != null) {
        // Query fresh balance directly from DB inside transaction to guarantee zero stale overwrite
        final custRows = await txn.query(
          'customers',
          columns: ['current_balance_paise'],
          where: 'id = ?',
          whereArgs: [customer.id],
        );
        final int currentDbBalance = custRows.isNotEmpty
            ? (custRows.first['current_balance_paise'] as int? ?? 0)
            : customer.currentBalancePaise;

        final newBalancePaise = currentDbBalance + creditDue;

        await txn.rawUpdate('''
          UPDATE customers
          SET current_balance_paise = ?
          WHERE id = ?
        ''', [newBalancePaise, customer.id]);

        final ledgerEntry = LedgerTransactionModel(
          id: _uuid.v4(),
          businessId: businessId,
          customerId: customer.id,
          type: 'credit', // Credit given to customer
          amountPaise: creditDue,
          balanceAfterPaise: newBalancePaise,
          description: paymentMethod == 'split'
              ? 'Bill #$invoiceNumber Udhar (Split)'
              : 'Bill #$invoiceNumber Udhar',
          referenceId: saleId,
          createdAt: DateTime.now(),
          syncStatus: 'pending',
        );

        await txn.insert('ledger_transactions', ledgerEntry.toMap());
      }
    });

    // Best-effort FEFO batch bookkeeping — deliberately AFTER the sale's own
    // atomic transaction has already committed, and wrapped so it can never
    // fail the sale itself. This is a no-op for any product with no
    // product_batches rows (every non-pharmacy item, and any pharmacy item
    // never inwarded through the batch-aware flow) — see _deductStockFefo's
    // doc comment for why that makes it safe to call unconditionally here
    // rather than checking the vertical first.
    for (var item in cartItems) {
      try {
        await _deductStockFefo(item.product.id, item.quantity);
      } catch (_) {}
    }

    // Tell every other screen the bill landed: sales + stock always, khata when the
    // bill carries credit, cash drawer when money physically came in.
    final bool touchedCustomer = customer != null &&
        (paymentMethod == 'credit' ||
            (paymentMethod == 'split' && splitCreditPaise > 0));
    final bool touchedCash =
        paymentMethod == 'cash' || (paymentMethod == 'split' && splitCashPaise > 0);
    AppDataBus.instance.bumpSaleCompleted(
      affectsCustomer: touchedCustomer,
      affectsCash: touchedCash,
    );

    return sale;
  }

  // --- 1-TAP SALES RETURN / REFUND ENGINE ---
  Future<void> processSalesReturn({
    required SaleModel sale,
    String refundMethod = 'cash', // 'cash', 'credit', 'credit_note'
    String reason = 'Customer Return',
    String? customerId,
  }) async {
    final db = await instance.database;
    final returnId = _uuid.v4();
    final returnNumber = 'RET-${_uuid.v4().substring(0, 8).toUpperCase()}';
    final targetCustId = customerId ?? sale.customerId;

    await db.transaction((txn) async {
      // 1. Mark sale status as 'refunded' and mark all items fully returned
      final updatedItems = sale.items.map((it) {
        final m = Map<String, dynamic>.from(it);
        m['returned_quantity'] = m['quantity'] ?? m['qty'] ?? 1;
        return m;
      }).toList();

      await txn.update(
        'sales',
        {
          'status': 'refunded',
          'items_json': jsonEncode(updatedItems),
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: [sale.id],
      );

      // 2. Restock all products into inventory & record audit movement
      for (final it in sale.items) {
        final prodId = it['product_id'] ?? it['id'];
        final prodName = (it['product_name'] ?? it['name'] ?? 'Item').toString();
        final num rawQty = it['quantity'] ?? it['qty'] ?? 1;
        final double qty = rawQty.toDouble();

        List<Map<String, dynamic>> prodRows = [];
        if (prodId != null && prodId.toString().isNotEmpty) {
          prodRows = await txn.query('products', where: 'id = ?', whereArgs: [prodId.toString()]);
        }
        if (prodRows.isEmpty && prodName.isNotEmpty) {
          prodRows = await txn.query('products', where: 'name = ?', whereArgs: [prodName]);
        }

        if (prodRows.isNotEmpty) {
          final pMap = prodRows.first;
          final currentStock = (pMap['stock_quantity'] as num).toDouble();
          final targetProdId = pMap['id'].toString();
          final newStock = currentStock + qty;

          await txn.rawUpdate('''
            UPDATE products
            SET stock_quantity = stock_quantity + ?
            WHERE id = ?
          ''', [qty, targetProdId]);

          final batchId = it['batch_id'];
          if (batchId != null && batchId.toString().isNotEmpty) {
            await txn.rawUpdate('''
              UPDATE product_batches
              SET quantity = quantity + ?
              WHERE id = ?
            ''', [qty, batchId.toString()]);
          }

          final movement = InventoryMovementModel(
            id: _uuid.v4(),
            businessId: sale.businessId,
            productId: targetProdId,
            productName: prodName,
            movementType: 'RETURN',
            quantity: qty,
            previousStock: currentStock,
            newStock: newStock,
            referenceId: returnNumber,
            createdAt: DateTime.now(),
          );
          await txn.insert('inventory_movements', movement.toMap());
        }
      }

      // 3. Insert record into sale_returns
      await txn.insert('sale_returns', {
        'id': returnId,
        'sale_id': sale.id,
        'return_number': returnNumber,
        'items_returned_json': jsonEncode(updatedItems),
        'total_refund_paise': sale.totalAmountPaise,
        'refund_method': refundMethod,
        'reason': reason,
        'created_at': DateTime.now().toIso8601String(),
        'sync_status': 'pending',
      });

      // 4. Handle Customer Credit / Store Credit
      final effectiveMethod = (refundMethod == 'credit' || refundMethod == 'credit_note')
          ? refundMethod
          : (sale.paymentMethod == 'credit' ? 'credit' : 'cash');

      if ((effectiveMethod == 'credit' || effectiveMethod == 'credit_note') &&
          targetCustId != null &&
          targetCustId.isNotEmpty) {
        final custRows = await txn.query('customers', where: 'id = ?', whereArgs: [targetCustId]);
        if (custRows.isNotEmpty) {
          final currentBal = (custRows.first['current_balance_paise'] as int?) ?? 0;
          // Sacred financial rule: No clamping! Negative balance natively represents Jama (Advance)
          final refundPaise = sale.totalAmountPaise;
          final newBal = currentBal - refundPaise;

          await txn.rawUpdate('''
            UPDATE customers
            SET current_balance_paise = ?
            WHERE id = ?
          ''', [newBal, targetCustId]);

          final ledgerEntry = LedgerTransactionModel(
            id: _uuid.v4(),
            businessId: sale.businessId,
            customerId: targetCustId,
            type: 'debit',
            amountPaise: refundPaise,
            balanceAfterPaise: newBal,
            description: effectiveMethod == 'credit_note'
                ? 'Store Credit: Full Return #$returnNumber (Inv #${sale.invoiceNumber})'
                : 'Udhar Reversal: Full Return #$returnNumber (Inv #${sale.invoiceNumber})',
            referenceId: returnId,
            createdAt: DateTime.now(),
            syncStatus: 'pending',
          );
          await txn.insert('ledger_transactions', ledgerEntry.toMap());
        }
      } else if (effectiveMethod == 'cash') {
        final cashToRefund = sale.paymentMethod == 'cash'
            ? sale.totalAmountPaise
            : (sale.paymentMethod == 'split' ? sale.splitCashPaise : sale.totalAmountPaise);

        if (cashToRefund > 0) {
          final refundExpense = ExpenseModel(
            id: _uuid.v4(),
            businessId: sale.businessId,
            title: 'Cash Refund: #$returnNumber (Inv #${sale.invoiceNumber})',
            amountPaise: cashToRefund,
            category: 'Refund',
            createdAt: DateTime.now(),
            note: reason,
          );
          await txn.insert('expenses', refundExpense.toMap());
        }
      }
    });

    // App-wide instant reactive notification across all open tabs
    AppDataBus.instance.bumpAll();
  }

  /// Processes partial sales return (Tukdo me wapsi):
  /// - Restocks only the returned items into SQLite inventory
  /// - Reverses customer credit/udhar, grants Store Credit (advance), or records cash drawer outflow
  /// - Inserts record into `sale_returns`
  /// - Updates cumulative returned quantities on the sale invoice
  Future<String> processPartialSalesReturn({
    required SaleModel sale,
    required List<Map<String, dynamic>> returnItems,
    required String refundMethod, // 'cash', 'credit', 'credit_note'
    String reason = 'Partial Customer Return',
    String? userPin,
    String? customerId,
  }) async {
    final db = await instance.database;
    final returnId = _uuid.v4();
    final returnNumber = 'RET-${_uuid.v4().substring(0, 8).toUpperCase()}';
    final targetCustId = customerId ?? sale.customerId;

    int totalRefundPaise = 0;
    for (final it in returnItems) {
      final num price = it['price_paise'] ?? it['selling_price_paise'] ?? 0;
      final num qty = it['return_quantity'] ?? it['quantity'] ?? 1;
      totalRefundPaise += (price * qty).toInt();
    }

    await db.transaction((txn) async {
      // 1. Restock only returned items into inventory & record audit movement
      for (final it in returnItems) {
        final prodId = it['product_id'] ?? it['id'];
        final prodName = (it['product_name'] ?? it['name'] ?? 'Item').toString();
        final num rawQty = it['return_quantity'] ?? it['quantity'] ?? 1;
        final double qty = rawQty.toDouble();
        if (qty <= 0) continue;

        List<Map<String, dynamic>> prodRows = [];
        if (prodId != null && prodId.toString().isNotEmpty) {
          prodRows = await txn.query('products', where: 'id = ?', whereArgs: [prodId.toString()]);
        }
        if (prodRows.isEmpty && prodName.isNotEmpty) {
          prodRows = await txn.query('products', where: 'name = ?', whereArgs: [prodName]);
        }

        if (prodRows.isNotEmpty) {
          final pMap = prodRows.first;
          final currentStock = (pMap['stock_quantity'] as num).toDouble();
          final targetProdId = pMap['id'].toString();
          final newStock = currentStock + qty;

          await txn.rawUpdate('''
            UPDATE products
            SET stock_quantity = stock_quantity + ?
            WHERE id = ?
          ''', [qty, targetProdId]);

          final batchId = it['batch_id'];
          if (batchId != null && batchId.toString().isNotEmpty) {
            await txn.rawUpdate('''
              UPDATE product_batches
              SET quantity = quantity + ?
              WHERE id = ?
            ''', [qty, batchId.toString()]);
          }

          final movement = InventoryMovementModel(
            id: _uuid.v4(),
            businessId: sale.businessId,
            productId: targetProdId,
            productName: prodName,
            movementType: 'PARTIAL_RETURN',
            quantity: qty,
            previousStock: currentStock,
            newStock: newStock,
            referenceId: returnNumber,
            createdAt: DateTime.now(),
          );
          await txn.insert('inventory_movements', movement.toMap());
        }
      }

      // 2. Insert into sale_returns table
      await txn.insert('sale_returns', {
        'id': returnId,
        'sale_id': sale.id,
        'return_number': returnNumber,
        'items_returned_json': jsonEncode(returnItems),
        'total_refund_paise': totalRefundPaise,
        'refund_method': refundMethod,
        'reason': reason,
        'created_at': DateTime.now().toIso8601String(),
        'sync_status': 'pending',
      });

      // 3. Update original sale items_json to record cumulative returned_quantity per item
      final List<dynamic> currentItems = List<dynamic>.from(sale.items);
      bool allFullyReturned = true;

      for (int i = 0; i < currentItems.length; i++) {
        final currentIt = Map<String, dynamic>.from(currentItems[i]);
        final cProdId = currentIt['product_id'] ?? currentIt['id'];
        final cProdName = currentIt['product_name'] ?? currentIt['name'];
        final num soldQty = currentIt['quantity'] ?? currentIt['qty'] ?? 1;
        num previouslyReturned = currentIt['returned_quantity'] ?? 0;

        for (final retIt in returnItems) {
          final rProdId = retIt['product_id'] ?? retIt['id'];
          final rProdName = retIt['product_name'] ?? retIt['name'];
          if ((cProdId != null && cProdId == rProdId) || (cProdName != null && cProdName == rProdName)) {
            final num retQty = retIt['return_quantity'] ?? retIt['quantity'] ?? 0;
            previouslyReturned += retQty;
            break;
          }
        }

        currentIt['returned_quantity'] = previouslyReturned;
        currentItems[i] = currentIt;

        if (previouslyReturned < soldQty) {
          allFullyReturned = false;
        }
      }

      final newStatus = allFullyReturned ? 'refunded' : 'partially_refunded';
      await txn.update(
        'sales',
        {
          'status': newStatus,
          'items_json': jsonEncode(currentItems),
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: [sale.id],
      );

      // 4. Handle Customer Udhar Reversal or Store Credit (Customer Advance)
      if ((refundMethod == 'credit' || refundMethod == 'credit_note') &&
          targetCustId != null &&
          targetCustId.isNotEmpty) {
        final custRows = await txn.query('customers', where: 'id = ?', whereArgs: [targetCustId]);
        if (custRows.isNotEmpty) {
          final currentBal = (custRows.first['current_balance_paise'] as int?) ?? 0;
          // Sacred financial rule: No clamping! Negative balance natively represents Jama (Advance)
          final newBal = currentBal - totalRefundPaise;

          await txn.rawUpdate('''
            UPDATE customers
            SET current_balance_paise = ?
            WHERE id = ?
          ''', [newBal, targetCustId]);

          final ledgerEntry = LedgerTransactionModel(
            id: _uuid.v4(),
            businessId: sale.businessId,
            customerId: targetCustId,
            type: 'debit',
            amountPaise: totalRefundPaise,
            balanceAfterPaise: newBal,
            description: refundMethod == 'credit_note'
                ? 'Store Credit: Return #$returnNumber (Inv #${sale.invoiceNumber})'
                : 'Udhar Reversal: Return #$returnNumber (Inv #${sale.invoiceNumber})',
            referenceId: returnId,
            createdAt: DateTime.now(),
            syncStatus: 'pending',
          );
          await txn.insert('ledger_transactions', ledgerEntry.toMap());
        }
      } else if (refundMethod == 'cash' && totalRefundPaise > 0) {
        // Record cash drawer refund outflow
        final refundExpense = ExpenseModel(
          id: _uuid.v4(),
          businessId: sale.businessId,
          title: 'Cash Refund: #$returnNumber (Inv #${sale.invoiceNumber})',
          amountPaise: totalRefundPaise,
          category: 'Refund',
          createdAt: DateTime.now(),
          note: reason,
        );
        await txn.insert('expenses', refundExpense.toMap());
      }
    });

    // App-wide instant reactive notification across all open tabs
    AppDataBus.instance.bumpAll();

    return returnNumber;
  }

  /// Returns all partial/full return receipts recorded for a specific sale.
  Future<List<Map<String, dynamic>>> getSaleReturns(String saleId) async {
    final db = await instance.database;
    return await db.query(
      'sale_returns',
      where: 'sale_id = ?',
      whereArgs: [saleId],
      orderBy: 'created_at DESC',
    );
  }

  /// Fetches all child variants belonging to a parent product.
  Future<List<ProductModel>> getVariantsForProduct(String parentId) async {
    final db = await instance.database;
    final rows = await db.query(
      'products',
      where: 'parent_id = ?',
      whereArgs: [parentId],
      orderBy: 'name ASC',
    );
    return rows.map((r) => ProductModel.fromMap(r)).toList();
  }

  /// Atomically saves a parent product and creates its child variants.
  Future<List<ProductModel>> createProductWithVariants({
    required ProductModel parentProduct,
    List<String>? variantLabels,
    List<VariantCustomData>? customVariants,
  }) async {
    final db = await instance.database;
    final List<ProductModel> createdVariants = [];

    await db.transaction((txn) async {
      final parentToSave = parentProduct.copyWith(hasVariants: true);
      await txn.insert(
        'products',
        parentToSave.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (customVariants != null && customVariants.isNotEmpty) {
        for (final cv in customVariants) {
          final variantId = _uuid.v4();
          final childVariant = ProductModel(
            id: variantId,
            businessId: parentToSave.businessId,
            name: '${parentToSave.name} (${cv.label})',
            barcode: cv.barcode != null && cv.barcode!.isNotEmpty ? cv.barcode : null,
            categoryId: parentToSave.categoryId,
            sellingPricePaise: cv.sellingPricePaise,
            mrpPaise: cv.mrpPaise > 0 ? cv.mrpPaise : cv.sellingPricePaise,
            purchasePricePaise: cv.purchasePricePaise,
            stockQuantity: cv.stockQuantity,
            taxRate: parentToSave.taxRate,
            isTaxInclusive: parentToSave.isTaxInclusive,
            unit: parentToSave.unit,
            size: cv.label,
            color: parentToSave.color,
            fitNotes: parentToSave.fitNotes,
            parentId: parentToSave.id,
            hasVariants: false,
            variantLabel: cv.label,
            syncStatus: 'pending',
            businessType: parentToSave.businessType,
          );
          await txn.insert(
            'products',
            childVariant.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          createdVariants.add(childVariant);
        }
      } else if (variantLabels != null) {
        for (final label in variantLabels) {
          final variantId = _uuid.v4();
          final childVariant = ProductModel(
            id: variantId,
            businessId: parentToSave.businessId,
            name: '${parentToSave.name} ($label)',
            categoryId: parentToSave.categoryId,
            sellingPricePaise: parentToSave.sellingPricePaise,
            mrpPaise: parentToSave.mrpPaise,
            purchasePricePaise: parentToSave.purchasePricePaise,
            stockQuantity: parentToSave.stockQuantity,
            taxRate: parentToSave.taxRate,
            isTaxInclusive: parentToSave.isTaxInclusive,
            unit: parentToSave.unit,
            size: label,
            color: parentToSave.color,
            fitNotes: parentToSave.fitNotes,
            parentId: parentToSave.id,
            hasVariants: false,
            variantLabel: label,
            syncStatus: 'pending',
            businessType: parentToSave.businessType,
          );
          await txn.insert(
            'products',
            childVariant.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          createdVariants.add(childVariant);
        }
      }
    });
    AppDataBus.instance.bumpProducts();
    return createdVariants;
  }

  Future<void> upsertProduct(ProductModel product) async {
    final db = await instance.database;
    await db.insert(
      'products',
      product.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    AppDataBus.instance.bumpProducts();
  }

  Future<void> deleteProduct(String id) async {
    final db = await instance.database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
    AppDataBus.instance.bumpProducts();
  }

  /// Adds [delta] to one product's stock and optionally updates its prices, as a
  /// targeted relative UPDATE inside a transaction.
  ///
  /// Deliberately NOT `upsertProduct(product.copyWith(stockQuantity: old + qty))`,
  /// which is how every inward screen used to do it. That pattern reads a
  /// ProductModel when a screen opens, adds to the number it captured, and
  /// writes the whole row back with ConflictAlgorithm.replace — so anything that
  /// changed in between is silently reverted. Inward happens while the shop is
  /// open and billing, so the lost update is real: ring up a sale while the
  /// inward sheet is open, save the inward, and the sale's deduction disappears.
  /// `stock_quantity = stock_quantity + ?` is evaluated by SQLite against the
  /// CURRENT row instead, exactly how processPosBill already deducts a sale.
  ///
  /// A product at or above the 99999 "unlimited / uncounted" sentinel keeps that
  /// sentinel — adding a delivery to an uncounted item must not turn it into a
  /// counted one. Prices still apply in that case.
  ///
  /// Returns the before and after quantities so the caller can record an
  /// accurate InventoryMovementModel without a second read.
  Future<StockDeltaResult> applyStockDelta(
    String productId,
    double delta, {
    int? purchasePricePaise,
    int? sellingPricePaise,
    int? mrpPaise,
  }) async {
    final db = await instance.database;
    final result = await db.transaction((txn) async {
      final rows = await txn.query(
        'products',
        columns: ['stock_quantity'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return const StockDeltaResult(previousStock: 0, newStock: 0, found: false);
      }
      final previous = (rows.first['stock_quantity'] as num?)?.toDouble() ?? 0.0;

      final priceUpdates = <String, Object?>{'sync_status': 'pending'};
      if (purchasePricePaise != null && purchasePricePaise > 0) {
        priceUpdates['purchase_price_paise'] = purchasePricePaise;
      }
      if (sellingPricePaise != null && sellingPricePaise > 0) {
        priceUpdates['selling_price_paise'] = sellingPricePaise;
      }
      if (mrpPaise != null && mrpPaise > 0) {
        priceUpdates['mrp_paise'] = mrpPaise;
      }
      await txn.update('products', priceUpdates,
          where: 'id = ?', whereArgs: [productId]);

      final isUnlimited = previous >= 99999;
      if (delta != 0 && !isUnlimited) {
        await txn.rawUpdate(
          'UPDATE products SET stock_quantity = MAX(0, stock_quantity + ?) WHERE id = ?',
          [delta, productId],
        );
      }

      final after = await txn.query(
        'products',
        columns: ['stock_quantity'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      return StockDeltaResult(
        previousStock: previous,
        newStock: (after.first['stock_quantity'] as num?)?.toDouble() ?? previous,
        found: true,
      );
    });
    AppDataBus.instance.bumpProducts();
    return result;
  }

  // ==========================================================================
  // PRODUCT BATCHES — real multi-batch FEFO (First-Expiry-First-Out).
  // See ProductBatchModel's doc comment for the design: this table is the
  // source of truth for per-delivery quantity/expiry; ProductModel.
  // stockQuantity/expiryDate/batchNumber stay as fast denormalized summaries
  // the billing screen already reads today, unchanged.
  // ==========================================================================

  /// Records one delivery/batch. Deliberately does NOT touch
  /// products.stock_quantity itself — the caller (quick_stock_update_modal.dart's
  /// inward flow) already updates that via its own `upsertProduct` call, the
  /// same as before this feature existed; recording a batch is a parallel,
  /// additive bookkeeping step. It DOES refresh the product's denormalized
  /// expiry_date/batch_number (the soonest-expiring batch) so the existing
  /// "SELL FIRST" billing badge (expiry_utils.dart, reading ProductModel
  /// directly) reflects the new delivery without any change to that code.
  Future<void> addProductBatch(ProductBatchModel batch) async {
    final db = await instance.database;
    await db.insert('product_batches', batch.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await _recomputeProductExpirySummary(db, batch.productId);
    AppDataBus.instance.bumpProducts();
  }

  /// Every batch for a product, soonest-expiring first (nulls — unknown
  /// expiry — sorted last, since a known-expiring batch is the more urgent
  /// one to sell). Powers the "Batches" viewer in quick_stock_update_modal.dart.
  Future<List<ProductBatchModel>> getBatchesForProduct(String productId) async {
    final db = await instance.database;
    final rows = await db.query('product_batches', where: 'product_id = ? AND quantity > 0', whereArgs: [productId]);
    final batches = rows.map((r) => ProductBatchModel.fromMap(r)).toList();
    batches.sort((a, b) {
      if (a.expiryDate == null && b.expiryDate == null) return 0;
      if (a.expiryDate == null) return 1;
      if (b.expiryDate == null) return -1;
      return a.expiryDate!.compareTo(b.expiryDate!);
    });
    return batches;
  }

  /// Deducts [qty] from a product's batches in FEFO order (soonest expiry
  /// first; unknown-expiry batches last), for the portion of a sale that
  /// batch-tracking actually knows about. A product with no batches (every
  /// non-pharmacy item, and any pharmacy item never inwarded through the
  /// batch-aware flow) simply has nothing to deduct — a harmless no-op, not
  /// an error — which is why processPosBill calls this unconditionally for
  /// every sold item rather than checking the vertical first.
  ///
  /// Deliberately called AFTER the sale's own atomic transaction commits,
  /// never inside it, and wrapped in try/catch by its caller: this is
  /// bookkeeping on top of an already-correct stock_quantity deduction
  /// (processPosBill's existing raw UPDATE), never allowed to be the reason
  /// a real sale fails to save.
  Future<void> _deductStockFefo(String productId, double qty) async {
    if (qty <= 0) return;
    final db = await instance.database;
    var remaining = qty;
    final batches = await getBatchesForProduct(productId);

    // A product that was never inwarded through the batch-aware flow has
    // nothing here to deduct, and — critically — nothing here to summarise
    // either. Returning now is what makes this the harmless no-op the doc
    // comment above promises.
    //
    // It did NOT used to return: it fell through to
    // _recomputeProductExpirySummary, which derives expiry_date/batch_number
    // from the batch list and therefore wrote NULL over both columns whenever
    // that list was empty. Since processPosBill calls this for EVERY sold item,
    // selling a single unit of any product whose expiry had been typed in by
    // hand (add_product_modal, not a batch) permanently erased that expiry —
    // and with it the product's row in the Inventory "Near Expiry" radar, whose
    // no-batch fallback reads exactly those two columns.
    if (batches.isEmpty) return;

    for (final batch in batches) {
      if (remaining <= 0) break;
      final take = remaining >= batch.quantity ? batch.quantity : remaining;
      final newQty = batch.quantity - take;
      if (newQty <= 0) {
        await db.delete('product_batches', where: 'id = ?', whereArgs: [batch.id]);
      } else {
        await db.update('product_batches', {'quantity': newQty}, where: 'id = ?', whereArgs: [batch.id]);
      }
      remaining -= take;
    }
    await _recomputeProductExpirySummary(db, productId);
  }

  /// Every batch, across every product for [businessType], expiring within
  /// [withinDays] — the real, per-batch version of what
  /// inventory_screen.dart's "Near Expiry" radar used to compute from each
  /// product's single denormalized expiryDate/stockQuantity (which could
  /// only ever show ONE batch per product, and with the wrong quantity —
  /// the product's full aggregate stock, not that specific batch's). A
  /// product with two deliveries expiring at different times now correctly
  /// produces two separate rows here, each with its own real quantity.
  Future<List<Map<String, dynamic>>> getNearExpiryBatches(String businessType, {int withinDays = 90}) async {
    final now = DateTime.now();
    final products = await getAllProducts(businessType: businessType);
    final results = <Map<String, dynamic>>[];

    for (final product in products) {
      final batches = await getBatchesForProduct(product.id);
      if (batches.isEmpty) {
        final expiryStr = product.expiryDate?.trim();
        if (expiryStr != null && expiryStr.isNotEmpty) {
          DateTime? expiry = DateTime.tryParse(expiryStr);
          if (expiry == null && expiryStr.contains('/')) {
            final parts = expiryStr.split('/');
            if (parts.length == 2) {
              final month = int.tryParse(parts[0]);
              var year = int.tryParse(parts[1]);
              if (month != null && year != null) {
                if (year < 100) year += 2000;
                expiry = DateTime(year, month, 28);
              }
            } else if (parts.length == 3) {
              final day = int.tryParse(parts[0]);
              final month = int.tryParse(parts[1]);
              final year = int.tryParse(parts[2]);
              if (day != null && month != null && year != null) {
                expiry = DateTime(year, month, day);
              }
            }
          }
          if (expiry != null) {
            final daysLeft = expiry.difference(now).inDays;
            if (daysLeft <= withinDays) {
              results.add({
                'product_name': product.name,
                'batch_no': product.batchNumber?.isNotEmpty == true ? product.batchNumber! : 'MAIN',
                'qty': product.stockQuantity.toInt(),
                'unit': product.unit,
                'expiry_date': expiry,
                'days_left': daysLeft,
                'cost_paise': product.purchasePricePaise,
                'status': daysLeft <= 0 ? 'Expired' : (daysLeft <= 30 ? 'Expiring Soon (<30d)' : 'Under 90 Days'),
                'is_urgent': daysLeft <= 30,
              });
            }
          }
        }
        continue;
      }
      for (final batch in batches) {
        final expiryStr = batch.expiryDate?.trim();
        if (expiryStr == null || expiryStr.isEmpty) continue;
        DateTime? expiry = DateTime.tryParse(expiryStr);
        if (expiry == null && expiryStr.contains('/')) {
          final parts = expiryStr.split('/');
          if (parts.length == 2) {
            final month = int.tryParse(parts[0]);
            var year = int.tryParse(parts[1]);
            if (month != null && year != null) {
              if (year < 100) year += 2000;
              expiry = DateTime(year, month, 28);
            }
          } else if (parts.length == 3) {
            final day = int.tryParse(parts[0]);
            final month = int.tryParse(parts[1]);
            final year = int.tryParse(parts[2]);
            if (day != null && month != null && year != null) {
              expiry = DateTime(year, month, day);
            }
          }
        }
        if (expiry == null) continue;

        final daysLeft = expiry.difference(now).inDays;
        if (daysLeft > withinDays) continue;

        results.add({
          'product_name': product.name,
          'batch_no': batch.batchNumber?.isNotEmpty == true ? batch.batchNumber! : 'DEFAULT',
          'qty': batch.quantity.toInt(),
          'unit': product.unit,
          'expiry_date': expiry,
          'days_left': daysLeft,
          'cost_paise': batch.purchasePricePaise,
          'status': daysLeft <= 0 ? 'Expired' : (daysLeft <= 30 ? 'Expiring Soon (<30d)' : 'Under 90 Days'),
          'is_urgent': daysLeft <= 30,
        });
      }
    }

    results.sort((a, b) => (a['days_left'] as int).compareTo(b['days_left'] as int));
    return results;
  }

  /// Refreshes products.expiry_date/batch_number from whichever batch now
  /// has the soonest expiry (or clears both if no batches remain) — the
  /// denormalized summary every existing billing-screen badge already reads.
  Future<void> _recomputeProductExpirySummary(Database db, String productId) async {
    final batches = await getBatchesForProduct(productId);
    final soonest = batches.isEmpty ? null : batches.first;
    await db.update(
      'products',
      {
        'expiry_date': soonest?.expiryDate,
        'batch_number': soonest?.batchNumber,
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<void> toggleProductFavorite(String id, bool isFavorite) async {
    final db = await instance.database;
    await db.update(
      'products',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    AppDataBus.instance.bumpProducts();
  }

  Future<void> upsertCategory(CategoryModel category) async {
    final db = await instance.database;
    await db.insert(
      'categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Category pills are rendered by the product screens, so they reload on this too.
    AppDataBus.instance.bumpProducts();
  }

  /// Finds an existing category by name (case-insensitive) within a business
  /// vertical, or creates one. Bulk-import flows (menu scan, master-catalog
  /// import, AI inward) each need this same lookup-or-create step; this is the
  /// one place to change it. Note: `importMasterProductToStore` has its own
  /// inline copy of this same pattern, predating this helper — left as-is
  /// rather than refactored, to avoid touching a tested existing flow.
  Future<String> findOrCreateCategoryId({
    required String name,
    required String businessId,
    required String businessType,
  }) async {
    final cleanName = name.trim();
    final db = await instance.database;
    final existing = await db.query(
      'categories',
      where: 'LOWER(TRIM(name)) = ? AND (business_type = ? OR business_type = \'both\')',
      whereArgs: [cleanName.toLowerCase(), businessType],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as String;
    }

    final newId = 'cat_${businessType}_${_uuid.v4().substring(0, 8)}';
    await upsertCategory(CategoryModel(
      id: newId,
      businessId: businessId,
      name: cleanName,
      businessType: businessType,
    ));
    return newId;
  }

  Future<CustomerModel?> findCustomerByPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '').trim();
    if (cleanPhone.isEmpty) return null;
    final db = await instance.database;
    final result = await db.query(
      'customers',
      where: 'phone = ?',
      whereArgs: [cleanPhone],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return CustomerModel.fromMap(result.first);
    }
    return null;
  }

  Future<void> upsertCustomer(CustomerModel customer) async {
    final db = await instance.database;
    await db.insert(
      'customers',
      customer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    AppDataBus.instance.bumpCustomers();
  }

  Future<void> toggleCustomerVip(String id, bool isVip) async {
    final db = await instance.database;
    await db.update(
      'customers',
      {'is_vip': isVip ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    AppDataBus.instance.bumpCustomers();
  }

  Future<void> deleteCustomer(String id) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('ledger_transactions', where: 'customer_id = ?', whereArgs: [id]);
      await txn.delete('customers', where: 'id = ?', whereArgs: [id]);
    });
    AppDataBus.instance.bumpCustomers();
  }

  Future<CustomerModel?> getCustomerById(String id) async {
    final db = await instance.database;
    final result = await db.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
    if (result.isNotEmpty) {
      return CustomerModel.fromMap(result.first);
    }
    return null;
  }

  Future<void> upsertSale(SaleModel sale) async {
    final db = await instance.database;
    await db.insert('sales', sale.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    AppDataBus.instance.bumpSales();
  }

  Future<SaleModel?> getSaleById(String id) async {
    final db = await instance.database;
    final result = await db.query('sales', where: 'id = ?', whereArgs: [id], limit: 1);
    if (result.isNotEmpty) {
      return SaleModel.fromMap(result.first);
    }
    return null;
  }

  Future<List<SaleModel>> getAllSales({int limit = 100}) async {
    final db = await instance.database;
    final result = await db.query('sales', orderBy: 'created_at DESC', limit: limit);
    return result.map((json) => SaleModel.fromMap(json)).toList();
  }

  /// Every sale in a half-open date range, with NO row cap.
  ///
  /// Added because "today's" figures were being derived by pulling the last
  /// N sales and filtering them in Dart — a shop that crossed N bills in a
  /// day had its own day silently truncated, and the busier the shop, the
  /// more wrong the dashboard got.
  Future<List<SaleModel>> getSalesBetween(DateTime start, DateTime end) async {
    final db = await instance.database;
    final result = await db.query(
      'sales',
      where: 'created_at >= ? AND created_at < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'created_at DESC',
    );
    return result.map((json) => SaleModel.fromMap(json)).toList();
  }

  /// Real gross margin for a day, computed line by line from the buying rate
  /// frozen onto each sale item at billing time.
  ///
  /// This replaces `todaySales * 0.14` — a hardcoded 14% of turnover that the
  /// Home dashboard presented as "Est. Profit / Live Margin" behind an owner
  /// PIN. It moved with revenue no matter what the shop actually bought at,
  /// so a day selling nothing but loss-leaders and a day selling nothing but
  /// high-margin goods reported the identical "profit".
  ///
  /// Lines whose cost is unknown (0 — never inwarded with a buying price, or
  /// billed before cost was frozen onto the line) are EXCLUDED from the
  /// margin rather than counted as 100% profit, and reported separately so
  /// the UI can tell the owner the figure is partial instead of quietly
  /// overstating it.
  Future<DayProfitSummary> getDayProfitSummary(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    final sales = await getSalesBetween(start, end);
    int costedRevenue = 0;
    int costOfGoods = 0;
    int uncostedRevenue = 0;
    int uncostedLines = 0;

    for (final sale in sales) {
      if (sale.isRefunded) continue;
      for (final raw in sale.items) {
        final rawQty = (raw['quantity'] as num?)?.toDouble() ?? 0.0;
        final returnedQty = (raw['returned_quantity'] as num?)?.toDouble() ?? 0.0;
        final qty = (rawQty - returnedQty).clamp(0.0, rawQty);
        if (qty <= 0) continue;

        final lineRevenue = (raw['gross_total_paise'] as num?)?.toInt() ??
            (((raw['unit_price_paise'] as num?)?.toInt() ?? 0) * qty).round();
        final unitCost = (raw['cost_price_paise'] as num?)?.toInt() ?? 0;

        if (unitCost <= 0) {
          uncostedRevenue += lineRevenue;
          uncostedLines++;
          continue;
        }
        costedRevenue += lineRevenue;
        costOfGoods += (unitCost * qty).round();
      }
    }

    final expenses = await getAllExpenses();
    // Exclude 'Refund' category because cash refund is a drawer balancing outflow, not an operational expense
    final dayExpenses = expenses
        .where((e) =>
            e.category != 'Refund' &&
            !e.createdAt.isBefore(start) &&
            e.createdAt.isBefore(end))
        .fold<int>(0, (sum, e) => sum + e.amountPaise);

    return DayProfitSummary(
      grossMarginPaise: costedRevenue - costOfGoods,
      netProfitPaise: costedRevenue - costOfGoods - dayExpenses,
      costedRevenuePaise: costedRevenue,
      uncostedRevenuePaise: uncostedRevenue,
      uncostedLineCount: uncostedLines,
      expensesPaise: dayExpenses,
    );
  }

  Future<List<LedgerTransactionModel>> getLedgerForCustomer(String customerId) async {
    final db = await instance.database;
    final result = await db.query(
      'ledger_transactions',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );
    return result.map((json) => LedgerTransactionModel.fromMap(json)).toList();
  }

  Future<List<SaleModel>> getSalesForCustomer(String customerId, {String? phone}) async {
    final db = await instance.database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (customerId.isNotEmpty) {
      whereClauses.add('customer_id = ?');
      whereArgs.add(customerId);
    }
    if (phone != null && phone.isNotEmpty) {
      whereClauses.add('customer_phone = ?');
      whereArgs.add(phone);
    }

    if (whereClauses.isEmpty) return [];

    final result = await db.query(
      'sales',
      where: whereClauses.join(' OR '),
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );
    return result.map((json) => SaleModel.fromMap(json)).toList();
  }

  Future<void> recordCustomerLedgerEntry({
    required CustomerModel customer,
    required String type, // 'credit' (Udhar Diya) | 'debit' (Jama Mila)
    required int amountPaise,
    required String description,
    String? referenceId,
  }) async {
    final db = await instance.database;
    final isUdhar = type == 'credit';

    await db.transaction((txn) async {
      // Query fresh balance directly from DB inside transaction to prevent race condition or stale UI reference
      final custRows = await txn.query(
        'customers',
        columns: ['current_balance_paise'],
        where: 'id = ?',
        whereArgs: [customer.id],
      );
      final int currentDbBalance = custRows.isNotEmpty
          ? (custRows.first['current_balance_paise'] as int? ?? 0)
          : customer.currentBalancePaise;

      // Sacred financial rule: No clamping! Negative balance represents Jama (Advance)
      final int newBalancePaise = isUdhar
          ? currentDbBalance + amountPaise
          : currentDbBalance - amountPaise;

      await txn.rawUpdate('''
        UPDATE customers
        SET current_balance_paise = ?
        WHERE id = ?
      ''', [newBalancePaise, customer.id]);

      // When Jama (payment received) is recorded, FIFO auto-settle the customer's unpaid credit bills
      if (!isUdhar && amountPaise > 0) {
        final pendingSales = await txn.query(
          'sales',
          where: "(customer_id = ? OR (customer_phone IS NOT NULL AND customer_phone != '' AND customer_phone = ?)) AND payment_method = 'credit' AND status != 'settled'",
          whereArgs: [customer.id, customer.phone],
          orderBy: 'created_at ASC',
        );

        int remainingJamaPaise = amountPaise;
        for (final row in pendingSales) {
          final saleId = row['id'] as String;
          final totalPaise = (row['total_amount_paise'] as int?) ?? 0;
          if (remainingJamaPaise >= totalPaise) {
            await txn.update(
              'sales',
              {'status': 'settled', 'sync_status': 'pending'},
              where: 'id = ?',
              whereArgs: [saleId],
            );
            remainingJamaPaise -= totalPaise;
          } else {
            // Partial payment: bill remains pending until fully covered or selectively settled
            break;
          }
        }
      }

      final ledgerEntry = LedgerTransactionModel(
        id: _uuid.v4(),
        businessId: customer.businessId,
        customerId: customer.id,
        type: type,
        amountPaise: amountPaise,
        balanceAfterPaise: newBalancePaise,
        description: description,
        referenceId: referenceId,
        createdAt: DateTime.now(),
        syncStatus: 'pending',
      );
      await txn.insert('ledger_transactions', ledgerEntry.toMap());
    });

    AppDataBus.instance.bumpCustomers();
    AppDataBus.instance.bumpSales();
    AppDataBus.instance.bumpCash();
  }

  Future<void> settleCustomerSaleBill({
    required String saleId,
    required CustomerModel customer,
    required int amountPaise,
    required String paymentMode,
  }) async {
    final db = await instance.database;

    await db.transaction((txn) async {
      final custRows = await txn.query(
        'customers',
        columns: ['current_balance_paise'],
        where: 'id = ?',
        whereArgs: [customer.id],
      );
      final int currentDbBalance = custRows.isNotEmpty
          ? (custRows.first['current_balance_paise'] as int? ?? 0)
          : customer.currentBalancePaise;

      final int newBalancePaise = currentDbBalance - amountPaise;

      await txn.update(
        'sales',
        {'status': 'settled', 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: [saleId],
      );

      await txn.rawUpdate('''
        UPDATE customers
        SET current_balance_paise = ?
        WHERE id = ?
      ''', [newBalancePaise, customer.id]);

      final ledgerEntry = LedgerTransactionModel(
        id: _uuid.v4(),
        businessId: customer.businessId,
        customerId: customer.id,
        type: 'debit',
        amountPaise: amountPaise,
        balanceAfterPaise: newBalancePaise,
        description: 'Bill Settlement ($paymentMode)',
        referenceId: saleId,
        createdAt: DateTime.now(),
        syncStatus: 'pending',
      );
      await txn.insert('ledger_transactions', ledgerEntry.toMap());
    });

    // Sale status changed, customer balance changed, and cash may have come in.
    AppDataBus.instance.bumpSales();
    AppDataBus.instance.bumpCustomers();
    AppDataBus.instance.bumpCash();
  }

  Future<void> settleMultipleCustomerSaleBills({
    required List<String> saleIds,
    required CustomerModel customer,
    required int totalAmountPaise,
    required String paymentMode,
  }) async {
    final db = await instance.database;

    await db.transaction((txn) async {
      final custRows = await txn.query(
        'customers',
        columns: ['current_balance_paise'],
        where: 'id = ?',
        whereArgs: [customer.id],
      );
      final int currentDbBalance = custRows.isNotEmpty
          ? (custRows.first['current_balance_paise'] as int? ?? 0)
          : customer.currentBalancePaise;

      final int newBalancePaise = currentDbBalance - totalAmountPaise;

      for (final saleId in saleIds) {
        await txn.update(
          'sales',
          {'status': 'settled', 'sync_status': 'pending'},
          where: 'id = ?',
          whereArgs: [saleId],
        );
      }

      await txn.rawUpdate('''
        UPDATE customers
        SET current_balance_paise = ?
        WHERE id = ?
      ''', [newBalancePaise, customer.id]);

      final ledgerEntry = LedgerTransactionModel(
        id: _uuid.v4(),
        businessId: customer.businessId,
        customerId: customer.id,
        type: 'debit',
        amountPaise: totalAmountPaise,
        balanceAfterPaise: newBalancePaise,
        description: 'Selective Settle (${saleIds.length} Bills • $paymentMode)',
        referenceId: saleIds.join(','),
        createdAt: DateTime.now(),
        syncStatus: 'pending',
      );
      await txn.insert('ledger_transactions', ledgerEntry.toMap());
    });

    AppDataBus.instance.bumpSales();
    AppDataBus.instance.bumpCustomers();
    AppDataBus.instance.bumpCash();
  }

  Future<void> markSaleSynced(String saleId) async {
    final db = await instance.database;
    await db.update('sales', {'sync_status': 'synced'}, where: 'id = ?', whereArgs: [saleId]);
  }

  Future<List<SaleModel>> getPendingSales({int limit = 50}) async {
    final db = await instance.database;
    final result = await db.query(
      'sales',
      where: 'sync_status = ?',
      whereArgs: ['pending'],
      limit: limit,
    );
    return result.map((m) => SaleModel.fromMap(m)).toList();
  }

  Future<void> addExpense(ExpenseModel expense) async {
    final db = await instance.database;
    await db.insert('expenses', expense.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    AppDataBus.instance.bumpCash();
  }

  Future<List<ExpenseModel>> getAllExpenses() async {
    final db = await instance.database;
    final result = await db.query('expenses', orderBy: 'created_at DESC');
    // Deliberately no demo-expense seeding here. This used to insert two
    // fabricated expense rows into every real merchant's Cash Register the
    // first time the expenses table was empty — indistinguishable from a
    // real entry. An empty result means no expenses have been logged yet.
    return result.map((m) => ExpenseModel.fromMap(m)).toList();
  }


  Future<void> deleteExpense(String id) async {
    final db = await instance.database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
    AppDataBus.instance.bumpCash();
  }

  Future<void> _ensureStoreProfileTable(Database db) async {
    try {
      await db.execute('ALTER TABLE store_profile ADD COLUMN business_type TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE store_profile ADD COLUMN is_pro INTEGER DEFAULT 0');
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE store_profile ADD COLUMN pro_plan TEXT DEFAULT 'free'");
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE store_profile ADD COLUMN pro_expiry TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE store_profile ADD COLUMN razorpay_payment_id TEXT');
    } catch (_) {}
    await db.execute('''
      CREATE TABLE IF NOT EXISTS store_profile (
        id TEXT PRIMARY KEY,
        store_name TEXT,
        tagline TEXT,
        owner_name TEXT,
        phone TEXT,
        email TEXT,
        upi_vpa TEXT,
        category TEXT,
        business_type TEXT,
        address TEXT,
        pincode TEXT,
        gstin TEXT,
        fssai TEXT,
        logo_url TEXT,
        upi_accounts_json TEXT,
        is_pro INTEGER DEFAULT 0,
        pro_plan TEXT DEFAULT 'free',
        pro_expiry TEXT,
        razorpay_payment_id TEXT,
        trial_started_at TEXT
      )
    ''');
    try {
      await db.execute('ALTER TABLE store_profile ADD COLUMN trial_started_at TEXT');
    } catch (_) {}
  }

  Future<StoreProfileModel> getStoreProfile() async {
    final db = await instance.database;
    await _ensureStoreProfileTable(db);
    try {
      final result = await db.query('store_profile', where: 'id = ?', whereArgs: ['default_store']);
      if (result.isNotEmpty) {
        return StoreProfileModel.fromMap(result.first);
      }
    } catch (_) {}
    return StoreProfileModel();
  }

  /// Checks whether the active database has a user-configured store profile
  Future<bool> hasConfiguredStoreProfile() async {
    final profile = await getStoreProfile();
    return profile.isConfigured;
  }

  Future<void> saveStoreProfile(StoreProfileModel profile) async {
    final db = await instance.database;
    await _ensureStoreProfileTable(db);
    final map = profile.toMap();
    map['id'] = 'default_store';

    // Preserve existing business_type and trial_started_at if incoming is blank
    final existing = await db.query('store_profile', where: 'id = ?', whereArgs: ['default_store'], limit: 1);
    if (existing.isNotEmpty) {
      if ((map['business_type'] as String?)?.trim().isEmpty ?? true) {
        final existingType = existing.first['business_type'] as String?;
        if (existingType != null && existingType.trim().isNotEmpty) {
          map['business_type'] = existingType;
        }
      }
      if ((map['trial_started_at'] as String?)?.trim().isEmpty ?? true) {
        final existingTrial = existing.first['trial_started_at'] as String?;
        if (existingTrial != null && existingTrial.trim().isNotEmpty) {
          map['trial_started_at'] = existingTrial;
        }
      }
    }

    await db.insert('store_profile', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> activateProMembership({
    required String plan,
    required String paymentId,
    required DateTime expiryDate,
  }) async {
    final current = await getStoreProfile();
    final updated = StoreProfileModel(
      storeName: current.storeName,
      tagline: current.tagline,
      ownerName: current.ownerName,
      phone: current.phone,
      email: current.email,
      upiVpa: current.upiVpa,
      category: current.category,
      businessType: current.businessType,
      address: current.address,
      pincode: current.pincode,
      gstin: current.gstin,
      fssai: current.fssai,
      logoUrl: current.logoUrl,
      upiAccountsJson: current.upiAccountsJson,
      isPro: true,
      proPlan: plan,
      proExpiry: expiryDate.toIso8601String(),
      razorpayPaymentId: paymentId,
      trialStartedAt: current.trialStartedAt,
    );
    await saveStoreProfile(updated);
  }

  /// Grants a 7-day free Pro trial if the store has never had any Pro plan or trial before.
  /// Strictly non-repeatable: Once initiated, trial_started_at is permanently locked and cannot restart.
  Future<StoreProfileModel> ensureFreeTrialGranted() async {
    final current = await getStoreProfile();
    final prefs = await SharedPreferences.getInstance();

    // 1. Check if trial was already initiated previously
    String? existingTrialStart = current.trialStartedAt.trim().isNotEmpty ? current.trialStartedAt.trim() : null;
    existingTrialStart ??= prefs.getString('pro_trial_started_at')?.trim();

    if (existingTrialStart != null && existingTrialStart.isNotEmpty) {
      final startDate = DateTime.tryParse(existingTrialStart);
      if (startDate != null) {
        final expiry = startDate.add(const Duration(days: 7));
        final isStillValid = DateTime.now().isBefore(expiry);

        if (isStillValid) {
          if (!current.isPro || current.proPlan != 'trial') {
            final updated = StoreProfileModel(
              storeName: current.storeName,
              tagline: current.tagline,
              ownerName: current.ownerName,
              phone: current.phone,
              email: current.email,
              upiVpa: current.upiVpa,
              category: current.category,
              businessType: current.businessType,
              address: current.address,
              pincode: current.pincode,
              gstin: current.gstin,
              fssai: current.fssai,
              logoUrl: current.logoUrl,
              upiAccountsJson: current.upiAccountsJson,
              isPro: true,
              proPlan: 'trial',
              proExpiry: expiry.toIso8601String(),
              razorpayPaymentId: 'free_trial_7d',
              trialStartedAt: existingTrialStart,
            );
            await saveStoreProfile(updated);
            await prefs.setBool('is_pro', true);
            return updated;
          }
          return current;
        } else {
          // Trial has strictly expired! Do not renew!
          if (current.isPro && (current.proPlan == 'trial' || current.razorpayPaymentId == 'free_trial_7d')) {
            await deactivateProMembership();
            await prefs.setBool('is_pro', false);
          }
          return current;
        }
      }
    }

    // 2. If user already purchased a paid plan (monthly / annual), do not override
    if (current.isProEffective && current.proPlan != 'trial' && current.proPlan != 'free') {
      return current;
    }

    // 3. Check if device or account already used trial
    final alreadyUsed = prefs.getBool('pro_trial_already_consumed') ?? false;
    if (alreadyUsed) {
      return current;
    }

    // 4. First-time initiation: Lock trial_started_at permanently!
    final now = DateTime.now();
    final expiry = now.add(const Duration(days: 7));
    final startStr = now.toIso8601String();

    await prefs.setString('pro_trial_started_at', startStr);
    await prefs.setBool('pro_trial_already_consumed', true);
    await prefs.setBool('is_pro', true);

    final updated = StoreProfileModel(
      storeName: current.storeName,
      tagline: current.tagline,
      ownerName: current.ownerName,
      phone: current.phone,
      email: current.email,
      upiVpa: current.upiVpa,
      category: current.category,
      businessType: current.businessType,
      address: current.address,
      pincode: current.pincode,
      gstin: current.gstin,
      fssai: current.fssai,
      logoUrl: current.logoUrl,
      upiAccountsJson: current.upiAccountsJson,
      isPro: true,
      proPlan: 'trial',
      proExpiry: expiry.toIso8601String(),
      razorpayPaymentId: 'free_trial_7d',
      trialStartedAt: startStr,
    );
    await saveStoreProfile(updated);
    return updated;
  }

  Future<void> deactivateProMembership() async {
    final current = await getStoreProfile();
    final updated = StoreProfileModel(
      storeName: current.storeName,
      tagline: current.tagline,
      ownerName: current.ownerName,
      phone: current.phone,
      email: current.email,
      upiVpa: current.upiVpa,
      category: current.category,
      businessType: current.businessType,
      address: current.address,
      pincode: current.pincode,
      gstin: current.gstin,
      fssai: current.fssai,
      logoUrl: current.logoUrl,
      upiAccountsJson: current.upiAccountsJson,
      isPro: false,
      proPlan: '',
      proExpiry: '',
      razorpayPaymentId: '',
    );
    await saveStoreProfile(updated);
  }

  // ==========================================
  // INVENTORY MOVEMENTS AUDIT TRAIL
  // ==========================================
  Future<void> recordInventoryMovement(InventoryMovementModel movement) async {
    final db = await instance.database;
    await db.insert('inventory_movements', movement.toMap());
    // The Inventory screen's audit trail reads this table.
    AppDataBus.instance.bumpProducts();
  }

  Future<List<InventoryMovementModel>> getAllInventoryMovements({int limit = 100}) async {
    final db = await instance.database;
    final result = await db.query(
      'inventory_movements',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return result.map((m) => InventoryMovementModel.fromMap(m)).toList();
  }

  // ==========================================
  // SUPPLIERS MASTER
  // ==========================================
  Future<List<SupplierModel>> getAllSuppliers() async {
    final db = await instance.database;
    final result = await db.query('suppliers', orderBy: 'name ASC');
    // Deliberately no demo-supplier seeding here. This used to insert three
    // fabricated wholesalers with fake outstanding balances (₹18,600 /
    // ₹3,400 owed) into every real merchant's Purchases & Restock screen on
    // first open — indistinguishable from genuine data. An empty result
    // means the store genuinely has no suppliers yet.
    return result.map((m) => SupplierModel.fromMap(m)).toList();
  }

  Future<void> upsertSupplier(SupplierModel supplier) async {
    final db = await instance.database;
    await db.insert('suppliers', supplier.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ==========================================================================
  // PURCHASE / RESTOCK ORDERS
  //
  // The Purchases screen had no persistence at all before this: orders lived in
  // widget state and were gone on dispose, and "Mark Inward Received" never
  // touched a product row despite saying "Received into Stock!". These give it
  // a real table; receiving an order routes its lines through
  // InventoryInwardService, the same path AI bill scan uses.
  // ==========================================================================

  Future<List<PurchaseOrderModel>> getAllPurchaseOrders({int limit = 200}) async {
    final db = await instance.database;
    final rows = await db.query(
      'purchase_orders',
      orderBy: 'order_date DESC',
      limit: limit,
    );
    return rows.map((r) => PurchaseOrderModel.fromMap(r)).toList();
  }

  Future<PurchaseOrderModel?> getPurchaseOrderById(String id) async {
    final db = await instance.database;
    final rows = await db.query('purchase_orders',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return PurchaseOrderModel.fromMap(rows.first);
  }

  Future<void> upsertPurchaseOrder(PurchaseOrderModel order) async {
    final db = await instance.database;
    await db.insert(
      'purchase_orders',
      order.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    AppDataBus.instance.bumpProducts();
  }

  Future<void> deletePurchaseOrder(String id) async {
    final db = await instance.database;
    await db.delete('purchase_orders', where: 'id = ?', whereArgs: [id]);
    AppDataBus.instance.bumpProducts();
  }

  /// Next purchase order number, allocated from the shared app_counters table
  /// the same way getNextInvoiceSequence allocates invoice numbers.
  ///
  /// Replaces the screen's old `'PO-${1085 + _purchases.length}'`, which reused
  /// an id as soon as any order was deleted — delete one, add one, and the new
  /// order silently overwrote an existing row.
  Future<String> getNextPurchaseOrderNumber() async {
    final db = await instance.database;
    final next = await db.transaction((txn) async {
      final row = await txn.query('app_counters',
          where: 'key = ?', whereArgs: ['purchase_order_sequence'], limit: 1);
      int nextVal;
      if (row.isEmpty) {
        final countRes =
            await txn.rawQuery('SELECT COUNT(*) as count FROM purchase_orders');
        nextVal = (Sqflite.firstIntValue(countRes) ?? 0) + 1086;
        await txn.insert('app_counters',
            {'key': 'purchase_order_sequence', 'last_val': nextVal});
      } else {
        nextVal = ((row.first['last_val'] as num?)?.toInt() ?? 1085) + 1;
        await txn.update('app_counters', {'last_val': nextVal},
            where: 'key = ?', whereArgs: ['purchase_order_sequence']);
      }
      return nextVal;
    });
    return 'PO-$next';
  }

  Future<void> deleteSupplier(String id) async {
    final db = await instance.database;
    await db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
  }

  // ==========================================
  // CASH REGISTER SHIFTS
  // ==========================================
  Future<void> saveCashRegisterShift(CashRegisterShiftModel shift) async {
    final db = await instance.database;
    await db.insert('cash_register_shifts', shift.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    AppDataBus.instance.bumpCash();
  }

  Future<CashRegisterShiftModel?> getLatestCashRegisterShift() async {
    final db = await instance.database;
    final result = await db.query('cash_register_shifts', orderBy: 'opened_at DESC', limit: 1);
    if (result.isNotEmpty) {
      return CashRegisterShiftModel.fromMap(result.first);
    }
    return null;
  }

  Future<List<CashRegisterShiftModel>> getAllCashRegisterShifts({
    DateTime? from,
    DateTime? to,
    int limit = 50,
  }) async {
    final db = await instance.database;
    String? where;
    List<dynamic>? whereArgs;

    if (from != null && to != null) {
      where = 'opened_at >= ? AND opened_at <= ?';
      whereArgs = [from.toIso8601String(), to.toIso8601String()];
    } else if (from != null) {
      where = 'opened_at >= ?';
      whereArgs = [from.toIso8601String()];
    }

    final result = await db.query(
      'cash_register_shifts',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'opened_at DESC',
      limit: limit,
    );
    return result.map((m) => CashRegisterShiftModel.fromMap(m)).toList();
  }

  // ==========================================
  // DATA RESET & FACTORY WIPE (START FRESH)
  // ==========================================

  /// 1. Clears all sales history, bills, and resets daily counter
  Future<void> clearSalesHistory() async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('sales');
    });
  }

  /// 2. Clears all products, categories, and stock audit ledger
  Future<void> clearProductsAndInventory() async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('products');
      await txn.delete('categories');
      await txn.delete('inventory_movements');
    });
  }

  /// 3. Clears all customers and Khata ledger transactions
  Future<void> clearKhataAndCustomers() async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('customers');
      await txn.delete('ledger_transactions');
    });
  }

  /// 4. Complete Factory Reset: Wipes all operational retail data cleanly
  Future<void> completeFactoryReset({bool resetStoreProfile = false}) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('sales');
      await txn.delete('products');
      await txn.delete('categories');
      await txn.delete('inventory_movements');
      await txn.delete('customers');
      await txn.delete('ledger_transactions');
      await txn.delete('expenses');
      await txn.delete('cash_register_shifts');
      await txn.delete('suppliers');
      try {
        await txn.delete('product_batches');
        await txn.delete('audit_logs');
      } catch (_) {}
      if (resetStoreProfile) {
        await txn.delete('store_profile');
      }
    });

    // Reset Cash Drawer float to ₹0.00
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('cash_register_opening_float_paise', 0);
    } catch (_) {}

    // Instantly notify all active tabs (Products, POS, Khata, Cash Register) to refresh
    AppDataBus.instance.bumpAll();
  }

  /// Automatically re-links orphan variants to their master parent product
  Future<void> repairVariantRelationships() async {
    final db = await database;
    try {
      final parents = await db.query('products', where: 'has_variants = 1');
      for (final p in parents) {
        final pId = p['id'] as String;
        final pName = p['name'] as String;
        await db.rawUpdate('''
          UPDATE products
          SET parent_id = ?
          WHERE (parent_id IS NULL OR parent_id = '')
            AND name LIKE ?
            AND id != ?
        ''', [pId, '$pName (%', pId]);
      }
    } catch (_) {}
  }

  // --- DOCTOR MANAGEMENT (Pharmacy Vertical) ---
  Future<List<DoctorModel>> getDoctors() async {
    final db = await instance.database;
    final result = await db.query('doctors', orderBy: 'name ASC');
    return result.map((json) => DoctorModel.fromMap(json)).toList();
  }

  Future<void> upsertDoctor(DoctorModel doctor) async {
    final db = await instance.database;
    await db.insert('doctors', doctor.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteDoctor(String id) async {
    final db = await instance.database;
    await db.delete('doctors', where: 'id = ?', whereArgs: [id]);
  }

  // --- SECURITY & AUDIT LOGS ---
  /// Logs a critical security / store action (e.g. Sales Return, Stock Delta, Bill Deletion)
  Future<void> logAuditAction({
    required String action,
    required String details,
    int amountPaise = 0,
    String? userPin,
  }) async {
    try {
      final db = await instance.database;
      final profile = await getStoreProfile();
      await db.insert('audit_logs', {
        'id': _uuid.v4(),
        'business_id': profile.phone.isNotEmpty ? profile.phone : 'default_biz',
        'action': action,
        'details': details,
        'amount_paise': amountPaise,
        'user_pin': userPin ?? '',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  /// Retrieves recent audit logs
  Future<List<Map<String, dynamic>>> getAuditLogs({int limit = 100}) async {
    try {
      final db = await instance.database;
      return await db.query(
        'audit_logs',
        orderBy: 'created_at DESC',
        limit: limit,
      );
    } catch (_) {
      return [];
    }
  }
}

/// Before/after stock for a single [LocalDatabase.applyStockDelta] call, so an
/// inward caller can write an accurate InventoryMovementModel audit row without
/// re-reading the product.
///
/// [found] is false when the product id no longer exists — for example it was
/// deleted on another device and the cloud listener removed it locally while an
/// inward sheet was still open. Callers skip the line rather than resurrecting a
/// deleted product.
class StockDeltaResult {
  final double previousStock;
  final double newStock;
  final bool found;

  const StockDeltaResult({
    required this.previousStock,
    required this.newStock,
    this.found = true,
  });

  /// Quantity actually applied. Zero for an "unlimited" (>= 99999) product,
  /// whose sentinel is intentionally left alone.
  double get appliedDelta => newStock - previousStock;
}

class VariantCustomData {
  final String label;
  final int sellingPricePaise;
  final int mrpPaise;
  final int purchasePricePaise;
  final double stockQuantity;
  final String? barcode;

  const VariantCustomData({
    required this.label,
    required this.sellingPricePaise,
    required this.mrpPaise,
    required this.purchasePricePaise,
    required this.stockQuantity,
    this.barcode,
  });
}


