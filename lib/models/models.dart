import 'dart:convert';

import '../core/utils/money_formatter.dart';

String inferBusinessType(String? name, String? category) {
  final text = '${name ?? ''} ${category ?? ''}'.toLowerCase();
  if (text.contains('dettol') ||
      text.contains('savlon') ||
      text.contains('lifebuoy') ||
      text.contains('vicks') ||
      text.contains('moov') ||
      text.contains('volini') ||
      text.contains('band-aid') ||
      text.contains('glucon') ||
      text.contains('glucose-d') ||
      text.contains('glucose powder') ||
      text.contains('horlicks') ||
      text.contains('bournvita') ||
      text.contains('complan') ||
      text.contains('toothpaste') ||
      text.contains('colgate') ||
      text.contains('close up') ||
      text.contains('sensodyne') ||
      text.contains('eno') ||
      text.contains('pudin hara') ||
      text.contains('strepsils') ||
      text.contains('iodex') ||
      text.contains('sanitizer') ||
      text.contains('diaper') ||
      text.contains('pampers') ||
      text.contains('boroline')) {
    return 'both';
  }
  if (text.contains('tablet') ||

      text.contains('capsule') ||
      text.contains('syrup') ||
      text.contains('dolo') ||
      text.contains('crocin') ||
      text.contains('paracetamol') ||
      text.contains('cetirizine') ||
      text.contains('ointment') ||
      text.contains('first aid') ||
      text.contains('bandage') ||
      text.contains('injection') ||
      text.contains('medical') ||
      text.contains('pharma') ||
      text.contains('strip') ||
      text.contains('azithromycin') ||
      text.contains('pantoprazole') ||
      text.contains('disprin') ||
      text.contains('benadryl') ||
      text.contains('ascoril') ||
      text.contains('betadine')) {
    return 'pharmacy';
  }
  if (text.contains('shirt') ||
      text.contains('t-shirt') ||
      text.contains('kurti') ||
      text.contains('saree') ||
      text.contains('jeans') ||
      text.contains('trouser') ||
      text.contains('footwear') ||
      text.contains('shoes') ||
      text.contains('sandals') ||
      text.contains('apparel') ||
      text.contains('clothing') ||
      text.contains('innerwear')) {
    return 'clothing';
  }
  if (text.contains('pipe') ||
      text.contains('paint') ||
      text.contains('wire') ||
      text.contains('switch') ||
      text.contains('mcb') ||
      text.contains('tool') ||
      text.contains('screw') ||
      text.contains('nail') ||
      text.contains('washbasin') ||
      text.contains('cement') ||
      text.contains('sanitary') ||
      text.contains('hardware') ||
      text.contains('bulb') ||
      text.contains('batten')) {
    return 'hardware';
  }
  if (text.contains('chai') ||
      text.contains('coffee') ||
      text.contains('samosa') ||
      text.contains('curry') ||
      text.contains('roti') ||
      text.contains('naan') ||
      text.contains('burger') ||
      text.contains('pizza') ||
      text.contains('dessert') ||
      text.contains('kulfi') ||
      text.contains('restaurant') ||
      text.contains('beverage')) {
    return 'restaurant';
  }
  return 'grocery';
}

class CategoryModel {
  final String id;
  final String businessId;
  final String name;
  final String businessType;

