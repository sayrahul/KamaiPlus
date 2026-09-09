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
  final String? batchNumber;
  final String? expiryDate;
  final String? size;
  final String? color;
  final String? imeiSerial;
  final String? hsnCode;
  final bool isLooseItem;
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
    this.batchNumber,
    this.expiryDate,
    this.size,
    this.color,
    this.imeiSerial,
    this.hsnCode,
    this.isLooseItem = false,
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
    'batch_number': batchNumber,
    'expiry_date': expiryDate,
    'size': size,
    'color': color,
    'imei_serial': imeiSerial,
    'hsn_code': hsnCode,
    'is_loose_item': isLooseItem ? 1 : 0,
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
    batchNumber: map['batch_number'] as String?,
    expiryDate: map['expiry_date'] as String?,
    size: map['size'] as String?,
    color: map['color'] as String?,
    imeiSerial: map['imei_serial'] as String?,
    hsnCode: map['hsn_code'] as String?,
    isLooseItem: map['is_loose_item'] == 1 || map['is_loose_item'] == true,
    syncStatus: map['sync_status'] ?? 'pending',
  );

  ProductModel copyWith({
    double? stockQuantity,
    int? sellingPricePaise,
    int? mrpPaise,
    int? purchasePricePaise,
    String? name,
    String? barcode,
    String? categoryId,
    double? taxRate,
    bool? isTaxInclusive,
    String? unit,
    String? batchNumber,
    String? expiryDate,
    String? size,
    String? color,
    String? imeiSerial,
    String? hsnCode,
    bool? isLooseItem,
    String? syncStatus,
  }) => ProductModel(
    id: id,
    businessId: businessId,
    name: name ?? this.name,
    barcode: barcode ?? this.barcode,
    categoryId: categoryId ?? this.categoryId,
    sellingPricePaise: sellingPricePaise ?? this.sellingPricePaise,
    mrpPaise: mrpPaise ?? this.mrpPaise,
    purchasePricePaise: purchasePricePaise ?? this.purchasePricePaise,
    stockQuantity: stockQuantity ?? this.stockQuantity,
    taxRate: taxRate ?? this.taxRate,
    isTaxInclusive: isTaxInclusive ?? this.isTaxInclusive,
    unit: unit ?? this.unit,
    batchNumber: batchNumber ?? this.batchNumber,
    expiryDate: expiryDate ?? this.expiryDate,
    size: size ?? this.size,
    color: color ?? this.color,
    imeiSerial: imeiSerial ?? this.imeiSerial,
    hsnCode: hsnCode ?? this.hsnCode,
    isLooseItem: isLooseItem ?? this.isLooseItem,
    syncStatus: syncStatus ?? this.syncStatus,
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
  final bool isVip;

  CustomerModel({
    required this.id,
    required this.businessId,
    required this.name,
    required this.phone,
    this.address,
    this.currentBalancePaise = 0,
    this.creditLimitPaise = 500000, // Default ₹5,000 limit
    this.syncStatus = 'synced',
    this.isVip = false,
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
    'is_vip': isVip ? 1 : 0,
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
    isVip: map['is_vip'] == 1 || map['is_vip'] == true,
  );

  CustomerModel copyWith({
    String? name,
    String? phone,
    String? address,
    int? currentBalancePaise,
    int? creditLimitPaise,
    String? syncStatus,
    bool? isVip,
  }) => CustomerModel(
    id: id,
    businessId: businessId,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    address: address ?? this.address,
    currentBalancePaise: currentBalancePaise ?? this.currentBalancePaise,
    creditLimitPaise: creditLimitPaise ?? this.creditLimitPaise,
    syncStatus: syncStatus ?? this.syncStatus,
    isVip: isVip ?? this.isVip,
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

class DoctorModel {
  final String id;
  final String businessId;
  final String name;
  final String? qualification;
  final String? registrationNumber;
  final String? phone;

  DoctorModel({
    required this.id,
    required this.businessId,
    required this.name,
    this.qualification,
    this.registrationNumber,
    this.phone,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'business_id': businessId,
    'name': name,
    'qualification': qualification,
    'registration_number': registrationNumber,
    'phone': phone,
  };

  factory DoctorModel.fromMap(Map<String, dynamic> map) => DoctorModel(
    id: map['id'] ?? '',
    businessId: map['business_id'] ?? '',
    name: map['name'] ?? '',
    qualification: map['qualification'],
    registrationNumber: map['registration_number'],
    phone: map['phone'],
  );
}

class SaleModel {
  final String id;
  final String businessId;
  final String invoiceNumber;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? doctorName;
  final String? tableNumber;
  final int subtotalPaise;
  final int taxAmountPaise;
  final int discountPaise;
  final int totalAmountPaise;
  final String paymentMethod; // 'cash' | 'upi' | 'credit' (udhar) | 'split'
  final int splitCashPaise;
  final int splitUpiPaise;
  final int splitCreditPaise;
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
    this.doctorName,
    this.tableNumber,
    required this.subtotalPaise,
    required this.taxAmountPaise,
    this.discountPaise = 0,
    required this.totalAmountPaise,
    required this.paymentMethod,
    this.splitCashPaise = 0,
    this.splitUpiPaise = 0,
    this.splitCreditPaise = 0,
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
    'doctor_name': doctorName,
    'table_number': tableNumber,
    'subtotal_paise': subtotalPaise,
    'tax_amount_paise': taxAmountPaise,
    'discount_paise': discountPaise,
    'total_amount_paise': totalAmountPaise,
    'payment_method': paymentMethod,
    'split_cash_paise': splitCashPaise,
    'split_upi_paise': splitUpiPaise,
    'split_credit_paise': splitCreditPaise,
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
      doctorName: map['doctor_name'],
      tableNumber: map['table_number'],
      subtotalPaise: map['subtotal_paise'] ?? 0,
      taxAmountPaise: map['tax_amount_paise'] ?? 0,
      discountPaise: map['discount_paise'] ?? 0,
      totalAmountPaise: map['total_amount_paise'] ?? 0,
      paymentMethod: map['payment_method'] ?? 'cash',
      splitCashPaise: map['split_cash_paise'] ?? 0,
      splitUpiPaise: map['split_upi_paise'] ?? 0,
      splitCreditPaise: map['split_credit_paise'] ?? 0,
      status: map['status'] ?? 'completed',
      items: parsedItems,
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
      syncStatus: map['sync_status'] ?? 'pending',
    );
  }

  bool get isRefunded => status.toLowerCase() == 'refunded' || status.toLowerCase() == 'returned';
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
  final String businessType;
  final String address;
  final String pincode;
  final String gstin;
  final String fssai;
  final String logoUrl;
  final String upiAccountsJson;
  final bool isPro;
  final String proPlan; // 'free' | 'monthly' | 'annual'
  final String proExpiry; // ISO date string
  final String razorpayPaymentId;

  StoreProfileModel({
    this.storeName = '',
    this.tagline = '',
    this.ownerName = '',
    this.phone = '',
    this.email = '',
    this.upiVpa = '',
    this.category = '',
    this.businessType = '',
    this.address = '',
    this.pincode = '',
    this.gstin = '',
    this.fssai = '',
    this.logoUrl = '',
    this.upiAccountsJson = '[]',
    this.isPro = false,
    this.proPlan = 'free',
    this.proExpiry = '',
    this.razorpayPaymentId = '',
  });

  /// True only when user has actively completed store setup
  bool get isConfigured =>
      storeName.trim().isNotEmpty &&
      businessType.trim().isNotEmpty &&
      storeName.trim() != 'KamaiPlus Store';

  /// Evaluates whether Pro membership is currently active and unexpired
  bool get isProEffective {
    if (!isPro) return false;
    if (proExpiry.trim().isEmpty) return true;
    final exp = DateTime.tryParse(proExpiry.trim());
    if (exp == null) return true;
    return DateTime.now().isBefore(exp);
  }

  Map<String, dynamic> toMap() => {
    'store_name': storeName,
    'tagline': tagline,
    'owner_name': ownerName,
    'phone': phone,
    'email': email,
    'upi_vpa': upiVpa,
    'category': category,
    'business_type': businessType,
    'address': address,
    'pincode': pincode,
    'gstin': gstin,
    'fssai': fssai,
    'logo_url': logoUrl,
    'upi_accounts_json': upiAccountsJson,
    'is_pro': isPro ? 1 : 0,
    'pro_plan': proPlan,
    'pro_expiry': proExpiry,
    'razorpay_payment_id': razorpayPaymentId,
  };

  factory StoreProfileModel.fromMap(Map<String, dynamic> map) {
    final rawIsPro = (map['is_pro'] is int ? map['is_pro'] == 1 : (map['is_pro'] as bool? ?? false));
    final expiryStr = (map['pro_expiry'] ?? '').toString().trim();
    final expiryDate = expiryStr.isNotEmpty ? DateTime.tryParse(expiryStr) : null;
    final bool effectivePro = rawIsPro && (expiryDate == null || DateTime.now().isBefore(expiryDate));

    return StoreProfileModel(
      storeName: (map['store_name'] as String?)?.isNotEmpty == true ? map['store_name'] : 'KamaiPlus Store',
      tagline: (map['tagline'] as String?)?.isNotEmpty == true ? map['tagline'] : 'Always Fresh, Best Wholesale Rates',
      ownerName: (map['owner_name'] as String?)?.isNotEmpty == true ? map['owner_name'] : 'Store Owner',
      phone: map['phone'] ?? '',
      email: map['email'] ?? '',
      upiVpa: map['upi_vpa'] ?? '',
      category: (map['category'] as String?)?.isNotEmpty == true ? map['category'] : 'Retail Store',
      businessType: (map['business_type'] as String?)?.isNotEmpty == true ? map['business_type'] : 'grocery',
      address: map['address'] ?? 'Main Market, Station Road',
      pincode: map['pincode'] ?? '',
      gstin: map['gstin'] ?? '',
      fssai: map['fssai'] ?? '',
      logoUrl: map['logo_url'] ?? '',
      upiAccountsJson: map['upi_accounts_json'] ?? '[]',
      isPro: effectivePro,
      proPlan: (map['pro_plan'] as String?)?.isNotEmpty == true ? map['pro_plan'] : 'free',
      proExpiry: expiryStr,
      razorpayPaymentId: map['razorpay_payment_id'] ?? '',
    );
  }
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

class CartTabModel {
  String id;
  String name;
  int number;
  Map<String, CartItemModel> items;
  CustomerModel? customer;

  CartTabModel({
    required this.id,
    required this.name,
    required this.number,
    required this.items,
    this.customer,
  });

  int get totalItemCount => items.values.fold<int>(0, (sum, it) => sum + it.quantity.toInt());
  int get grossTotalPaise => items.values.fold<int>(0, (sum, it) => sum + it.grossTotalPaise);
}

typedef CartTab = CartTabModel;

