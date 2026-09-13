import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kamaiplus_pos/core/database/local_database.dart';
import 'package:kamaiplus_pos/models/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await LocalDatabase.instance.switchUser('partial_return_test_${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() async {
    await LocalDatabase.instance.closeDatabase();
  });

  test('Partial sales return restocks only returned items and updates sale status', () async {
    final db = LocalDatabase.instance;

    // 1. Create product with initial stock = 7.0 (assuming 3 were sold from 10)
    final prod = ProductModel(
      id: 'p_test_shirt',
      businessId: 'biz_test',
      name: 'Polo Cotton Shirt',
      sellingPricePaise: 50000, // ₹500.00
      mrpPaise: 60000,
      stockQuantity: 7.0,
      businessType: 'clothing',
    );
    await db.upsertProduct(prod);

    // 2. Create Sale Model with 3 shirts sold
    final sale = SaleModel(
      id: 'sale_test_123',
      businessId: 'biz_test',
      invoiceNumber: 'INV-1001',
      subtotalPaise: 150000,
      taxAmountPaise: 0,
      discountPaise: 0,
      totalAmountPaise: 150000,
      paymentMethod: 'cash',
      status: 'completed',
      items: [
        {
          'product_id': 'p_test_shirt',
          'product_name': 'Polo Cotton Shirt',
          'quantity': 3,
          'price_paise': 50000,
        }
      ],
      createdAt: DateTime.now(),
    );

    // Insert sale into SQLite
    final rawDb = await db.database;
    await rawDb.insert('sales', {
      'id': sale.id,
      'business_id': sale.businessId,
      'invoice_number': sale.invoiceNumber,
      'subtotal_paise': sale.subtotalPaise,
      'tax_amount_paise': sale.taxAmountPaise,
      'discount_paise': sale.discountPaise,
      'total_amount_paise': sale.totalAmountPaise,
      'payment_method': sale.paymentMethod,
      'status': sale.status,
      'items_json': jsonEncode(sale.items),
      'created_at': sale.createdAt.toIso8601String(),
      'sync_status': 'synced',
    });

    // 3. Process partial return of 1 shirt
    final retNum1 = await db.processPartialSalesReturn(
      sale: sale,
      returnItems: [
        {
          'product_id': 'p_test_shirt',
          'product_name': 'Polo Cotton Shirt',
          'return_quantity': 1.0,
          'price_paise': 50000,
        }
      ],
      refundMethod: 'cash',
      reason: 'Wrong size',
      userPin: '1234',
    );

    expect(retNum1.startsWith('RET-'), isTrue);

    // Verify stock increased by 1 -> from 7.0 to 8.0
    final productsAfterReturn1 = await db.getAllProducts(businessType: 'clothing');
    final updatedProd1 = productsAfterReturn1.firstWhere((p) => p.id == 'p_test_shirt');
    expect(updatedProd1.stockQuantity, 8.0);

    // Verify sale status is now partially_refunded
    final saleRows1 = await rawDb.query('sales', where: 'id = ?', whereArgs: [sale.id]);
    expect(saleRows1.first['status'], 'partially_refunded');

    final items1 = jsonDecode(saleRows1.first['items_json'] as String) as List;
    expect(items1.first['returned_quantity'], 1.0);

    // Verify sale_returns record
    final returns1 = await db.getSaleReturns(sale.id);
    expect(returns1.length, 1);
    expect(returns1.first['total_refund_paise'], 50000);

    // 4. Return remaining 2 shirts
    final updatedSale1 = SaleModel.fromMap(saleRows1.first);
    final retNum2 = await db.processPartialSalesReturn(
      sale: updatedSale1,
      returnItems: [
        {
          'product_id': 'p_test_shirt',
          'product_name': 'Polo Cotton Shirt',
          'return_quantity': 2.0,
          'price_paise': 50000,
        }
      ],
      refundMethod: 'cash',
      reason: 'Customer return',
      userPin: '1234',
    );

    expect(retNum2.startsWith('RET-'), isTrue);

    // Verify stock is now 10.0
    final productsAfterReturn2 = await db.getAllProducts(businessType: 'clothing');
    final updatedProd2 = productsAfterReturn2.firstWhere((p) => p.id == 'p_test_shirt');
    expect(updatedProd2.stockQuantity, 10.0);

    // Verify sale status is now fully 'refunded'
    final saleRows2 = await rawDb.query('sales', where: 'id = ?', whereArgs: [sale.id]);
    expect(saleRows2.first['status'], 'refunded');

    final returns2 = await db.getSaleReturns(sale.id);
    expect(returns2.length, 2);
  });
}
