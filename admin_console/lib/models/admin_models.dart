/// Read models for the KamaiPlus Admin Console.
///
/// These deliberately do NOT mirror the mobile app's `ProductModel`/
/// `SaleModel`/etc. 1:1 — those are shaped around the local SQLite schema.
/// The admin console instead reads the root-level `sales`/`products`/
/// `customers` Firestore collections the mobile app dual-syncs into
/// specifically "for Web Admin Portal" (see firestore_sync_service.dart),
/// which use a different, wider field-name convention (several aliases per
/// value, e.g. both `total_amount_paise` and `grand_total`) — each `fromMap`
/// below tries every alias actually seen in that sync code, oldest/most
/// specific first, so a field added or renamed in one place doesn't
/// silently produce a zero here.
library;

int _asInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

double _asDouble(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

String _asString(dynamic v, [String fallback = '']) => v?.toString() ?? fallback;

bool _asBool(dynamic v) => v == true || v == 1 || v == 'true';

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  if (v is String) return DateTime.tryParse(v);
  // Firestore Timestamp (from cloud_firestore) exposes toDate().
  try {
    return (v as dynamic).toDate() as DateTime;
  } catch (_) {
    return null;
  }
}

class AdminBusiness {
  final String id;
  final String name;
  final String ownerName;
  final String ownerUid;
  final String phone;
  final String email;
  final String businessType;
  final String category;
  final String address;
  final String gstin;
  final bool isPro;
  final String proPlan;
  final DateTime? proExpiry;
  final int totalSalesCount;
  final int totalRevenuePaise;
  final DateTime? lastSaleAt;
  final DateTime? lastSyncedAt;
  /// The coupon code used at Pro checkout, if any — written by the mobile
  /// app's razorpay_service.dart onto this same doc at purchase time.
  final String? couponCodeUsed;

  const AdminBusiness({
    required this.id,
    required this.name,
    required this.ownerName,
    required this.ownerUid,
    required this.phone,
    required this.email,
    required this.businessType,
    required this.category,
    required this.address,
    required this.gstin,
    required this.isPro,
    required this.proPlan,
    required this.proExpiry,
    required this.totalSalesCount,
    required this.totalRevenuePaise,
    required this.lastSaleAt,
    required this.lastSyncedAt,
    this.couponCodeUsed,
  });

  factory AdminBusiness.fromMap(String id, Map<String, dynamic> m) {
    final isProCloud = _asBool(m['is_pro']) ||
        m['subscription_tier'] == 'pro' ||
        m['subscription_tier'] == 'annual' ||
        m['subscription_tier'] == 'monthly';
    final expiryStr = m['pro_expiry'] ?? m['subscription_expires_at'] ?? m['subscription_valid_until'];
    return AdminBusiness(
      id: id,
      name: _asString(m['store_name'] ?? m['business_name'] ?? m['shop_name'] ?? m['name'], 'Unnamed Store'),
      ownerName: _asString(m['owner_name']),
      ownerUid: _asString(m['owner_uid']),
      phone: _asString(m['phone']),
      email: _asString(m['email']),
      businessType: _asString(m['business_type'], 'grocery'),
      category: _asString(m['category']),
      address: _asString(m['address']),
      gstin: _asString(m['gstin']),
      isPro: isProCloud,
      proPlan: _asString(m['pro_plan'] ?? m['subscription_tier']),
      proExpiry: _asDate(expiryStr),
      totalSalesCount: _asInt(m['total_sales_count']),
      totalRevenuePaise: _asInt(m['total_revenue_paise']),
      lastSaleAt: _asDate(m['last_sale_at']),
      lastSyncedAt: _asDate(m['last_synced_at']),
      couponCodeUsed: m['coupon_code_used'] as String?,
    );
  }

  bool get isProExpired => proExpiry != null && DateTime.now().isAfter(proExpiry!);
  bool get isProEffective => isPro && !isProExpired;
}

