import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../models/models.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();
  static Database? _database;
  static const _uuid = Uuid();

  LocalDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('kamaiplus_local.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
      onOpen: (db) async {
        await _ensureExtraTables(db);
      },
    );
  }

  Future<void> _ensureExtraTables(Database db) async {
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
    try {
      await db.execute('ALTER TABLE customers ADD COLUMN address TEXT');
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
    try {
      await db.execute('ALTER TABLE products ADD COLUMN size_variants_json TEXT DEFAULT \'[]\'');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE sales ADD COLUMN table_number TEXT');
    } catch (_) {}
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        name TEXT NOT NULL
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
        size_variants_json TEXT DEFAULT '[]',
        sync_status TEXT NOT NULL
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
        sync_status TEXT NOT NULL
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
        subtotal_paise INTEGER NOT NULL,
        tax_amount_paise INTEGER NOT NULL,
        discount_paise INTEGER NOT NULL,
        total_amount_paise INTEGER NOT NULL,
        payment_method TEXT NOT NULL,
        split_cash_paise INTEGER DEFAULT 0,
        split_upi_paise INTEGER DEFAULT 0,
        split_credit_paise INTEGER DEFAULT 0,
        table_number TEXT,
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

    // Pre-populate starter retail items & customers
    await _seedStarterData(db);
  }

  Future<void> _seedStarterData(Database db) async {
    const defaultBizId = 'biz_starter_pos';

    // Categories
    final categories = [
      {'id': 'cat_grocery', 'business_id': defaultBizId, 'name': 'Grocery & Staples'},
      {'id': 'cat_dairy', 'business_id': defaultBizId, 'name': 'Dairy & Bakery'},
      {'id': 'cat_snacks', 'business_id': defaultBizId, 'name': 'Snacks & Beverages'},
      {'id': 'cat_personal', 'business_id': defaultBizId, 'name': 'Personal Care'},
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

  /// Replaces the starter catalog with products relevant to the selected store type.
  Future<void> seedCatalogForStoreType({
    required String businessId,
    required String storeType,
  }) async {
    final db = await instance.database;
    final catalog = _catalogForStoreType(storeType);

    await db.transaction((txn) async {
      await txn.delete('products', where: 'business_id = ?', whereArgs: [businessId]);
      await txn.delete('categories', where: 'business_id = ?', whereArgs: [businessId]);

      for (final category in catalog.categories) {
        await txn.insert('categories', {
          'id': '${businessId}_${category.id}',
          'business_id': businessId,
          'name': category.name,
        });
      }

      for (final product in catalog.products) {
        final sizeVariants = storeType == 'Apparel / Clothing'
            ? const ['S', 'M', 'L', 'XL', 'XXL']
            : const <String>[];
        await txn.insert('products', {
          'id': '${businessId}_${product.id}',
          'business_id': businessId,
          'name': product.name,
          'barcode': product.barcode,
          'category_id': '${businessId}_${product.categoryId}',
          'selling_price_paise': product.sellingPricePaise,
          'mrp_paise': product.mrpPaise,
          'purchase_price_paise': product.purchasePricePaise,
          'stock_quantity': product.stockQuantity,
          'tax_rate': product.taxRate,
          'is_tax_inclusive': 1,
          'unit': product.unit,
          'size_variants_json': jsonEncode(sizeVariants),
          'sync_status': 'pending',
        });
      }
    });
  }

  _StarterCatalog _catalogForStoreType(String storeType) {
    switch (storeType) {
      case 'Apparel / Clothing':
        return _StarterCatalog(
          categories: const [
            _StarterCategory('apparel', 'Men & Women Clothing'),
            _StarterCategory('kids', 'Kids Wear'),
            _StarterCategory('footwear', 'Footwear'),
            _StarterCategory('accessories', 'Fashion Accessories'),
          ],
          products: const [
            _StarterProduct('shirt_cotton', 'Men Cotton Casual Shirt', 'apparel', 'pcs', 79900, 99900, 52000, 25, 5),
            _StarterProduct('jeans_regular', 'Men Regular Fit Jeans', 'apparel', 'pcs', 109900, 139900, 72000, 18, 12),
            _StarterProduct('tshirt_basic', 'Unisex Cotton T-Shirt', 'apparel', 'pcs', 39900, 49900, 24000, 40, 5),
            _StarterProduct('kurti_printed', 'Women Printed Daily Kurti', 'apparel', 'pcs', 69900, 89900, 43000, 22, 5),
            _StarterProduct('leggings', 'Women Stretch Leggings', 'apparel', 'pcs', 34900, 44900, 21000, 30, 5),
            _StarterProduct('saree_cotton', 'Cotton Daily Wear Saree', 'apparel', 'pcs', 89900, 119900, 57000, 18, 5),
            _StarterProduct('dress_kids', 'Kids Party Dress', 'kids', 'pcs', 84900, 109900, 54000, 15, 5),
            _StarterProduct('school_shirt', 'Kids School Shirt', 'kids', 'pcs', 44900, 59900, 28000, 20, 5),
            _StarterProduct('school_pant', 'Kids School Pant', 'kids', 'pcs', 49900, 64900, 30000, 20, 5),
            _StarterProduct('sports_shoe', 'Unisex Sports Shoes', 'footwear', 'pair', 99900, 129900, 62000, 18, 18),
            _StarterProduct('slippers', 'Daily Wear Slippers', 'footwear', 'pair', 24900, 29900, 14000, 35, 5),
            _StarterProduct('sandal_women', 'Women Casual Sandals', 'footwear', 'pair', 59900, 79900, 36000, 20, 18),
            _StarterProduct('belt', 'Leather Finish Belt', 'accessories', 'pcs', 29900, 39900, 15000, 25, 18),
            _StarterProduct('wallet', 'Men Wallet', 'accessories', 'pcs', 34900, 49900, 19000, 25, 18),
            _StarterProduct('cap', 'Cotton Adjustable Cap', 'accessories', 'pcs', 19900, 29900, 10000, 30, 5),
          ],
        );
      case 'Electronics & Mobile':
        return _StarterCatalog(
          categories: const [
            _StarterCategory('mobile', 'Mobile Phones'),
            _StarterCategory('accessories', 'Mobile Accessories'),
            _StarterCategory('power', 'Power & Charging'),
            _StarterCategory('audio', 'Audio & Gadgets'),
          ],
          products: const [
            _StarterProduct('phone_entry', 'Android Smartphone 4GB/64GB', 'mobile', 'pcs', 899900, 999900, 820000, 8, 18),
            _StarterProduct('phone_mid', 'Android Smartphone 6GB/128GB', 'mobile', 'pcs', 1499900, 1699900, 1320000, 5, 18),
            _StarterProduct('phone_premium', 'Android Smartphone 8GB/256GB', 'mobile', 'pcs', 2499900, 2799900, 2200000, 3, 18),
            _StarterProduct('case_clear', 'Universal Clear Mobile Cover', 'accessories', 'pcs', 19900, 29900, 8000, 40, 18),
            _StarterProduct('case_premium', 'Premium Shockproof Mobile Cover', 'accessories', 'pcs', 39900, 59900, 18000, 30, 18),
            _StarterProduct('tempered', '9H Tempered Glass Screen Guard', 'accessories', 'pcs', 14900, 29900, 5000, 60, 18),
            _StarterProduct('cable_typec', 'Fast Charging Type-C Cable', 'power', 'pcs', 24900, 39900, 11000, 45, 18),
            _StarterProduct('cable_iphone', 'Lightning Charging Cable', 'power', 'pcs', 39900, 59900, 20000, 30, 18),
            _StarterProduct('charger_20w', '20W Fast Wall Charger', 'power', 'pcs', 79900, 99900, 45000, 25, 18),
            _StarterProduct('charger_65w', '65W GaN Fast Charger', 'power', 'pcs', 179900, 229900, 115000, 12, 18),
            _StarterProduct('powerbank', '10000mAh Power Bank', 'power', 'pcs', 99900, 129900, 68000, 18, 18),
            _StarterProduct('neckband', 'Bluetooth Wireless Neckband', 'audio', 'pcs', 89900, 119900, 56000, 20, 18),
            _StarterProduct('earbuds', 'TWS Wireless Earbuds', 'audio', 'pcs', 129900, 169900, 80000, 15, 18),
            _StarterProduct('speaker', 'Portable Bluetooth Speaker', 'audio', 'pcs', 149900, 199900, 95000, 10, 18),
            _StarterProduct('smartwatch', 'Bluetooth Smart Watch', 'audio', 'pcs', 99900, 149900, 58000, 12, 18),
          ],
        );
      case 'Cafe / Restaurant':
        return _StarterCatalog(
          categories: const [
            _StarterCategory('breakfast', 'Breakfast & Snacks'),
            _StarterCategory('meals', 'Meals & Combos'),
            _StarterCategory('beverages', 'Tea, Coffee & Beverages'),
            _StarterCategory('desserts', 'Desserts & Add-ons'),
          ],
          products: const [
            _StarterProduct('tea', 'Masala Tea', 'beverages', 'cup', 1500, 1500, 500, 999999, 5),
            _StarterProduct('coffee', 'Filter Coffee', 'beverages', 'cup', 3000, 3000, 1000, 999999, 5),
            _StarterProduct('lemonade', 'Fresh Lemonade', 'beverages', 'glass', 4000, 4000, 1500, 999999, 5),
            _StarterProduct('poha', 'Kanda Poha', 'breakfast', 'plate', 5000, 5000, 2200, 999999, 5),
            _StarterProduct('idli', 'Idli Sambar (2 pcs)', 'breakfast', 'plate', 6000, 6000, 2600, 999999, 5),
            _StarterProduct('vada', 'Medu Vada Sambar (2 pcs)', 'breakfast', 'plate', 7000, 7000, 3000, 999999, 5),
            _StarterProduct('sandwich', 'Veg Grilled Sandwich', 'breakfast', 'plate', 9000, 9000, 4000, 999999, 5),
            _StarterProduct('thali', 'Regular Veg Thali', 'meals', 'plate', 14000, 14000, 6500, 999999, 5),
            _StarterProduct('rice_bowl', 'Veg Rice Bowl', 'meals', 'bowl', 12000, 12000, 5500, 999999, 5),
            _StarterProduct('paneer_roll', 'Paneer Tikka Roll', 'meals', 'pcs', 11000, 11000, 5000, 999999, 5),
            _StarterProduct('noodles', 'Veg Hakka Noodles', 'meals', 'plate', 13000, 13000, 6000, 999999, 5),
            _StarterProduct('fries', 'Masala French Fries', 'meals', 'plate', 8000, 8000, 3500, 999999, 5),
            _StarterProduct('samosa', 'Samosa', 'breakfast', 'pcs', 2000, 2000, 800, 999999, 5),
            _StarterProduct('brownie', 'Chocolate Brownie', 'desserts', 'pcs', 7000, 7000, 3000, 999999, 5),
            _StarterProduct('icecream', 'Vanilla Ice Cream Scoop', 'desserts', 'scoop', 5000, 5000, 2200, 999999, 5),
          ],
        );
      case 'Grocery / Kirana':
      default:
        return _StarterCatalog(
          categories: const [
            _StarterCategory('staples', 'Grocery & Staples'),
            _StarterCategory('dairy', 'Dairy & Bakery'),
            _StarterCategory('snacks', 'Snacks & Beverages'),
            _StarterCategory('homecare', 'Personal & Home Care'),
          ],
          products: const [
            _StarterProduct('atta', 'Aashirvaad Shudh Chakki Atta (5kg)', 'staples', 'bag', 24500, 26000, 22000, 40, 0),
            _StarterProduct('rice', 'India Gate Basmati Rice (5kg)', 'staples', 'bag', 49900, 56000, 43000, 25, 5),
            _StarterProduct('oil', 'Fortune Sunflower Oil (1L)', 'staples', 'pouch', 15500, 17000, 14000, 50, 5),
            _StarterProduct('salt', 'Tata Salt (1kg)', 'staples', 'pkt', 2800, 3000, 2400, 100, 0),
            _StarterProduct('sugar', 'Madhur Sugar (1kg)', 'staples', 'pkt', 4800, 5200, 4200, 80, 0),
            _StarterProduct('dal', 'Toor Dal (1kg)', 'staples', 'pkt', 14900, 17500, 12500, 60, 5),
            _StarterProduct('butter', 'Amul Butter (500g)', 'dairy', 'pcs', 27500, 28500, 25000, 25, 12),
            _StarterProduct('milk', 'Amul Taaza Milk (1L)', 'dairy', 'pkt', 6800, 7000, 6000, 60, 0),
            _StarterProduct('bread', 'Modern Sandwich Bread', 'dairy', 'pkt', 4500, 5000, 3600, 35, 0),
            _StarterProduct('biscuits', 'Parle-G Biscuits (800g)', 'snacks', 'pkt', 7500, 8000, 6200, 50, 5),
            _StarterProduct('maggi', 'Maggi Masala Noodles (70g)', 'snacks', 'pcs', 1400, 1400, 1150, 120, 12),
            _StarterProduct('chips', 'Lays Classic Salted Chips', 'snacks', 'pkt', 2000, 2000, 1600, 80, 12),
            _StarterProduct('soap', 'Dettol Bathing Soap (125g)', 'homecare', 'pcs', 6500, 6800, 5400, 60, 18),
            _StarterProduct('shampoo', 'Clinic Plus Shampoo Sachet', 'homecare', 'pcs', 1000, 1000, 700, 100, 18),
            _StarterProduct('detergent', 'Surf Excel Matic (1kg)', 'homecare', 'pkt', 21000, 23000, 17500, 30, 18),
          ],
        );
    }
  }

  // --- QUERY APIS ---
  Future<List<ProductModel>> getAllProducts() async {
    final db = await instance.database;
    final result = await db.query('products', orderBy: 'name ASC');
    return result.map((json) => ProductModel.fromMap(json)).toList();
  }

  Future<List<CategoryModel>> getAllCategories() async {
    final db = await instance.database;
    final result = await db.query('categories', orderBy: 'name ASC');
    return result.map((json) => CategoryModel.fromMap(json)).toList();
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

  Future<int> getNextInvoiceSequence() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM sales');
    final count = Sqflite.firstIntValue(result) ?? 0;
    return count + 1;
  }

  // --- ATOMIC MULTI-TABLE POS TRANSACTION (Sub-10ms) ---
  Future<SaleModel> processPosBill({
    required String businessId,
    required List<CartItemModel> cartItems,
    required String paymentMethod,
    CustomerModel? customer,
    int discountPaise = 0,
    int splitCashPaise = 0,
    int splitUpiPaise = 0,
    int splitCreditPaise = 0,
    String? tableNumber,
  }) async {
    final db = await instance.database;

    final seq = await getNextInvoiceSequence();
    final String invoiceNumber = 'INV-${seq.toString().padLeft(3, '0')}';
    final saleId = _uuid.v4();

    int subtotalPaise = 0;
    int totalTaxPaise = 0;
    List<Map<String, dynamic>> itemsList = [];

    for (var item in cartItems) {
      subtotalPaise += item.grossTotalPaise;
      itemsList.add(item.toMap());
    }

    final totalAmountPaise = subtotalPaise - discountPaise;

    final sale = SaleModel(
      id: saleId,
      businessId: businessId,
      invoiceNumber: invoiceNumber,
      customerId: customer?.id,
      customerName: customer?.name,
      customerPhone: customer?.phone,
      subtotalPaise: subtotalPaise,
      taxAmountPaise: totalTaxPaise,
      discountPaise: discountPaise,
      totalAmountPaise: totalAmountPaise,
      paymentMethod: paymentMethod,
      splitCashPaise: splitCashPaise,
      splitUpiPaise: splitUpiPaise,
      splitCreditPaise: splitCreditPaise,
      tableNumber: tableNumber,
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

    return sale;
  }

  Future<void> upsertProduct(ProductModel product) async {
    final db = await instance.database;
    await db.insert(
      'products',
      product.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertCategory(CategoryModel category) async {
    final db = await instance.database;
    await db.insert(
      'categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertCustomer(CustomerModel customer) async {
    final db = await instance.database;
    await db.insert(
      'customers',
      customer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> seedStarterSalesIfNeeded() async {
    final db = await instance.database;
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM sales')) ?? 0;
    if (count > 0) return;

    final now = DateTime.now();
    final starterSales = [
      {
        'id': 'sale_init_1',
        'business_id': 'biz_starter_pos',
        'invoice_number': 'INV-1001',
        'customer_id': 'cust_1',
        'customer_name': 'Ramesh Kumar',
        'customer_phone': '9820012345',
        'subtotal_paise': 45000,
        'tax_amount_paise': 0,
        'discount_paise': 0,
        'total_amount_paise': 45000,
        'payment_method': 'credit',
        'status': 'completed',
        'items_json': jsonEncode([
          {'product_name': 'Aashirvaad Shudh Chakki Atta (5kg)', 'quantity': 1, 'price': 24500, 'gross_total_paise': 24500},
          {'product_name': 'Amul Butter Pasteurised (500g)', 'quantity': 1, 'price': 20500, 'gross_total_paise': 20500},
        ]),
        'created_at': now.subtract(const Duration(minutes: 35)).toIso8601String(),
        'sync_status': 'synced',
      },
      {
        'id': 'sale_init_2',
        'business_id': 'biz_starter_pos',
        'invoice_number': 'INV-1002',
        'customer_id': 'cust_2',
        'customer_name': 'Anita Sharma',
        'customer_phone': '9819098765',
        'subtotal_paise': 27500,
        'tax_amount_paise': 0,
        'discount_paise': 0,
        'total_amount_paise': 27500,
        'payment_method': 'upi',
        'status': 'completed',
        'items_json': jsonEncode([
          {'product_name': 'Amul Butter Pasteurised (500g)', 'quantity': 1, 'price': 27500, 'gross_total_paise': 27500},
        ]),
        'created_at': now.subtract(const Duration(hours: 2, minutes: 15)).toIso8601String(),
        'sync_status': 'synced',
      },
      {
        'id': 'sale_init_3',
        'business_id': 'biz_starter_pos',
        'invoice_number': 'INV-1003',
        'customer_id': null,
        'customer_name': 'Walk-in Customer',
        'customer_phone': null,
        'subtotal_paise': 15500,
        'tax_amount_paise': 0,
        'discount_paise': 0,
        'total_amount_paise': 15500,
        'payment_method': 'cash',
        'status': 'completed',
        'items_json': jsonEncode([
          {'product_name': 'Fortune Sunlite Sunflower Oil (1L)', 'quantity': 1, 'price': 15500, 'gross_total_paise': 15500},
        ]),
        'created_at': now.subtract(const Duration(hours: 4, minutes: 5)).toIso8601String(),
        'sync_status': 'synced',
      },
    ];

    for (final s in starterSales) {
      await db.insert('sales', s);
    }
  }

  Future<List<SaleModel>> getAllSales({int limit = 100}) async {
    final db = await instance.database;
    var result = await db.query('sales', orderBy: 'created_at DESC', limit: limit);
    if (result.isEmpty) {
      await seedStarterSalesIfNeeded();
      result = await db.query('sales', orderBy: 'created_at DESC', limit: limit);
    }
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
  }

  Future<void> markSaleSynced(String saleId) async {
    final db = await instance.database;
    await db.update('sales', {'sync_status': 'synced'}, where: 'id = ?', whereArgs: [saleId]);
  }

  Future<void> addExpense(ExpenseModel expense) async {
    final db = await instance.database;
    await db.insert('expenses', expense.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ExpenseModel>> getAllExpenses() async {
    final db = await instance.database;
    final result = await db.query('expenses', orderBy: 'created_at DESC');
    if (result.isEmpty) {
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
  }

  Future<void> _ensureStoreProfileTable(Database db) async {
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
        address TEXT,
        pincode TEXT,
        gstin TEXT,
        fssai TEXT,
        logo_url TEXT,
        upi_accounts_json TEXT
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

  Future<void> saveStoreProfile(StoreProfileModel profile) async {
    final db = await instance.database;
    await _ensureStoreProfileTable(db);
    final map = profile.toMap();
    map['id'] = 'default_store';
    await db.insert('store_profile', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ==========================================
  // INVENTORY MOVEMENTS AUDIT TRAIL
  // ==========================================
  Future<void> recordInventoryMovement(InventoryMovementModel movement) async {
    final db = await instance.database;
    await db.insert('inventory_movements', movement.toMap());
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

  // ==========================================
  // CASH REGISTER SHIFTS
  // ==========================================
  Future<void> saveCashRegisterShift(CashRegisterShiftModel shift) async {
    final db = await instance.database;
    await db.insert('cash_register_shifts', shift.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
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
}

class _StarterCatalog {
  final List<_StarterCategory> categories;
  final List<_StarterProduct> products;

  const _StarterCatalog({
    required this.categories,
    required this.products,
  });
}

class _StarterCategory {
  final String id;
  final String name;

  const _StarterCategory(this.id, this.name);
}

class _StarterProduct {
  final String id;
  final String name;
  final String categoryId;
  final String unit;
  final int sellingPricePaise;
  final int mrpPaise;
  final int purchasePricePaise;
  final double stockQuantity;
  final double taxRate;
  const _StarterProduct(
    this.id,
    this.name,
    this.categoryId,
    this.unit,
    this.sellingPricePaise,
    this.mrpPaise,
    this.purchasePricePaise,
    this.stockQuantity,
    this.taxRate,
  );

  String get barcode => '890${id.hashCode.abs().toString().padLeft(10, '0').substring(0, 10)}';
}