  CategoryModel({
    required this.id,
    required this.businessId,
    required this.name,
    this.businessType = 'grocery',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'business_id': businessId,
    'name': name,
    'business_type': businessType,
  };

  factory CategoryModel.fromMap(Map<String, dynamic> map) => CategoryModel(
    id: map['id'] ?? '',
    businessId: map['business_id'] ?? '',
    name: map['name'] ?? '',
    businessType: (map['business_type'] != null && map['business_type'].toString().isNotEmpty)
        ? map['business_type']
        : inferBusinessType(map['name'], ''),
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
  final bool isFavorite;
  final String syncStatus;
  final String businessType;
  /// How many sellable sub-units make up one pack of this product's [unit] —
  /// e.g. 15 tablets in a pharmacy strip, 10 pieces in a box. Null means
  /// unknown; quantity_config.dart falls back to whole/half-pack chips rather
  /// than assuming a count.
  final int? subUnitsPerPack;
  /// Free-text fit/size-chart note for Clothing — e.g. "Runs small, order
  /// one size up". Distinct from [size] (which holds the actual size label
  /// like "M" or "40"); this is the merchant's own guidance to a customer
  /// choosing between sizes.
  final String? fitNotes;

  /// Parent product ID if this product is a child variant (e.g. Size M, Color Red).
  final String? parentId;
  /// True if this product is a parent master SKU with child variants.
  final bool hasVariants;
  /// Human-readable label of the variant (e.g. "Size: M • Color: Blue").
  final String? variantLabel;

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
    this.isFavorite = false,
    this.syncStatus = 'synced',
    this.businessType = 'grocery',
    this.subUnitsPerPack,
    this.fitNotes,
    this.parentId,
    this.hasVariants = false,
    this.variantLabel,
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
    'is_favorite': isFavorite ? 1 : 0,
    'sync_status': syncStatus,
    'business_type': businessType,
    'sub_units_per_pack': subUnitsPerPack,
    'fit_notes': fitNotes,
    'parent_id': parentId,
    'has_variants': hasVariants ? 1 : 0,
    'variant_label': variantLabel,
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
    isFavorite: (map['is_favorite'] == 1 || map['is_favorite'] == true),
    syncStatus: map['sync_status'] ?? 'pending',
    businessType: (map['business_type'] != null && map['business_type'].toString().isNotEmpty)
        ? map['business_type']
        : inferBusinessType(map['name'], map['category_id']),
    subUnitsPerPack: (map['sub_units_per_pack'] as num?)?.toInt(),
    fitNotes: map['fit_notes'] as String?,
    parentId: map['parent_id'] as String?,
    hasVariants: (map['has_variants'] == 1 || map['has_variants'] == true),
    variantLabel: map['variant_label'] as String?,
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
    bool? isFavorite,
    String? syncStatus,
    String? businessType,
    int? subUnitsPerPack,
    String? fitNotes,
    String? parentId,
    bool? hasVariants,
    String? variantLabel,
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
    isFavorite: isFavorite ?? this.isFavorite,
    syncStatus: syncStatus ?? this.syncStatus,
    businessType: businessType ?? this.businessType,
    subUnitsPerPack: subUnitsPerPack ?? this.subUnitsPerPack,
    fitNotes: fitNotes ?? this.fitNotes,
    parentId: parentId ?? this.parentId,
    hasVariants: hasVariants ?? this.hasVariants,
    variantLabel: variantLabel ?? this.variantLabel,
  );

  /// True if this item is a child variant of a parent product.
  bool get isVariant => parentId != null && parentId!.isNotEmpty;


  /// Returns true if item has uncounted / infinite stock (stock quantity >= 99990).
  /// This prevents counter billing from being blocked by zero stock.
  bool get isUnlimitedStock => stockQuantity >= 99990.0;

  /// Strict inventory asset cost valuation in integer paise:
  /// (stockQuantity * purchasePricePaise).
  /// Excludes master parent items with variants (child variants hold the actual stock),
  /// unlimited stock (>= 99990), and negative stock.
  int get assetCostValuationPaise {
    if (hasVariants) return 0;
    if (isUnlimitedStock || stockQuantity <= 0) return 0;
    if (purchasePricePaise <= 0) return 0;
    return (stockQuantity * purchasePricePaise).round();
  }
}

/// Offline Master SKU catalog item pre-indexed for ultra-fast barcode scan
/// or 2-letter autocomplete lookups (<2ms query time).
class MasterProductModel {
  final String barcode;
  final String name;
  final String category;
  final int mrpPaise;
  final int sellingPricePaise;
  final String unit;
  final double taxRate;
  final String businessType;
  final String? brand;
  final String? hsnCode;