class AdminSale {
  final String id;
  final String businessId;
  final String invoiceNumber;
  final String customerName;
  final int totalAmountPaise;
  final String paymentMethod;
  final String status;
  final DateTime? createdAt;
  final List<dynamic> items;

  const AdminSale({
    required this.id,
    required this.businessId,
    required this.invoiceNumber,
    required this.customerName,
    required this.totalAmountPaise,
    required this.paymentMethod,
    required this.status,
    required this.createdAt,
    required this.items,
  });

  factory AdminSale.fromMap(String id, Map<String, dynamic> m) {
    return AdminSale(
      id: id,
      businessId: _asString(m['business_id']),
      invoiceNumber: _asString(m['invoice_number'], id),
      customerName: _asString(m['customer_name'], 'Cash Customer'),
      totalAmountPaise: _asInt(m['total_amount_paise'] ?? m['grand_total']),
      paymentMethod: _asString(m['payment_method'], 'cash'),
      status: _asString(m['status'], 'completed'),
      createdAt: _asDate(m['created_at']),
      items: (m['items'] as List?) ?? const [],
    );
  }
}

class AdminProduct {
  final String id;
  final String businessId;
  final String name;
  final String? barcode;
  final int sellingPricePaise;
  final double stockQuantity;
  final String unit;

  const AdminProduct({
    required this.id,
    required this.businessId,
    required this.name,
    required this.barcode,
    required this.sellingPricePaise,
    required this.stockQuantity,
    required this.unit,
  });

  factory AdminProduct.fromMap(String id, Map<String, dynamic> m) {
    return AdminProduct(
      id: id,
      businessId: _asString(m['business_id']),
      name: _asString(m['name'], 'Unnamed item'),
      barcode: m['barcode']?.toString(),
      sellingPricePaise: _asInt(m['selling_price_paise'] ?? m['selling_price']),
      stockQuantity: _asDouble(m['stock_quantity'] ?? m['current_stock']),
      unit: _asString(m['unit'], 'pcs'),
    );
  }

  bool get isLowStock => stockQuantity < 5 && stockQuantity < 99990;
}

class AdminCustomer {
  final String id;
  final String businessId;
  final String name;
  final String phone;
  final int currentBalancePaise;

  const AdminCustomer({
    required this.id,
    required this.businessId,
    required this.name,
    required this.phone,
    required this.currentBalancePaise,
  });

  factory AdminCustomer.fromMap(String id, Map<String, dynamic> m) {
    return AdminCustomer(
      id: id,
      businessId: _asString(m['business_id']),
      name: _asString(m['name'], 'Unnamed customer'),
      phone: _asString(m['phone']),
      currentBalancePaise: _asInt(m['current_balance_paise'] ?? m['current_balance']),
    );
  }
}

class AdminCoupon {
  final String code;
  final bool active;
  final double? discountPercent;
  final int? flatOffPaise;
  final DateTime? validTill;

  const AdminCoupon({
    required this.code,
    required this.active,
    required this.discountPercent,
    required this.flatOffPaise,
    required this.validTill,
  });

  factory AdminCoupon.fromMap(String code, Map<String, dynamic> m) {
    return AdminCoupon(
      code: code,
      active: _asBool(m['active']),
      discountPercent: m['discount_percent'] != null ? _asDouble(m['discount_percent']) : null,
      flatOffPaise: m['flat_off_paise'] != null ? _asInt(m['flat_off_paise']) : null,
      validTill: _asDate(m['valid_till']),
    );
  }

  Map<String, dynamic> toMap() => {
        'active': active,
        if (discountPercent != null) 'discount_percent': discountPercent,
        if (flatOffPaise != null) 'flat_off_paise': flatOffPaise,
        if (validTill != null) 'valid_till': validTill!.toIso8601String(),
      };

  bool get isExpired => validTill != null && DateTime.now().isAfter(validTill!);
}
