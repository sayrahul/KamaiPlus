import 'dart:convert';

class CategoryModel {
  final String id;
  final String businessId;
  final String name;

  CategoryModel({
    required this.id,
    required this.businessId,
    required this.name,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'business_id': businessId,
    'name': name,
  };

  factory CategoryModel.fromMap(Map<String, dynamic> map) => CategoryModel(
    id: map['id'] ?? '',
    businessId: map['business_id'] ?? '',
    name: map['name'] ?? '',
  );
}

class ProductModel {
  final String id;
  final String businessId;
  final String name;
  final String? barcode;
  final String? categoryId;
  final int sellingPricePaise;
  final int mrpPaise;
  final int purchasePricePaise;
  final double stockQuantity;
  final double taxRate;
  final bool isTaxInclusive;
  final String unit;
  final String syncStatus;

  ProductModel({
    required this.id,
    required this.businessId,
    required this.name,
    this.barcode,
    this.categoryId,
    required this.sellingPricePaise,
    required this.mrpPaise,
    this.purchasePricePaise = 0,
    required this.stockQuantity,
    this.taxRate = 0.0,
    this.isTaxInclusive = true,
    this.unit = 'pcs',
    this.syncStatus = 'synced',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'business_id': businessId,
    'name': name,
    'barcode': barcode,
    'category_id': categoryId,
    'selling_price_paise': sellingPricePaise,
    'mrp_paise': mrpPaise,
    'purchase_price_paise': purchasePricePaise,
    'stock_quantity': stockQuantity,
    'tax_rate': taxRate,
    'is_tax_inclusive': isTaxInclusive ? 1 : 0,
    'unit': unit,
    'sync_status': syncStatus,
  };

  factory ProductModel.fromMap(Map<String, dynamic> map) => ProductModel(
    id: map['id'] ?? '',
    businessId: map['business_id'] ?? '',
    name: map['name'] ?? '',
    barcode: map['barcode'],
    categoryId: map['category_id'],
    sellingPricePaise: map['selling_price_paise'] ?? 0,
    mrpPaise: map['mrp_paise'] ?? 0,
    purchasePricePaise: map['purchase_price_paise'] ?? 0,
    stockQuantity: (map['stock_quantity'] as num?)?.toDouble() ?? 0.0,
    taxRate: (map['tax_rate'] as num?)?.toDouble() ?? 0.0,
    isTaxInclusive: (map['is_tax_inclusive'] == 1 || map['is_tax_inclusive'] == true),
    unit: map['unit'] ?? 'pcs',
    syncStatus: map['sync_status'] ?? 'pending',
  );

  ProductModel copyWith({
    double? stockQuantity,
    int? sellingPricePaise,
    String? name,
  }) => ProductModel(
    id: id,
    businessId: businessId,
    name: name ?? this.name,
    barcode: barcode,
    categoryId: categoryId,
    sellingPricePaise: sellingPricePaise ?? this.sellingPricePaise,
    mrpPaise: mrpPaise,
    purchasePricePaise: purchasePricePaise,
    stockQuantity: stockQuantity ?? this.stockQuantity,
    taxRate: taxRate,
    isTaxInclusive: isTaxInclusive,
    unit: unit,
    syncStatus: syncStatus,
  );
}

class CustomerModel {
  final String id;
  final String businessId;
  final String name;
  final String phone;
  final String? address;
  final int currentBalancePaise; // Positive = customer owes money (Udhar)
  final int creditLimitPaise;
  final String syncStatus;

  CustomerModel({
    required this.id,
    required this.businessId,
    required this.name,
    required this.phone,
    this.address,
    this.currentBalancePaise = 0,
    this.creditLimitPaise = 500000, // Default ₹5,000 limit
    this.syncStatus = 'synced',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'business_id': businessId,
    'name': name,
    'phone': phone,
    'address': address,
    'current_balance_paise': currentBalancePaise,
    'credit_limit_paise': creditLimitPaise,
    'sync_status': syncStatus,
  };

  factory CustomerModel.fromMap(Map<String, dynamic> map) => CustomerModel(
    id: map['id'] ?? '',
    businessId: map['business_id'] ?? '',
    name: map['name'] ?? '',
    phone: map['phone'] ?? '',
    address: map['address'],
    currentBalancePaise: map['current_balance_paise'] ?? 0,
    creditLimitPaise: map['credit_limit_paise'] ?? 500000,
    syncStatus: map['sync_status'] ?? 'pending',
  );

  CustomerModel copyWith({
    String? name,
    String? phone,
    String? address,
    int? currentBalancePaise,
    int? creditLimitPaise,
    String? syncStatus,
  }) => CustomerModel(
    id: id,
    businessId: businessId,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    address: address ?? this.address,
    currentBalancePaise: currentBalancePaise ?? this.currentBalancePaise,
    creditLimitPaise: creditLimitPaise ?? this.creditLimitPaise,
    syncStatus: syncStatus ?? this.syncStatus,
  );
}

class CartItemModel {
  final ProductModel product;
  double quantity;
  int unitPricePaise;
  String discountType; // 'flat' | 'percentage'
  double discountValue; // in rupees for flat, or 0..100 for percentage