  const MasterProductModel({
    required this.barcode,
    required this.name,
    required this.category,
    required this.mrpPaise,
    required this.sellingPricePaise,
    this.unit = 'pcs',
    this.taxRate = 0.0,
    this.businessType = 'grocery',
    this.brand,
    this.hsnCode,
  });

  Map<String, dynamic> toMap() => {
    'barcode': barcode,
    'name': name,
    'category': category,
    'mrp_paise': mrpPaise,
    'selling_price_paise': sellingPricePaise,
    'unit': unit,
    'tax_rate': taxRate,
    'business_type': businessType,
    'brand': brand,
    'hsn_code': hsnCode,
  };

  factory MasterProductModel.fromMap(Map<String, dynamic> map) => MasterProductModel(
    barcode: map['barcode']?.toString() ?? '',
    name: map['name']?.toString() ?? '',
    category: map['category']?.toString() ?? 'General',
    mrpPaise: (map['mrp_paise'] as num?)?.toInt() ?? 0,
    sellingPricePaise: (map['selling_price_paise'] as num?)?.toInt() ?? 0,
    unit: map['unit']?.toString() ?? 'pcs',
    taxRate: (map['tax_rate'] as num?)?.toDouble() ?? 0.0,
    businessType: map['business_type']?.toString() ?? 'grocery',
    brand: map['brand'] as String?,
    hsnCode: map['hsn_code'] as String?,
  );

  /// 1-Tap converter: transforms master dictionary item into an active store ProductModel
  /// with optional stock (defaults to 99999.0 = Unlimited).
  ProductModel toProductModel({
    required String businessId,
    String? categoryId,
    double initialStock = 99999.0,
    int? customSellingPricePaise,
  }) {
    final sPrice = customSellingPricePaise ?? (sellingPricePaise > 0 ? sellingPricePaise : mrpPaise);
    return ProductModel(
      id: 'prod_m_${barcode}_${DateTime.now().millisecondsSinceEpoch}',
      businessId: businessId,
      name: name,
      barcode: barcode,
      categoryId: categoryId,
      mrpPaise: mrpPaise,
      sellingPricePaise: sPrice,
      // Deliberately 0, not an invented number. This used to be
      // `(mrpPaise * 0.85).round()` — a made-up 15% margin that nobody
      // entered and no supplier bill supports. It flowed straight into the
      // Home Pulse "Estimated Profit" tile and the inventory valuation, so
      // every catalog-imported SKU quietly reported a fictional profit. A
      // zero cost is honest ("not known yet") and the merchant sets the real
      // buying rate on first inward or from Edit Product.
      purchasePricePaise: 0,
      stockQuantity: initialStock,
      taxRate: taxRate,
      isTaxInclusive: true,
      unit: unit,
      hsnCode: hsnCode,
      isLooseItem: false,
      syncStatus: 'pending',
      businessType: businessType,
    );
  }
}



class CustomerModel {
  final String id;
  final String businessId;
  final String name;
  final String phone;
  final String? address;
  final String? gstin;
  final String? stateCode;
  final int currentBalancePaise; // Positive = customer owes money (Udhar)
  final int creditLimitPaise;
  final String syncStatus;
  final bool isVip;

  /// Birthday as `MM-DD` (e.g. `08-14`). Day and month only — a shopkeeper
  /// knows the date, not the year, and does not need to store one. Null means
  /// not recorded, which is the honest default; the Birthday campaign simply
  /// skips such customers rather than guessing.
  final String? birthday;

