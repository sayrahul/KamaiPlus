import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
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
    _database = await _initDB(_activeDbName);
    return _database!;
  }

  /// Switch the active SQLite database to a user-scoped database file.
  /// Each user/email gets their own isolated local database: `kamaiplus_<safeId>.db`.
  /// This ensures multi-account isolation (e.g. User A has Store 1, User B has Store 2).
  Future<void> switchUser(String? userId) async {
    String targetDb;
    if (userId != null && userId.trim().isNotEmpty) {
      final safeId = userId.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      targetDb = 'kamaiplus_$safeId.db';
    } else {
      targetDb = 'kamaiplus_local.db';
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

  /// Closes database connection on sign-out
  Future<void> closeDatabase() async {
    if (_database != null) {
      try {
        await _database!.close();
      } catch (_) {}
      _database = null;
    }
    _activeDbName = 'kamaiplus_local.db';
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateToV2(db);
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
      await db.execute('ALTER TABLE products ADD COLUMN business_type TEXT DEFAULT "grocery"');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE categories ADD COLUMN business_type TEXT DEFAULT "grocery"');
    } catch (_) {}
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

    await _seedMasterCatalogIfEmpty(db);
    await _backfillBusinessVerticals(db);
  }

  /// Automatic vertical isolation: classifies unassigned categories & products
  /// into their correct business verticals so pharmacy/clothing/hardware items NEVER mix into grocery.
  Future<void> _backfillBusinessVerticals(Database db) async {
    try {
      // 1. Classify categories
      await db.execute('''
        UPDATE categories SET business_type = 'pharmacy' 
        WHERE id LIKE '%pharma%' OR id LIKE '%med%' 
           OR name LIKE '%Pharma%' OR name LIKE '%Medicine%' 
           OR name LIKE '%Tablets%' OR name LIKE '%Syrup%' 
           OR name LIKE '%First Aid%' OR name LIKE '%Ayurvedic%' 
           OR name LIKE '%Ointment%' OR name LIKE '%Generic%';
      ''');
      await db.execute('''
        UPDATE categories SET business_type = 'clothing' 
        WHERE id LIKE '%cloth%' OR name LIKE '%Men%' OR name LIKE '%Women%' 
           OR name LIKE '%Kids%' OR name LIKE '%Wear%' OR name LIKE '%Apparel%'
           OR name LIKE '%Saree%' OR name LIKE '%Shirt%' OR name LIKE '%Jeans%';
      ''');
      await db.execute('''
        UPDATE categories SET business_type = 'hardware' 
        WHERE id LIKE '%hard%' OR name LIKE '%Paint%' OR name LIKE '%Tool%' 
           OR name LIKE '%Plumbing%' OR name LIKE '%Electrical%' OR name LIKE '%Pipe%'
           OR name LIKE '%Sanitary%';
      ''');
      await db.execute('''
        UPDATE categories SET business_type = 'restaurant' 
        WHERE id LIKE '%rest%' OR name LIKE '%Starter%' OR name LIKE '%Beverage%' 
           OR name LIKE '%Main Course%' OR name LIKE '%Curry%' OR name LIKE '%Roti%'
           OR name LIKE '%Dessert%';
      ''');
      await db.execute('''
        UPDATE categories SET business_type = 'grocery' 
        WHERE business_type IS NULL OR business_type = '';
      ''');

      // 2. Sync products with their category's business_type
      await db.execute('''
        UPDATE products SET business_type = (
          SELECT categories.business_type FROM categories WHERE categories.id = products.category_id
        )
        WHERE category_id IS NOT NULL AND (
          SELECT categories.business_type FROM categories WHERE categories.id = products.category_id
        ) IS NOT NULL;
      ''');

      // 3. Keyword-based strict classification for products (prevents cross-vertical mixing)
      await db.execute('''
        UPDATE products SET business_type = 'pharmacy'
        WHERE (
          name LIKE '%Dolo%' OR name LIKE '%Paracetamol%' OR name LIKE '%Cetirizine%' 
          OR name LIKE '%Azithromycin%' OR name LIKE '%Pantoprazole%' OR name LIKE '%Syrup%' 
          OR name LIKE '%Tablet%' OR name LIKE '%Capsule%' OR name LIKE '%Ointment%' 
          OR name LIKE '%Vicks%' OR name LIKE '%Moov%' OR name LIKE '%Volini%' 
          OR name LIKE '%Band-Aid%' OR name LIKE '%Crocin%' OR name LIKE '%Combiflam%' 
          OR name LIKE '%Digene%' OR name LIKE '%Betadine%' OR name LIKE '%Strepsils%' 
          OR name LIKE '%Disprin%' OR name LIKE '%Eno%' OR name LIKE '%Benadryl%'
          OR name LIKE '%Ascoril%' OR name LIKE '%Inhaler%'
        );
      ''');

      await db.execute('''
        UPDATE products SET business_type = 'clothing'
        WHERE (
          name LIKE '%Shirt%' OR name LIKE '%T-Shirt%' OR name LIKE '%Jeans%' 
          OR name LIKE '%Saree%' OR name LIKE '%Kurti%' OR name LIKE '%Trouser%'
          OR name LIKE '%Suit%' OR name LIKE '%Dress%' OR name LIKE '%Legging%'
          OR name LIKE '%Shoes%' OR name LIKE '%Sandals%' OR name LIKE '%Innerwear%'
          OR name LIKE '%Dupatta%'
        );
      ''');

      await db.execute('''
        UPDATE products SET business_type = 'hardware'
        WHERE (
          name LIKE '%PVC Pipe%' OR name LIKE '%Hammer%' OR name LIKE '%Apex Emulsion%' 
          OR name LIKE '%Wire%' OR name LIKE '%Switch%' OR name LIKE '%MCB%'
          OR name LIKE '%Cement%' OR name LIKE '%Screwdriver%' OR name LIKE '%Nut Bolt%'
          OR name LIKE '%Washbasin%' OR name LIKE '%LED Bulb%' OR name LIKE '%LED Batten%'
        );
      ''');

      await db.execute('''
        UPDATE products SET business_type = 'restaurant'
        WHERE (
          name LIKE '%Masala Chai%' OR name LIKE '%Cold Coffee%' OR name LIKE '%Samosa%' 
          OR name LIKE '%Spring Roll%' OR name LIKE '%Paneer Butter%' OR name LIKE '%Dal Makhani%'
          OR name LIKE '%Butter Naan%' OR name LIKE '%Jeera Rice%' OR name LIKE '%Burger%'
          OR name LIKE '%Gulab Jamun%' OR name LIKE '%Kulfi%'
        );
      ''');

      // 3b. Crossover health & hygiene items sold in BOTH Grocery & Pharmacy
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

      // 4. Default any remaining to grocery
      await db.execute('''
        UPDATE products SET business_type = 'grocery' WHERE business_type IS NULL OR business_type = '';
      ''');
    } catch (_) {}
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
        business_type TEXT DEFAULT 'grocery'
      )
    ''');


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
      // Nothing tagged for this vertical yet — seed its starter catalog (only inserts
      // rows tagged with this exact businessType) and re-check.
      await seedVerticalStarterData(businessType);
      final seeded = await db.query(
        'products',
        where: "business_type = ? OR business_type = 'both'",
        whereArgs: [businessType],
        orderBy: 'is_favorite DESC, name ASC',
      );
      if (seeded.isNotEmpty) {
        return seeded.map((json) => ProductModel.fromMap(json)).toList();
      }
      // Still nothing (a custom vertical with no starter catalog, e.g.). Fall back
      // ONLY to genuinely unclassified rows (pre-dating the vertical feature) —
      // never to another vertical's tagged products. This is the fix for products
      // from one store type (e.g. Apparel) leaking into a different one (e.g.
      // Electronics) whenever the active vertical had few or zero matches.
      final unclassified = await db.query(
        'products',
        where: "business_type IS NULL OR business_type = ''",
        orderBy: 'is_favorite DESC, name ASC',
      );
      return unclassified.map((json) => ProductModel.fromMap(json)).toList();
    }
    final allResult = await db.query('products', orderBy: 'is_favorite DESC, name ASC');
    if (allResult.isEmpty) {
      final profile = await getStoreProfile();
      final type = profile.businessType.isNotEmpty ? profile.businessType : 'grocery';
      await seedVerticalStarterData(type);
      final seeded = await db.query('products', orderBy: 'is_favorite DESC, name ASC');
      return seeded.map((json) => ProductModel.fromMap(json)).toList();
    }
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

  Future<ProductModel?> findProductByBarcode(String barcode) async {
    final db = await instance.database;
    final result = await db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [barcode.trim()],
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
    var result = await db.query(
      'master_catalog',
      where: whereClause,
      whereArgs: whereArgs,
      limit: 1,
    );
    if (result.isNotEmpty) {
      return MasterProductModel.fromMap(result.first);
    }
    // Fallback: lookup by exact barcode regardless of vertical
    if (businessType != null && businessType.isNotEmpty) {
      result = await db.query(
        'master_catalog',
        where: 'barcode = ?',
        whereArgs: [cleanBarcode],
        limit: 1,
      );
      if (result.isNotEmpty) {
        return MasterProductModel.fromMap(result.first);
      }
    }
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
    final existing = await findProductByBarcode(masterItem.barcode);
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

    final effectiveVertical = masterItem.businessType == 'both'
        ? 'both'
        : ((targetVertical != null && targetVertical.isNotEmpty)
            ? targetVertical
            : masterItem.businessType);

    String? categoryId;
    if (masterItem.category.isNotEmpty && masterItem.category.toLowerCase() != 'general') {
      final db = await instance.database;
      final existingCat = await db.query(
        'categories',
        where: 'LOWER(TRIM(name)) = ?',
        whereArgs: [masterItem.category.trim().toLowerCase()],
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
        final newBalancePaise = customer.currentBalancePaise + creditDue;

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
    String reason = 'Customer Return',
  }) async {
    final db = await instance.database;

    await db.transaction((txn) async {
      // 1. Mark sale status as 'refunded'
      await txn.update(
        'sales',
        {
          'status': 'refunded',
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

          final movement = InventoryMovementModel(
            id: _uuid.v4(),
            businessId: sale.businessId,
            productId: targetProdId,
            productName: prodName,
            movementType: 'RETURN',
            quantity: qty,
            previousStock: currentStock,
            newStock: newStock,
            referenceId: sale.id,
            createdAt: DateTime.now(),
          );
          await txn.insert('inventory_movements', movement.toMap());
        }
      }

      // 3. If credit or split-credit was used, reverse customer udhar balance & record ledger entry
      final creditDue = sale.paymentMethod == 'credit'
          ? sale.totalAmountPaise
          : (sale.paymentMethod == 'split' ? sale.splitCreditPaise : 0);

      if (creditDue > 0 && sale.customerId != null && sale.customerId!.isNotEmpty) {
        final custRows = await txn.query('customers', where: 'id = ?', whereArgs: [sale.customerId]);
        if (custRows.isNotEmpty) {
          final currentBal = custRows.first['current_balance_paise'] as int;
          final newBal = (currentBal - creditDue).clamp(0, 999999999999);

          await txn.rawUpdate('''
            UPDATE customers
            SET current_balance_paise = ?
            WHERE id = ?
          ''', [newBal, sale.customerId]);

          final ledgerEntry = LedgerTransactionModel(
            id: _uuid.v4(),
            businessId: sale.businessId,
            customerId: sale.customerId!,
            type: 'debit', // Reversing credit debt
            amountPaise: creditDue,
            balanceAfterPaise: newBal,
            description: 'Sales Return / Refund #${sale.invoiceNumber}',
            referenceId: sale.id,
            createdAt: DateTime.now(),
            syncStatus: 'pending',
          );
          await txn.insert('ledger_transactions', ledgerEntry.toMap());
        }
      }

      // 4. If cash or split-cash was paid, record cash drawer refund outflow entry
      final cashToRefund = sale.paymentMethod == 'cash'
          ? sale.totalAmountPaise
          : (sale.paymentMethod == 'split' ? sale.splitCashPaise : 0);

      if (cashToRefund > 0) {
        final refundExpense = ExpenseModel(
          id: _uuid.v4(),
          businessId: sale.businessId,
          title: 'Cash Refund: #${sale.invoiceNumber}',
          amountPaise: cashToRefund,
          category: 'Refund',
          createdAt: DateTime.now(),
          note: reason,
        );
        await txn.insert('expenses', refundExpense.toMap());
      }
    });

    // A return can touch all four: sale status, restocked items, udhar reversal, cash out.
    AppDataBus.instance.bumpSaleCompleted(affectsCustomer: true, affectsCash: true);
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

  Future<List<SaleModel>> getAllSales({int limit = 100}) async {
    final db = await instance.database;
    final result = await db.query('sales', orderBy: 'created_at DESC', limit: limit);
    return result.map((json) => SaleModel.fromMap(json)).toList();
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
    final int newBalancePaise = isUdhar
        ? customer.currentBalancePaise + amountPaise
        : (customer.currentBalancePaise - amountPaise).clamp(0, 999999999999);

    await db.transaction((txn) async {
      await txn.rawUpdate('''
        UPDATE customers
        SET current_balance_paise = ?
        WHERE id = ?
      ''', [newBalancePaise, customer.id]);

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
    // A Jama/Udhar entry taken in cash physically changes the drawer.
    AppDataBus.instance.bumpCash();
  }

  Future<void> settleCustomerSaleBill({
    required String saleId,
    required CustomerModel customer,
    required int amountPaise,
    required String paymentMode,
  }) async {
    final db = await instance.database;
    final int newBalancePaise = (customer.currentBalancePaise - amountPaise).clamp(0, 999999999999);

    await db.transaction((txn) async {
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
    final int newBalancePaise = (customer.currentBalancePaise - totalAmountPaise).clamp(0, 999999999999);

    await db.transaction((txn) async {
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
    if (result.isEmpty && _activeDbName == 'kamaiplus_local.db') {
      final now = DateTime.now();
      final demo1 = ExpenseModel(
        id: 'exp_demo_1',
        businessId: 'biz_default_retail',
        title: 'Morning Chai & Snacks for Staff',
        amountPaise: 6000,
        category: 'Tea / Snacks',
        createdAt: now.subtract(const Duration(hours: 3)),
        note: 'Staff tea & biscuits',
      );
      final demo2 = ExpenseModel(
        id: 'exp_demo_2',
        businessId: 'biz_default_retail',
        title: 'Carry Bags & Packaging Tape',
        amountPaise: 12000,
        category: 'Packaging',
        createdAt: now.subtract(const Duration(hours: 1)),
        note: 'Plastic carry bags bundle',
      );
      await addExpense(demo1);
      await addExpense(demo2);
      return [demo2, demo1];
    }
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
        razorpay_payment_id TEXT
      )
    ''');
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
    );
    await saveStoreProfile(updated);
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
    if (result.isEmpty) {
      // Seed default suppliers if empty
      final defaultSuppliers = [
        SupplierModel(
          id: 'sup_1',
          businessId: 'biz_starter_pos',
          name: 'Metro Cash & Carry India',
          phone: '+919820011223',
          category: 'FMCG & Staples Wholesale',
          currentBalancePaise: 0,
        ),
        SupplierModel(
          id: 'sup_2',
          businessId: 'biz_starter_pos',
          name: 'Hindustan Unilever Distributor',
          phone: '+919819922334',
          category: 'Personal & Home Care',
          currentBalancePaise: 1860000,
        ),
        SupplierModel(
          id: 'sup_3',
          businessId: 'biz_starter_pos',
          name: 'Parle & Britannia Agencies',
          phone: '+919867733445',
          category: 'Biscuits & Confectionery',
          currentBalancePaise: 340000,
        ),
      ];
      for (final s in defaultSuppliers) {
        await db.insert('suppliers', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      return defaultSuppliers;
    }
    return result.map((m) => SupplierModel.fromMap(m)).toList();
  }

  Future<void> upsertSupplier(SupplierModel supplier) async {
    final db = await instance.database;
    await db.insert('suppliers', supplier.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
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
      if (resetStoreProfile) {
        await txn.delete('store_profile');
      }
    });
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
