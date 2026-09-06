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
  final int currentBalancePaise; // Positive = customer owes money (Udhar)
  final int creditLimitPaise;
  final String syncStatus;

  CustomerModel({
    required this.id,
    required this.businessId,
    required this.name,
    required this.phone,
    this.currentBalancePaise = 0,
    this.creditLimitPaise = 500000, // Default ₹5,000 limit
    this.syncStatus = 'synced',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'business_id': businessId,
    'name': name,
    'phone': phone,
    'current_balance_paise': currentBalancePaise,
    'credit_limit_paise': creditLimitPaise,
    'sync_status': syncStatus,
  };

  factory CustomerModel.fromMap(Map<String, dynamic> map) => CustomerModel(
    id: map['id'] ?? '',
    businessId: map['business_id'] ?? '',
    name: map['name'] ?? '',
    phone: map['phone'] ?? '',
    currentBalancePaise: map['current_balance_paise'] ?? 0,
    creditLimitPaise: map['credit_limit_paise'] ?? 500000,
    syncStatus: map['sync_status'] ?? 'pending',
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

class StoreProfileModel {
  final String storeName;
  final String ownerName;
  final String phone;
  final String upiVpa;
  final String category;
  final String address;
  final String gstin;

  StoreProfileModel({
    this.storeName = 'Sharma Kirana & General Store',
    this.ownerName = 'Rahul Jadhav',
    this.phone = '9876543210',
    this.upiVpa = 'sharmakirana@paytm',
    this.category = 'Grocery / Kirana',
    this.address = 'Shop #4, Main Market, Mumbai',
    this.gstin = '27AAAAA0000A1Z5',
  });

  Map<String, dynamic> toMap() => {
    'store_name': storeName,
    'owner_name': ownerName,
    'phone': phone,
    'upi_vpa': upiVpa,
    'category': category,
    'address': address,
    'gstin': gstin,
  };

  factory StoreProfileModel.fromMap(Map<String, dynamic> map) => StoreProfileModel(
    storeName: map['store_name'] ?? 'Sharma Kirana & General Store',
    ownerName: map['owner_name'] ?? 'Rahul Jadhav',
    phone: map['phone'] ?? '9876543210',
    upiVpa: map['upi_vpa'] ?? 'sharmakirana@paytm',
    category: map['category'] ?? 'Grocery / Kirana',
    address: map['address'] ?? 'Shop #4, Main Market, Mumbai',
    gstin: map['gstin'] ?? '27AAAAA0000A1Z5',
  );
}