  CartItemModel({
    required this.product,
    this.quantity = 1.0,
    int? unitPricePaise,
    this.discountType = 'flat',
    this.discountValue = 0.0,
    double? discountPercent,
  }) : unitPricePaise = unitPricePaise ?? product.sellingPricePaise {
    if (discountPercent != null && discountPercent > 0) {
      discountType = 'percentage';
      discountValue = discountPercent;
    }
  }

  double get discountPercent => discountType == 'percentage' ? discountValue : 0.0;
  set discountPercent(double val) {
    discountType = 'percentage';
    discountValue = val;
  }

  int get grossTotalPaise {
    final base = (unitPricePaise * quantity).round();
    if (discountType == 'percentage' && discountValue > 0) {
      final discount = (base * discountValue / 100).round();
      return base - discount;
    } else if (discountType == 'flat' && discountValue > 0) {
      final discountPaise = (discountValue * 100).round();
      return (base - discountPaise).clamp(0, base);
    }
    return base;
  }

  Map<String, dynamic> toMap() => {
    'product_id': product.id,
    'product_name': product.name,
    'quantity': quantity,
    'unit_price_paise': unitPricePaise,
    'gross_total_paise': grossTotalPaise,
    'tax_rate': product.taxRate,
    'is_tax_inclusive': product.isTaxInclusive ? 1 : 0,
    'discount_type': discountType,
    'discount_value': discountValue,
  };
}

class SaleModel {
  final String id;
  final String businessId;
  final String invoiceNumber;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final int subtotalPaise;
  final int taxAmountPaise;
  final int discountPaise;
  final int totalAmountPaise;
  final String paymentMethod; // 'cash' | 'upi' | 'credit' (udhar) | 'split'
  final String status;
  final List<Map<String, dynamic>> items;
  final DateTime createdAt;
  final String syncStatus;

  SaleModel({
    required this.id,
    required this.businessId,
    required this.invoiceNumber,
    this.customerId,
    this.customerName,
    this.customerPhone,
    required this.subtotalPaise,
    required this.taxAmountPaise,
    this.discountPaise = 0,
    required this.totalAmountPaise,
    required this.paymentMethod,
    this.status = 'completed',
    required this.items,
    required this.createdAt,
    this.syncStatus = 'pending',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'business_id': businessId,
    'invoice_number': invoiceNumber,
    'customer_id': customerId,
    'customer_name': customerName,
    'customer_phone': customerPhone,
    'subtotal_paise': subtotalPaise,
    'tax_amount_paise': taxAmountPaise,
    'discount_paise': discountPaise,
    'total_amount_paise': totalAmountPaise,
    'payment_method': paymentMethod,
    'status': status,
    'items_json': jsonEncode(items),
    'created_at': createdAt.toIso8601String(),
    'sync_status': syncStatus,
  };

  factory SaleModel.fromMap(Map<String, dynamic> map) {
    List<Map<String, dynamic>> parsedItems = [];
    try {
      if (map['items_json'] != null) {
        parsedItems = List<Map<String, dynamic>>.from(jsonDecode(map['items_json']));
      }
    } catch (_) {}

    return SaleModel(
      id: map['id'] ?? '',
      businessId: map['business_id'] ?? '',
      invoiceNumber: map['invoice_number'] ?? '',
      customerId: map['customer_id'],
      customerName: map['customer_name'],
      customerPhone: map['customer_phone'],
      subtotalPaise: map['subtotal_paise'] ?? 0,
      taxAmountPaise: map['tax_amount_paise'] ?? 0,
      discountPaise: map['discount_paise'] ?? 0,
      totalAmountPaise: map['total_amount_paise'] ?? 0,
      paymentMethod: map['payment_method'] ?? 'cash',
      status: map['status'] ?? 'completed',
      items: parsedItems,
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
      syncStatus: map['sync_status'] ?? 'pending',
    );
  }
}

class LedgerTransactionModel {
  final String id;
  final String businessId;
  final String customerId;
  final String type; // 'credit' (Customer took Udhar) | 'debit' (Customer paid back cash/UPI)
  final int amountPaise;
  final int balanceAfterPaise;
  final String description;
  final String? referenceId;
  final DateTime createdAt;
  final String syncStatus;

