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
      version: 2,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateToV2(db);
        }
      },
      onOpen: (db) async {
        await _ensureExtraTables(db);
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
    try {
      await db.execute('ALTER TABLE customers ADD COLUMN address TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE customers ADD COLUMN is_vip INTEGER DEFAULT 0');
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
        batch_number TEXT,
        expiry_date TEXT,
        size TEXT,
        color TEXT,
        imei_serial TEXT,
        hsn_code TEXT,
        is_loose_item INTEGER DEFAULT 0,
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
        is_vip INTEGER DEFAULT 0,
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
    });
  }

  Future<void> upsertProduct(ProductModel product) async {
    final db = await instance.database;
    await db.insert(
      'products',
      product.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteProduct(String id) async {
    final db = await instance.database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
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

  Future<void> toggleCustomerVip(String id, bool isVip) async {
    final db = await instance.database;
    await db.update(
      'customers',
      {'is_vip': isVip ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteCustomer(String id) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('ledger_transactions', where: 'customer_id = ?', whereArgs: [id]);
      await txn.delete('customers', where: 'id = ?', whereArgs: [id]);
    });
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
}