  CustomerModel({
    required this.id,
    required this.businessId,
    required this.name,
    required this.phone,
    this.address,
    this.gstin,
    this.stateCode,
    this.currentBalancePaise = 0,
    this.creditLimitPaise = 500000, // Default ₹5,000 limit
    this.syncStatus = 'synced',
    this.isVip = false,
    this.birthday,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'business_id': businessId,
    'name': name,
    'phone': phone,
    'address': address,
    'gstin': gstin,
    'state_code': stateCode,
    'current_balance_paise': currentBalancePaise,
    'credit_limit_paise': creditLimitPaise,
    'sync_status': syncStatus,
    'is_vip': isVip ? 1 : 0,
    'birthday': birthday,
  };

  /// Days until this customer's next birthday, or null when none is recorded.
  /// 0 means today.
  int? daysUntilBirthday([DateTime? now]) {
    final raw = birthday?.trim();
    if (raw == null || raw.isEmpty) return null;
    final m = RegExp(r'^(\d{1,2})-(\d{1,2})$').firstMatch(raw);
    if (m == null) return null;
    final month = int.tryParse(m.group(1)!);
    final day = int.tryParse(m.group(2)!);
    if (month == null || day == null || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final today = now ?? DateTime.now();
    final midnight = DateTime(today.year, today.month, today.day);
    var next = DateTime(midnight.year, month, day);
    // A 29 Feb birthday in a non-leap year rolls to 1 March, which is what
    // DateTime(year, 2, 29) already does — no special case needed.
    if (next.isBefore(midnight)) {
      next = DateTime(midnight.year + 1, month, day);
    }
    return next.difference(midnight).inDays;
  }

  factory CustomerModel.fromMap(Map<String, dynamic> map) => CustomerModel(
    id: map['id'] ?? '',
    businessId: map['business_id'] ?? '',
    name: map['name'] ?? '',
    phone: map['phone'] ?? '',
    address: map['address'],
    gstin: map['gstin'],
    stateCode: map['state_code'],
    currentBalancePaise: map['current_balance_paise'] ?? 0,
    creditLimitPaise: map['credit_limit_paise'] ?? 500000,
    syncStatus: map['sync_status'] ?? 'pending',
    isVip: map['is_vip'] == 1 || map['is_vip'] == true,
    birthday: map['birthday']?.toString(),
  );

  CustomerModel copyWith({
    String? name,
    String? phone,
    String? address,
    String? gstin,
    String? stateCode,
    int? currentBalancePaise,
    int? creditLimitPaise,
    String? syncStatus,
    bool? isVip,
    String? birthday,
  }) => CustomerModel(
    id: id,
    businessId: businessId,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    address: address ?? this.address,
    gstin: gstin ?? this.gstin,
    stateCode: stateCode ?? this.stateCode,
    currentBalancePaise: currentBalancePaise ?? this.currentBalancePaise,
    creditLimitPaise: creditLimitPaise ?? this.creditLimitPaise,
    syncStatus: syncStatus ?? this.syncStatus,
    isVip: isVip ?? this.isVip,
    birthday: birthday ?? this.birthday,
  );
}

class CartItemModel {
  final ProductModel product;
  double quantity;
  int unitPricePaise;
  String discountType; // 'flat' | 'percentage'
  double discountValue; // in rupees for flat, or 0..100 for percentage
  /// Free-text dish modifiers / kitchen instructions — "less spicy",
  /// "no onion", "extra cheese". Restaurant-specific (Phase 4, KamaiPlus
  /// Playbook); empty for every other vertical. Printed on the KOT and
  /// shown in the cart so the cashier can confirm it before billing.
  String notes;

  CartItemModel({
    required this.product,
    this.quantity = 1.0,
    int? unitPricePaise,
    this.discountType = 'flat',
    this.discountValue = 0.0,
    double? discountPercent,
    this.notes = '',
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
    // Buying rate FROZEN at the moment of sale. Profit must be computed from
    // what the goods actually cost when they were sold, not from whatever the
    // product's cost price happens to be weeks later — supplier rates move,
    // and re-reading the current cost would silently rewrite history every
    // time a new purchase came in. 0 means "cost not known for this line",
    // which the profit maths treats as uncosted rather than as free stock.
    'cost_price_paise': product.purchasePricePaise,
    'tax_rate': product.taxRate,
    'is_tax_inclusive': product.isTaxInclusive ? 1 : 0,
    'discount_type': discountType,
    'discount_value': discountValue,
    if (notes.trim().isNotEmpty) 'notes': notes.trim(),
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
  final String? customerGstin;
  final String? placeOfSupply;
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
    this.customerGstin,
    this.placeOfSupply,
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
    'customer_gstin': customerGstin,
    'place_of_supply': placeOfSupply,
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
      customerGstin: map['customer_gstin'],
      placeOfSupply: map['place_of_supply'],
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
  bool get isPartiallyRefunded => status.toLowerCase() == 'partially_refunded';

  /// What the customer effectively PAID for the whole of item [index], in
  /// integer paise — tax included, and with this bill's overall discount
  /// apportioned across the lines.
  ///
  /// This is the single source of truth for "how much is this line worth on a
  /// return", used by both the return modal's on-screen total and
  /// `processPartialSalesReturn`'s actual refund, so the two can never
  /// disagree about the money.
  ///
  /// Why it is not just `gross_total_paise`:
  ///  * for a tax-EXCLUSIVE item, `gross_total_paise` is the pre-tax line
  ///    total, but the customer paid tax on top of it (see `processPosBill`);
  ///  * `gross_total_paise` is also before any BILL-level discount, so on a
  ///    discounted bill refunding it raw hands back more than was ever taken.
  ///
  /// Returning every line in full therefore adds up to `totalAmountPaise`,
  /// which is exactly what a full refund (`processSalesReturn`) pays out.
  int lineEffectivePaidPaise(int index) {
    if (index < 0 || index >= items.length) return 0;
    final it = items[index];

    // Line total after any per-item discount. Older rows — and rows written by
    // other code paths — may carry only a unit price, so fall back to that.
    // 'price_paise' / 'selling_price_paise' are legacy spellings kept for
    // bills saved before the current item shape; note that they were ALSO
    // what the return code mistakenly read on every modern bill, where they
    // do not exist at all, which is why every refund came out as zero.
    num lineGross = (it['gross_total_paise'] as num?) ?? 0;
    if (lineGross <= 0) {
      final num unit = (it['unit_price_paise'] as num?) ??
          (it['price_paise'] as num?) ??
          (it['selling_price_paise'] as num?) ??
          0;
      final num qty = (it['quantity'] as num?) ?? (it['qty'] as num?) ?? 0;
      lineGross = unit * qty;
    }
    if (lineGross <= 0) return 0;

    // Add tax for exclusive-tax items, mirroring processPosBill's own maths.
    final double rate = (it['tax_rate'] as num?)?.toDouble() ?? 0.0;
    final bool inclusive = it['is_tax_inclusive'] == 1 || it['is_tax_inclusive'] == true;
    int lineWithTax = lineGross.round();
    if (rate > 0 && !inclusive) {
      final gst = MoneyFormatter.calculateGst(
        grossOrBasePaise: lineWithTax,
        taxRatePercent: rate,
        isInclusive: false,
      );
      lineWithTax = gst['grossTotal'] ?? lineWithTax;
    }

    // Apportion the bill-level discount. Every line summed to `grandTotal`
    // before that discount was applied, and grandTotal is recoverable exactly
    // as totalAmount + discount (see processPosBill).
    final int grandTotal = totalAmountPaise + discountPaise;
    if (discountPaise > 0 && grandTotal > 0) {
      lineWithTax = (lineWithTax * totalAmountPaise / grandTotal).round();
    }
    return lineWithTax < 0 ? 0 : lineWithTax;
  }

  /// Refundable paise for handing back [returnQty] units of item [index].
  int refundPaiseForItem(int index, num returnQty) {
    if (returnQty <= 0 || index < 0 || index >= items.length) return 0;
    final num soldQty = (items[index]['quantity'] as num?) ??
        (items[index]['qty'] as num?) ??
        0;
    if (soldQty <= 0) return 0;

    final int linePaid = lineEffectivePaidPaise(index);
    // Returning the whole line pays back the whole line, with no rounding
    // drift from the proration below.
    if (returnQty >= soldQty) return linePaid;
    return (linePaid * returnQty / soldQty).round();
  }

  /// Total refunded paise calculated from cumulative returned items in items_json.
  int get totalRefundedPaise {
    if (isRefunded) return totalAmountPaise;
    int refunded = 0;
    for (int i = 0; i < items.length; i++) {
      final num retQty = (items[i]['returned_quantity'] as num?) ?? 0;
      refunded += refundPaiseForItem(i, retQty);
    }
    return refunded > totalAmountPaise ? totalAmountPaise : refunded;
  }

  /// Net revenue paise after deducting returned items.
  int get netAmountPaise {
    if (isRefunded) return 0;
    final net = totalAmountPaise - totalRefundedPaise;
    return net > 0 ? net : 0;
  }

  /// Net cash collected from this sale after refunds.
  int get netCashAmountPaise {
    if (isRefunded) return 0;
    if (paymentMethod == 'cash') return netAmountPaise;
    if (paymentMethod == 'split') {
      final splitCash = splitCashPaise;
      if (splitCash <= 0) return 0;
      final remaining = netAmountPaise;
      return splitCash > remaining ? remaining : splitCash;
    }
    return 0;
  }

  /// Net UPI collected from this sale.
  int get netUpiAmountPaise {
    if (isRefunded) return 0;
    if (paymentMethod == 'upi') return netAmountPaise;
    if (paymentMethod == 'split') {
      final splitUpi = splitUpiPaise;
      if (splitUpi <= 0) return 0;
      final remaining = netAmountPaise - netCashAmountPaise;
      return splitUpi > remaining ? (remaining > 0 ? remaining : 0) : splitUpi;
    }
    return 0;
  }

  /// Net Credit due for this sale after returns.
  int get netCreditAmountPaise {
    if (isRefunded) return 0;
    if (paymentMethod == 'credit') return netAmountPaise;
    if (paymentMethod == 'split') {
      final remaining = netAmountPaise - netCashAmountPaise - netUpiAmountPaise;
      return remaining > 0 ? remaining : 0;
    }
    return 0;
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
  final String trialStartedAt;

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
    this.trialStartedAt = '',
  });

  factory StoreProfileModel.empty() => StoreProfileModel();

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

  /// Evaluates whether a 7-day Pro trial is currently active and valid
  bool get isTrialActive {
    if (!isProEffective) return false;
    return proPlan == 'trial' || proPlan == 'referral_trial' || razorpayPaymentId == 'free_trial_7d';
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
    'trial_started_at': trialStartedAt,
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
      trialStartedAt: map['trial_started_at']?.toString() ?? '',
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

/// One physical delivery of a product, tracked separately from
/// [ProductModel]'s own aggregate `stockQuantity` — real FEFO
/// (First-Expiry-First-Out) needs this because a pharmacy can have several
/// deliveries of the SAME medicine on the shelf at once, each with its own
/// expiry date; a single `ProductModel.expiryDate` field can only describe
/// one of them. `ProductModel.stockQuantity`/`expiryDate`/`batchNumber`
/// stay as fast, denormalized summaries (sum of all batches; the
/// soonest-expiring batch's date/number) so the billing screen's product
/// grid never has to query this table per-render — only inward (creating a
/// batch) and billing (deducting from the earliest-expiry batch first) read
/// or write it directly. See `local_database.dart`'s `addProductBatch` /
/// `_deductStockFefo` / `_recomputeProductAggregateFromBatches`.
class ProductBatchModel {
  final String id;
  final String productId;
  final String businessId;
  final String? batchNumber;
  final double quantity;
  final String? expiryDate;
  final int purchasePricePaise;
  final DateTime createdAt;

  ProductBatchModel({
    required this.id,
    required this.productId,
    required this.businessId,
    this.batchNumber,
    required this.quantity,
    this.expiryDate,
    this.purchasePricePaise = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'product_id': productId,
    'business_id': businessId,
    'batch_number': batchNumber,
    'quantity': quantity,
    'expiry_date': expiryDate,
    'purchase_price_paise': purchasePricePaise,
    'created_at': createdAt.toIso8601String(),
  };

  factory ProductBatchModel.fromMap(Map<String, dynamic> map) => ProductBatchModel(
    id: map['id'] ?? '',
    productId: map['product_id'] ?? '',
    businessId: map['business_id'] ?? '',
    batchNumber: map['batch_number'] as String?,
    quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
    expiryDate: map['expiry_date'] as String?,
    purchasePricePaise: (map['purchase_price_paise'] as num?)?.toInt() ?? 0,
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

/// A wholesale purchase / restock order recorded on the Purchases screen.
///
/// This model exists because that screen previously had no persistence at all:
/// orders lived in a plain `List<Map<String, dynamic>>` in widget state,
/// initialised empty and never read from the database. Creating an order only
/// called setState, and "Mark Inward Received" set a string on that Map and
/// showed a success toast reading "marked as Received into Stock!" without
/// touching a single product row. Everything the merchant entered was lost the
/// moment the screen was disposed or the app restarted — which is what the
/// "stock disappears after being added" report was describing.
///
/// [stockAppliedAt] is the double-apply guard: receiving an order adds its lines
/// to inventory exactly once, no matter how many times the button is pressed or
/// how the screen is re-entered.
class PurchaseOrderModel {
  final String id;
  final String businessId;
  final String? invoiceNo;
  final String supplierName;
  final String? supplierPhone;
  final String category;
  final int amountPaise;
  final int duePaise;
  final String paymentStatus;

  /// 'Received' or 'In-Transit'.
  final String status;
  final int itemsCount;

  /// Line items, each {name, qty, unit, rate_paise, total_paise}. Stored as
  /// JSON text in one column, the same convention SaleModel uses for its items.
  final List<Map<String, dynamic>> items;

  final DateTime orderDate;
  final DateTime? expectedDate;

  /// When this order's lines were actually taken into stock. Null means they
  /// have not been.
  final DateTime? stockAppliedAt;

  final String syncStatus;

  PurchaseOrderModel({
    required this.id,
    required this.businessId,
    required this.supplierName,
    this.invoiceNo,
    this.supplierPhone,
    this.category = 'Wholesale Inward',
    this.amountPaise = 0,
    this.duePaise = 0,
    this.paymentStatus = 'Paid (Cash)',
    this.status = 'In-Transit',
    this.itemsCount = 0,
    this.items = const [],
    required this.orderDate,
    this.expectedDate,
    this.stockAppliedAt,
    this.syncStatus = 'pending',
  });

  bool get isReceived => status == 'Received';
  bool get hasStockBeenApplied => stockAppliedAt != null;

  PurchaseOrderModel copyWith({
    String? invoiceNo,
    String? supplierName,
    String? supplierPhone,
    String? category,
    int? amountPaise,
    int? duePaise,
    String? paymentStatus,
    String? status,
    int? itemsCount,
    List<Map<String, dynamic>>? items,
    DateTime? orderDate,
    DateTime? expectedDate,
    DateTime? stockAppliedAt,
    String? syncStatus,
  }) =>
      PurchaseOrderModel(
        id: id,
        businessId: businessId,
        invoiceNo: invoiceNo ?? this.invoiceNo,
        supplierName: supplierName ?? this.supplierName,
        supplierPhone: supplierPhone ?? this.supplierPhone,
        category: category ?? this.category,
        amountPaise: amountPaise ?? this.amountPaise,
        duePaise: duePaise ?? this.duePaise,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        status: status ?? this.status,
        itemsCount: itemsCount ?? this.itemsCount,
        items: items ?? this.items,
        orderDate: orderDate ?? this.orderDate,
        expectedDate: expectedDate ?? this.expectedDate,
        stockAppliedAt: stockAppliedAt ?? this.stockAppliedAt,
        syncStatus: syncStatus ?? this.syncStatus,
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'business_id': businessId,
    'invoice_no': invoiceNo,
    'supplier_name': supplierName,
    'supplier_phone': supplierPhone,
    'category': category,
    'amount_paise': amountPaise,
    'due_paise': duePaise,
    'payment_status': paymentStatus,
    'status': status,
    'items_count': itemsCount,
    'items_json': jsonEncode(items),
    'order_date': orderDate.toIso8601String(),
    'expected_date': expectedDate?.toIso8601String(),
    'stock_applied_at': stockAppliedAt?.toIso8601String(),
    'sync_status': syncStatus,
  };

  factory PurchaseOrderModel.fromMap(Map<String, dynamic> map) {
    List<Map<String, dynamic>> parsedItems = [];
    try {
      final raw = map['items_json'];
      if (raw != null && raw.toString().isNotEmpty) {
        parsedItems = List<Map<String, dynamic>>.from(jsonDecode(raw));
      }
    } catch (_) {}

    return PurchaseOrderModel(
      id: map['id'] ?? '',
      businessId: map['business_id'] ?? '',
      invoiceNo: map['invoice_no'],
      supplierName: map['supplier_name'] ?? '',
      supplierPhone: map['supplier_phone'],
      category: map['category'] ?? 'Wholesale Inward',
      amountPaise: map['amount_paise'] ?? 0,
      duePaise: map['due_paise'] ?? 0,
      paymentStatus: map['payment_status'] ?? 'Paid (Cash)',
      status: map['status'] ?? 'In-Transit',
      itemsCount: map['items_count'] ?? 0,
      items: parsedItems,
      orderDate: DateTime.tryParse(map['order_date'] ?? '') ?? DateTime.now(),
      expectedDate: map['expected_date'] != null
          ? DateTime.tryParse(map['expected_date'])
          : null,
      stockAppliedAt: map['stock_applied_at'] != null
          ? DateTime.tryParse(map['stock_applied_at'])
          : null,
      syncStatus: map['sync_status'] ?? 'pending',
    );
  }
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


/// Real, cost-based profit figures for a single day.
///
/// Deliberately reports how much of the day's revenue it could actually cost
/// (`costedRevenuePaise`) alongside how much it could not (`uncostedRevenuePaise`),
/// so the dashboard can say "partial" instead of presenting an incomplete
/// margin as if it were the whole picture.
class DayProfitSummary {
  /// Revenue minus cost of goods, for lines with a known buying rate only.
  final int grossMarginPaise;

  /// [grossMarginPaise] minus the day's logged expenses.
  final int netProfitPaise;

  /// Revenue from lines that had a known buying rate.
  final int costedRevenuePaise;

  /// Revenue from lines with no buying rate on record — excluded from margin.
  final int uncostedRevenuePaise;

  /// How many sold lines had no buying rate on record.
  final int uncostedLineCount;

  final int expensesPaise;

  const DayProfitSummary({
    required this.grossMarginPaise,
    required this.netProfitPaise,
    required this.costedRevenuePaise,
    required this.uncostedRevenuePaise,
    required this.uncostedLineCount,
    required this.expensesPaise,
  });

  /// True when at least one sold line had no buying rate, i.e. the margin
  /// shown is computed over only part of the day's sales.
  bool get isPartial => uncostedLineCount > 0;

  /// Share of the day's revenue the margin actually covers, 0.0 to 1.0.
  double get costCoverage {
    final total = costedRevenuePaise + uncostedRevenuePaise;
    if (total <= 0) return 1.0;
    return costedRevenuePaise / total;
  }
}