  LedgerTransactionModel({
    required this.id,
    required this.businessId,
    required this.customerId,
    required this.type,
    required this.amountPaise,
    required this.balanceAfterPaise,
    required this.description,
    this.referenceId,
    required this.createdAt,
    this.syncStatus = 'pending',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'business_id': businessId,
    'customer_id': customerId,
    'type': type,
    'amount_paise': amountPaise,
    'balance_after_paise': balanceAfterPaise,
    'description': description,
    'reference_id': referenceId,
    'created_at': createdAt.toIso8601String(),
    'sync_status': syncStatus,
  };

  factory LedgerTransactionModel.fromMap(Map<String, dynamic> map) => LedgerTransactionModel(
    id: map['id'] ?? '',
    businessId: map['business_id'] ?? '',
    customerId: map['customer_id'] ?? '',
    type: map['type'] ?? 'credit',
    amountPaise: map['amount_paise'] ?? 0,
    balanceAfterPaise: map['balance_after_paise'] ?? 0,
    description: map['description'] ?? '',
    referenceId: map['reference_id'],
    createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    syncStatus: map['sync_status'] ?? 'pending',
  );
}


class ExpenseModel {
  final String id;
  final String businessId;
  final String title;
  final int amountPaise;
  final String category;
  final DateTime createdAt;
  final String note;

  ExpenseModel({
    required this.id,
    required this.businessId,
    required this.title,
    required this.amountPaise,
    this.category = 'General',
    required this.createdAt,
    this.note = '',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'business_id': businessId,
    'title': title,
    'amount_paise': amountPaise,
    'category': category,
    'created_at': createdAt.toIso8601String(),
    'note': note,
  };

  factory ExpenseModel.fromMap(Map<String, dynamic> map) => ExpenseModel(
    id: map['id'] ?? '',
    businessId: map['business_id'] ?? '',
    title: map['title'] ?? '',
    amountPaise: map['amount_paise'] ?? 0,
    category: map['category'] ?? 'General',
    createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    note: map['note'] ?? '',
  );
}

class UpiAccountModel {
  final String id;
  final String label;
  final String upiVpa;
  final bool isDefault;

  UpiAccountModel({
    required this.id,
    required this.label,
    required this.upiVpa,
    this.isDefault = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'upi_vpa': upiVpa,
    'is_default': isDefault ? 1 : 0,
  };

  factory UpiAccountModel.fromMap(Map<String, dynamic> map) => UpiAccountModel(
    id: map['id'] ?? '',
    label: map['label'] ?? '',
    upiVpa: map['upi_vpa'] ?? '',
    isDefault: map['is_default'] == 1 || map['is_default'] == true,
  );
}

class StoreProfileModel {
  final String storeName;
  final String tagline;
  final String ownerName;
  final String phone;
  final String email;
  final String upiVpa;
  final String category;
  final String address;
  final String pincode;
  final String gstin;
  final String fssai;
  final String logoUrl;
  final String upiAccountsJson;

  StoreProfileModel({
    this.storeName = 'Rahul Shramas',
    this.tagline = 'Always Fresh, Best Wholesale Rates',
    this.ownerName = 'Divyaang Pratishthan',
    this.phone = '9595997711',
    this.email = 'iamdivyaang@gmail.com',
    this.upiVpa = 'rahuljadhav44@ybl',
    this.category = 'Grocery / Kirana',
    this.address = 'Shop No. 12, Gandhi Market, Station Road',
    this.pincode = '400001',
    this.gstin = '',
    this.fssai = '',
    this.logoUrl = '',
    this.upiAccountsJson = '[{"id":"upi_1","label":"Shop Primary QR","upi_vpa":"rahuljadhav44@ybl","is_default":1}]',
  });

  Map<String, dynamic> toMap() => {
    'store_name': storeName,
    'tagline': tagline,
    'owner_name': ownerName,
    'phone': phone,
    'email': email,
    'upi_vpa': upiVpa,
    'category': category,
    'address': address,
    'pincode': pincode,
    'gstin': gstin,
    'fssai': fssai,
    'logo_url': logoUrl,
    'upi_accounts_json': upiAccountsJson,
  };

  factory StoreProfileModel.fromMap(Map<String, dynamic> map) => StoreProfileModel(
    storeName: map['store_name'] ?? 'Rahul Shramas',
    tagline: map['tagline'] ?? 'Always Fresh, Best Wholesale Rates',
    ownerName: map['owner_name'] ?? 'Divyaang Pratishthan',
    phone: map['phone'] ?? '9595997711',
    email: map['email'] ?? 'iamdivyaang@gmail.com',
    upiVpa: map['upi_vpa'] ?? 'rahuljadhav44@ybl',
    category: map['category'] ?? 'Grocery / Kirana',
    address: map['address'] ?? 'Shop No. 12, Gandhi Market, Station Road',
    pincode: map['pincode'] ?? '400001',
    gstin: map['gstin'] ?? '',
    fssai: map['fssai'] ?? '',
    logoUrl: map['logo_url'] ?? '',
    upiAccountsJson: map['upi_accounts_json'] ?? '[{"id":"upi_1","label":"Shop Primary QR","upi_vpa":"rahuljadhav44@ybl","is_default":1}]',
  );
}

class InventoryMovementModel {
  final String id;
  final String businessId;
  final String productId;
  final String productName;
  final String movementType; // 'SALE' | 'PURCHASE' | 'RETURN' | 'ADJUSTMENT' | 'DAMAGE'
  final double quantity;
  final double previousStock;
  final double newStock;
  final String? referenceId;
  final DateTime createdAt;

  InventoryMovementModel({
    required this.id,
    required this.businessId,
    required this.productId,
    required this.productName,
    required this.movementType,
    required this.quantity,
    required this.previousStock,
    required this.newStock,
    this.referenceId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'business_id': businessId,
    'product_id': productId,
    'product_name': productName,
    'movement_type': movementType,
    'quantity': quantity,
    'previous_stock': previousStock,
    'new_stock': newStock,
    'reference_id': referenceId,
    'created_at': createdAt.toIso8601String(),
  };

  factory InventoryMovementModel.fromMap(Map<String, dynamic> map) => InventoryMovementModel(
    id: map['id'] ?? '',
    businessId: map['business_id'] ?? '',
    productId: map['product_id'] ?? '',
    productName: map['product_name'] ?? '',
    movementType: map['movement_type'] ?? 'SALE',
    quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
    previousStock: (map['previous_stock'] as num?)?.toDouble() ?? 0.0,
    newStock: (map['new_stock'] as num?)?.toDouble() ?? 0.0,
    referenceId: map['reference_id'],
    createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
  );
}

class SupplierModel {
  final String id;
  final String businessId;
  final String name;
  final String phone;
  final String category;
  final int currentBalancePaise; // Udhar due to supplier
  final String? gstin;
  final String syncStatus;

  SupplierModel({
    required this.id,
    required this.businessId,
    required this.name,
    required this.phone,
    required this.category,
    this.currentBalancePaise = 0,
    this.gstin,
    this.syncStatus = 'synced',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'business_id': businessId,
    'name': name,
    'phone': phone,
    'category': category,
    'current_balance_paise': currentBalancePaise,
    'gstin': gstin,
    'sync_status': syncStatus,
  };

  factory SupplierModel.fromMap(Map<String, dynamic> map) => SupplierModel(
    id: map['id'] ?? '',
    businessId: map['business_id'] ?? '',
    name: map['name'] ?? '',
    phone: map['phone'] ?? '',
    category: map['category'] ?? 'General',
    currentBalancePaise: map['current_balance_paise'] ?? 0,
    gstin: map['gstin'],
    syncStatus: map['sync_status'] ?? 'pending',
  );
}

class CashRegisterShiftModel {
  final String id;
  final String businessId;
  final int openingCashPaise;
  final int cashSalesPaise;
  final int cashExpensesPaise;
  final int expectedClosingPaise;
  final int actualClosingPaise;
  final int differencePaise;
  final String status; // 'open' | 'closed'
  final DateTime openedAt;
  final DateTime? closedAt;

  CashRegisterShiftModel({
    required this.id,
    required this.businessId,
    required this.openingCashPaise,
    this.cashSalesPaise = 0,
    this.cashExpensesPaise = 0,
    required this.expectedClosingPaise,
    this.actualClosingPaise = 0,
    this.differencePaise = 0,
    this.status = 'open',
    required this.openedAt,
    this.closedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'business_id': businessId,
    'opening_cash_paise': openingCashPaise,
    'cash_sales_paise': cashSalesPaise,
    'cash_expenses_paise': cashExpensesPaise,
    'expected_closing_paise': expectedClosingPaise,
    'actual_closing_paise': actualClosingPaise,
    'difference_paise': differencePaise,
    'status': status,
    'opened_at': openedAt.toIso8601String(),
    'closed_at': closedAt?.toIso8601String(),
  };

  factory CashRegisterShiftModel.fromMap(Map<String, dynamic> map) => CashRegisterShiftModel(
    id: map['id'] ?? '',
    businessId: map['business_id'] ?? '',
    openingCashPaise: map['opening_cash_paise'] ?? 0,
    cashSalesPaise: map['cash_sales_paise'] ?? 0,
    cashExpensesPaise: map['cash_expenses_paise'] ?? 0,
    expectedClosingPaise: map['expected_closing_paise'] ?? 0,
    actualClosingPaise: map['actual_closing_paise'] ?? 0,
    differencePaise: map['difference_paise'] ?? 0,
    status: map['status'] ?? 'open',
    openedAt: DateTime.tryParse(map['opened_at'] ?? '') ?? DateTime.now(),
    closedAt: map['closed_at'] != null ? DateTime.tryParse(map['closed_at']) : null,
  );
}

