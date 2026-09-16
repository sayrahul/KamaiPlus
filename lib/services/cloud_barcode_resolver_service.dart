import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/database/local_database.dart';
import '../models/models.dart';

/// Hybrid Cloud Barcode Resolver Service (Petpooja / Vyapar Architecture).
///
/// Resolution ladder, fastest tier first — the first tier that answers wins:
///
///  0. In-memory cache for this app session (<0.1ms).
///  1. Indexed local SQLite Master Catalog (<2ms).
///  2. Curated offline Indian retail / pharmacy dictionary (<1ms).
///  3. Open* Facts family, all five endpoints queried in PARALLEL — Food
///     (India + World), Beauty, Products (general non-food merchandise) and
///     Pet Food. Free, no API key.
///  4. UPCitemdb trial endpoint — general merchandise (stationery, hardware,
///     electronics, apparel) that the Facts family simply does not index.
///     Free, no API key, IP-rate-limited, so it is deliberately Tier 4.
///  5. Google Books, for ISBN-13 barcodes (978/979 prefix) — book &
///     stationery shops.
///
/// A barcode that no tier can resolve is remembered in a short-lived negative
/// cache so a cashier rescanning an unknown item does not pay the full
/// network round-trip (and the counter does not stall) over and over.
///
/// **Vertical tagging rule.** The offline dictionary (tier 2) is curated
/// seed data, so it keeps its strict vertical filter — a pharmacy must never
/// be handed a grocery seed row. Anything resolved from the *internet*
/// (tiers 3-5) is tagged with the scanning store's OWN active vertical
/// instead: the merchant physically scanned that item at their own counter,
/// so it belongs to their shop by definition, and tagging it any other way
/// would make the product invisible in their own catalog right after they
/// billed it (the exact cross-vertical disappearing-stock class of bug
/// documented in DEVELOPMENT_LOG.md).
class CloudBarcodeResolverService {
  CloudBarcodeResolverService._();
  static final CloudBarcodeResolverService instance = CloudBarcodeResolverService._();

  static const Duration _timeout = Duration(milliseconds: 2800);
  static const Duration _negativeCacheTtl = Duration(hours: 6);

  /// Session caches. Positive hits are also persisted to SQLite; this map
  /// just avoids even that 2ms round-trip during rapid-fire gun scanning.
  final Map<String, MasterProductModel> _memoryCache = {};
  final Map<String, DateTime> _notFoundAt = {};

  /// Open* Facts family — identical API shape, so one parser handles all.
  static const List<String> _factsHosts = [
    'https://in.openfoodfacts.org',
    'https://world.openfoodfacts.org',
    'https://world.openbeautyfacts.org',
    'https://world.openproductsfacts.org',
    'https://world.openpetfoodfacts.org',
  ];

  static const String _factsFields =
      'product_name,product_name_en,generic_name,generic_name_en,brands,'
      'categories,categories_tags,quantity,product_quantity,product_quantity_unit,serving_size';

  /// Resolves a barcode from local catalog, curated dictionary or the
  /// internet. Returns `null` when nothing anywhere recognises it.
  ///
  /// [businessType] is the store's active vertical. Callers should always
  /// pass it — it both filters the curated seed dictionary and decides how a
  /// newly-resolved online product gets tagged.
  Future<MasterProductModel?> resolveBarcode(
    String barcode, {
    String? businessType,
  }) async {
    final cleanBarcode = normalizeBarcode(barcode);
    if (cleanBarcode == null) return null;

    final targetVertical = businessType?.trim().toLowerCase();

    // 0. Session memory cache.
    final cached = _memoryCache[cleanBarcode];
    if (cached != null) return cached;

    // 1. Instant Local SQLite Lookup (<2ms)
    final localMatch = await LocalDatabase.instance.findMasterProductByBarcode(
      cleanBarcode,
      businessType: targetVertical,
    );
    if (localMatch != null) {
      _memoryCache[cleanBarcode] = localMatch;
      return localMatch;
    }

    // 2. Curated offline Indian retail & pharmacy dictionary (<1ms).
    final offlineMatch = _lookupFastOfflineDictionary(cleanBarcode, targetVertical: targetVertical);
    if (offlineMatch != null) {
      await LocalDatabase.instance.insertMasterProduct(offlineMatch);
      _memoryCache[cleanBarcode] = offlineMatch;
      return offlineMatch;
    }

    // Negative cache — an unknown barcode rescanned within the TTL fails
    // instantly instead of blocking the counter on another network round-trip.
    final missedAt = _notFoundAt[cleanBarcode];
    if (missedAt != null && DateTime.now().difference(missedAt) < _negativeCacheTtl) {
      return null;
    }

    _ResolvedOnlineProduct? online;
    try {
      // 3. Open* Facts family, all five in parallel.
      online = await _queryFactsFamily(cleanBarcode);

      // 4. UPCitemdb — general merchandise the Facts family does not index.
      online ??= await _queryUpcItemDb(cleanBarcode);

      // 5. Google Books for ISBN-13 (book & stationery counters).
      if (online == null && (cleanBarcode.startsWith('978') || cleanBarcode.startsWith('979'))) {
        online = await _queryGoogleBooks(cleanBarcode);
      }
    } catch (_) {
      online = null;
    }

    if (online == null) {
      _notFoundAt[cleanBarcode] = DateTime.now();
      return null;
    }

    final resolved = _toMasterProduct(
      cleanBarcode,
      online,
      targetVertical: targetVertical,
    );

    // 6. Cache into Local SQLite Master Catalog for future instant scans (<2ms)
    await LocalDatabase.instance.insertMasterProduct(resolved);
    _memoryCache[cleanBarcode] = resolved;
    return resolved;
  }

  /// Validates and normalises a raw scan. Retail barcodes are EAN-8 (8),
  /// UPC-E (8), UPC-A (12), EAN-13 (13) or ITF-14 (14) digits. Anything
  /// non-numeric or outside that range is a misread or an internal SKU
  /// label, and no online repository will ever know it — returning null
  /// here saves a pointless 3-second network stall at the counter.
  static String? normalizeBarcode(String raw) {
    final digits = raw.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 8 || digits.length > 14) return null;
    return digits;
  }

  // ===========================================================================
  // TIER 3 — Open* Facts family
  // ===========================================================================

  Future<_ResolvedOnlineProduct?> _queryFactsFamily(String barcode) async {
    // All five hosts in parallel — the slowest one bounds the wait, not the
    // sum, so a cashier never stands there for five sequential timeouts.
    // `_fetchJson` already swallows its own failures, so a dead host simply
    // contributes a null instead of failing the whole batch.
    final results = await Future.wait<_ResolvedOnlineProduct?>(
      _factsHosts.map((host) async {
        final json = await _fetchJson('$host/api/v2/product/$barcode.json?fields=$_factsFields');
        if (json == null) return null;
        return _parseFactsProduct(json);
      }),
    );
    // Host order is priority order: India-localised names win over World.
    for (final r in results) {
      if (r != null) return r;
    }
    return null;
  }

  _ResolvedOnlineProduct? _parseFactsProduct(Map<String, dynamic> data) {
    if (data['status'] != 1) return null;
    final product = data['product'];
    if (product is! Map<String, dynamic>) return null;

    final name = _firstNonEmpty([
      product['product_name_en'],
      product['product_name'],
      product['generic_name_en'],
      product['generic_name'],
    ]);
    if (name == null) return null;

    return _ResolvedOnlineProduct(
      name: name,
      brand: _firstNonEmpty([product['brands']])?.split(',').first.trim(),
      rawCategory: _firstNonEmpty([product['categories']]) ?? '',
      packSize: _firstNonEmpty([product['quantity'], product['serving_size']]),
      source: 'Open Facts',
    );
  }

  // ===========================================================================
  // TIER 4 — UPCitemdb (general merchandise)
  // ===========================================================================

  Future<_ResolvedOnlineProduct?> _queryUpcItemDb(String barcode) async {
    final json = await _fetchJson('https://api.upcitemdb.com/prod/trial/lookup?upc=$barcode');
    if (json == null) return null;
    final items = json['items'];
    if (items is! List || items.isEmpty) return null;
    final item = items.first;
    if (item is! Map<String, dynamic>) return null;

    final name = _firstNonEmpty([item['title']]);
    if (name == null) return null;

    return _ResolvedOnlineProduct(
      name: name,
      brand: _firstNonEmpty([item['brand'], item['manufacturer']]),
      rawCategory: _firstNonEmpty([item['category']]) ?? '',
      packSize: _firstNonEmpty([item['size'], item['weight']]),
      source: 'UPCitemdb',
    );
  }

  // ===========================================================================
  // TIER 5 — Google Books (ISBN-13)
  // ===========================================================================

  Future<_ResolvedOnlineProduct?> _queryGoogleBooks(String isbn) async {
    final json = await _fetchJson('https://www.googleapis.com/books/v1/volumes?q=isbn:$isbn');
    if (json == null) return null;
    final items = json['items'];
    if (items is! List || items.isEmpty) return null;
    final info = (items.first as Map<String, dynamic>)['volumeInfo'];
    if (info is! Map<String, dynamic>) return null;

    final title = _firstNonEmpty([info['title']]);
    if (title == null) return null;
    final subtitle = _firstNonEmpty([info['subtitle']]);
    final authors = info['authors'];
    final author = (authors is List && authors.isNotEmpty) ? authors.first.toString().trim() : null;

    return _ResolvedOnlineProduct(
      name: subtitle == null ? title : '$title: $subtitle',
      brand: _firstNonEmpty([info['publisher']]) ?? author,
      rawCategory: 'Books & Stationery',
      packSize: null,
      source: 'Google Books',
    );
  }

  // ===========================================================================
  // NORMALISATION — turn a messy online record into a clean catalog row
  // ===========================================================================

  MasterProductModel _toMasterProduct(
    String barcode,
    _ResolvedOnlineProduct online, {
    String? targetVertical,
  }) {
    final vertical = (targetVertical != null && targetVertical.isNotEmpty) ? targetVertical : 'grocery';
    final displayName = buildDisplayName(
      rawName: online.name,
      brand: online.brand,
      packSize: online.packSize,
    );

    return MasterProductModel(
      barcode: barcode,
      name: displayName,
      category: mapToVerticalCategory(online.rawCategory, displayName, vertical),
      // Online barcode repositories carry no Indian MRP. Leaving these at 0
      // is deliberate and load-bearing: callers MUST treat a 0 price as
      // "merchant has to enter it" and never silently bill the item at ₹0.
      mrpPaise: 0,
      sellingPricePaise: 0,
      unit: inferUnit(packSize: online.packSize, name: displayName, vertical: vertical),
      taxRate: 0.0,
      businessType: vertical,
      brand: (online.brand != null && online.brand!.isNotEmpty) ? online.brand : null,
    );
  }

  /// Builds a counter-readable title: `Brand Product (PackSize)`, without
  /// repeating the brand or the size when the raw name already contains them.
  static String buildDisplayName({
    required String rawName,
    String? brand,
    String? packSize,
  }) {
    var name = rawName.replaceAll(RegExp(r'\s+'), ' ').trim();
    name = name.replaceAll(RegExp(r'^[,\-–—:;]+|[,\-–—:;]+$'), '').trim();

    final b = brand?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (b != null && b.isNotEmpty && !name.toLowerCase().contains(b.toLowerCase())) {
      name = '$b $name';
    }

    final size = packSize?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (size != null && size.isNotEmpty && !name.toLowerCase().contains(size.toLowerCase())) {
      name = '$name ($size)';
    }

    // Counter product cards are narrow; an essay of a title helps nobody.
    if (name.length > 90) name = '${name.substring(0, 87).trimRight()}...';
    return name;
  }

  /// Canonical app units only (see `BusinessVerticals.unitDisplayLabels`).
  ///
  /// The previous implementation used bare `text.contains(' g')`, which
  /// matched the space-g inside names like "Amul **G**old" or "Britannia Good
  /// Day" and silently set those to grams. Pack size is now parsed with an
  /// anchored numeric regex, and the name is only consulted as a fallback
  /// using whole-word matching.
  static String inferUnit({String? packSize, String? name, String vertical = 'grocery'}) {
    final size = packSize?.toLowerCase().trim() ?? '';
    if (size.isNotEmpty) {
      final m = RegExp(r'(\d+(?:[.,]\d+)?)\s*(kgs?|kilograms?|gms?|grams?|g|mls?|millilitres?|ltrs?|litres?|liters?|l)\b')
          .firstMatch(size);
      if (m != null) {
        switch (_unitFamily(m.group(2)!)) {
          case 'kg':
            return 'kg';
          case 'gram':
            return 'gram';
          case 'litre':
            return 'litre';
          case 'ml':
            return 'ml';
        }
      }
      if (RegExp(r'\b(strips?|tablets?|tabs?|capsules?)\b').hasMatch(size)) return 'strip';
      if (RegExp(r'\b(bottles?)\b').hasMatch(size)) return 'btl';
      if (RegExp(r'\b(packs?|packets?|sachets?|pouch(es)?|bags?)\b').hasMatch(size)) return 'packet';
      if (RegExp(r'\b(boxe?s?|cartons?)\b').hasMatch(size)) return 'box';
    }

    final n = name?.toLowerCase() ?? '';
    if (RegExp(r'\b(strip|tablets?|tabs?|capsules?)\b').hasMatch(n)) return 'strip';
    if (RegExp(r'\b(syrup|bottle|liquid|shampoo|oil)\b').hasMatch(n)) return 'btl';
    if (RegExp(r'\b(packe?t|sachet|pouch)\b').hasMatch(n)) return 'packet';
    if (RegExp(r'\b(box|carton)\b').hasMatch(n)) return 'box';

    // Vertical-appropriate default rather than a blanket "pcs".
    switch (vertical) {
      case 'pharmacy':
        return 'strip';
      case 'restaurant':
        return 'plate';
      default:
        return 'piece';
    }
  }

  static String _unitFamily(String token) {
    final t = token.toLowerCase();
    if (t.startsWith('kg') || t.startsWith('kilo')) return 'kg';
    if (t == 'g' || t.startsWith('gm') || t.startsWith('gram')) return 'gram';
    if (t.startsWith('ml') || t.startsWith('milli')) return 'ml';
    return 'litre';
  }

  /// Maps a foreign taxonomy string onto one of the merchant's OWN
  /// vertical categories.
  ///
  /// Open Food Facts returns its English taxonomy ("Plant-based foods and
  /// beverages, Snacks, Cereals..."), and the old code took the first comma
  /// segment verbatim. Every caller then auto-created that string as a real
  /// category row, so a few scans polluted a kirana's catalog with categories
  /// no Indian shopkeeper would ever write. Unrecognised input now falls back
  /// to 'General', which the callers deliberately skip rather than create.
  static String mapToVerticalCategory(String rawCategory, String productName, String vertical) {
    final haystack = '$rawCategory $productName'
        .toLowerCase()
        .replaceAll(RegExp(r'\b[a-z]{2}:'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ');

    bool has(List<String> keywords) => keywords.any((k) => haystack.contains(k));

    switch (vertical) {
      case 'pharmacy':
        if (has(['tablet', 'capsule', 'paracetamol', 'antibiotic'])) return 'Tablets & Capsules';
        if (has(['syrup', 'suspension', 'cough', 'expectorant'])) return 'Syrups & Suspensions';
        if (has(['injection', 'vial', 'ampoule'])) return 'Injections & Vials';
        if (has(['ointment', 'cream', 'gel', 'balm', 'lotion'])) return 'Ointments & Creams';
        if (has(['bandage', 'antiseptic', 'first aid', 'dressing', 'gauze'])) return 'First Aid & Bandages';
        return 'General';

      case 'clothing':
        if (has(['shirt', 't shirt', 'tshirt', 'tee'])) return 'Men Shirts & T-Shirts';
        if (has(['kurti', 'saree', 'sari', 'salwar', 'lehenga'])) return 'Women Kurtis & Sarees';
        if (has(['jean', 'trouser', 'pant', 'chino'])) return 'Jeans & Trousers';
        if (has(['kid', 'child', 'infant', 'baby'])) return 'Kids Wear';
        if (has(['shoe', 'footwear', 'sandal', 'slipper', 'sneaker'])) return 'Shoes & Footwear';
        if (has(['innerwear', 'vest', 'brief', 'sock', 'belt', 'wallet'])) return 'Innerwear & Accessories';
        return 'General';

      case 'hardware':
        if (has(['pipe', 'pvc', 'fitting', 'elbow'])) return 'Pipes & PVC Fittings';
        if (has(['paint', 'primer', 'enamel', 'putty'])) return 'Paints & Wall Primer';
        if (has(['wire', 'switch', 'mcb', 'socket', 'cable'])) return 'Wires, Switches & MCB';
        if (has(['tool', 'drill', 'plier', 'hammer', 'spanner', 'wrench'])) return 'Hand & Power Tools';
        if (has(['screw', 'nail', 'bolt', 'nut', 'fastener', 'washer'])) return 'Screws, Nails & Fasteners';
        if (has(['tap', 'faucet', 'sanitary', 'basin', 'shower'])) return 'Sanitary & Water Taps';
        if (has(['cement', 'adhesive', 'glue', 'sealant'])) return 'Cement & Adhesives';
        if (has(['bulb', 'led', 'batten', 'tube light', 'lamp'])) return 'LED Bulbs & Battens';
        return 'General';

      case 'restaurant':
        if (has(['tea', 'coffee', 'chai', 'beverage'])) return 'Hot & Cold Beverages';
        if (has(['water', 'soft drink', 'soda', 'cola', 'juice'])) return 'Packaged Drinks & Water';
        if (has(['starter', 'snack', 'namkeen', 'chips', 'pakoda'])) return 'Starters & Snacks';
        if (has(['curry', 'gravy', 'paneer', 'dal', 'masala'])) return 'Main Course (Curries)';
        if (has(['roti', 'naan', 'paratha', 'rice', 'biryani'])) return 'Roti, Naan & Rice';
        if (has(['pizza', 'burger', 'sandwich', 'roll', 'fries'])) return 'Fast Food & Pizzas';
        if (has(['dessert', 'sweet', 'ice cream', 'cake', 'halwa'])) return 'Desserts & Sweets';
        return 'General';

      default: // grocery / kirana
        if (has(['atta', 'flour', 'rice', 'dal', 'pulse', 'lentil', 'wheat', 'basmati'])) {
          return 'Atta, Rice & Dal';
        }
        if (has(['spice', 'masala', 'oil', 'ghee', 'turmeric', 'chilli', 'salt', 'sugar'])) {
          return 'Spices & Cooking Oil';
        }
        if (has(['dairy', 'milk', 'butter', 'cheese', 'paneer', 'curd', 'bread', 'egg', 'yoghurt', 'yogurt'])) {
          return 'Dairy, Bread & Eggs';
        }
        if (has(['biscuit', 'snack', 'chips', 'namkeen', 'chocolate', 'noodle', 'beverage', 'juice', 'cookie', 'wafer'])) {
          return 'Biscuits & Snacks';
        }
        if (has(['soap', 'detergent', 'shampoo', 'cleaner', 'toothpaste', 'handwash', 'sanitizer', 'washing'])) {
          return 'Soaps & Detergents';
        }
        if (has(['agarbatti', 'incense', 'pooja', 'puja', 'camphor', 'diya'])) {
          return 'Pooja & Agarbatti';
        }
        return 'General';
    }
  }

  // ===========================================================================
  // CURATED OFFLINE DICTIONARY (unchanged seed data — strict vertical filter)
  // ===========================================================================

  static const Map<String, Map<String, dynamic>> _kFastIndianDict = {
    '8901030383701': {'name': 'Aashirvaad Shudh Chakki Atta 5kg', 'cat': 'Atta, Rice & Dal', 'unit': 'packet', 'mrp': 26000, 'sell': 24500, 'type': 'grocery'},
    '8901262010054': {'name': 'Amul Butter Pasteurised 500g', 'cat': 'Dairy, Bread & Eggs', 'unit': 'packet', 'mrp': 28500, 'sell': 27500, 'type': 'grocery'},
    '8904043901007': {'name': 'Tata Salt Vacuum Evaporated 1kg', 'cat': 'Spices & Cooking Oil', 'unit': 'packet', 'mrp': 3000, 'sell': 2800, 'type': 'grocery'},
    '8901058852854': {'name': 'Maggi 2-Minute Masala Noodles 70g', 'cat': 'Biscuits & Snacks', 'unit': 'packet', 'mrp': 1400, 'sell': 1400, 'type': 'grocery'},
    '8901030383702': {'name': 'Dolo 650mg Paracetamol Tablets (15 Tabs)', 'cat': 'Tablets & Capsules', 'unit': 'strip', 'mrp': 3500, 'sell': 3200, 'type': 'pharmacy'},
    '8901117001019': {'name': 'Crocin Advance 500mg Fast Relief (15 Tabs)', 'cat': 'Tablets & Capsules', 'unit': 'strip', 'mrp': 2500, 'sell': 2300, 'type': 'pharmacy'},
    '8901117001026': {'name': 'Calpol 650 Paracetamol Tablets (15 Tabs)', 'cat': 'Tablets & Capsules', 'unit': 'strip', 'mrp': 3400, 'sell': 3000, 'type': 'pharmacy'},
    '8901117001033': {'name': 'Combiflam Pain Relief Tablets (20 Tabs)', 'cat': 'Tablets & Capsules', 'unit': 'strip', 'mrp': 4800, 'sell': 4400, 'type': 'pharmacy'},
    '8901117001040': {'name': 'Cetirizine 10mg Anti-Allergy (10 Tabs)', 'cat': 'Tablets & Capsules', 'unit': 'strip', 'mrp': 2200, 'sell': 2000, 'type': 'pharmacy'},
    '8901117001057': {'name': 'Pantocid 40mg Acidity Tablets (15 Tabs)', 'cat': 'Tablets & Capsules', 'unit': 'strip', 'mrp': 16500, 'sell': 15000, 'type': 'pharmacy'},
    '8901117001064': {'name': 'Azithromycin 500mg Tablets (3 Tabs)', 'cat': 'Tablets & Capsules', 'unit': 'strip', 'mrp': 7500, 'sell': 7000, 'type': 'pharmacy'},
    '8901117001071': {'name': 'Digene Acidity & Gas Relief Tablets (15 Tabs)', 'cat': 'Tablets & Capsules', 'unit': 'strip', 'mrp': 3200, 'sell': 3000, 'type': 'pharmacy'},
    '8901117001088': {'name': 'Eno Fruit Salt Regular Sachet 5g', 'cat': 'Generic Medicines', 'unit': 'packet', 'mrp': 1000, 'sell': 1000, 'type': 'pharmacy'},
    '8901117001095': {'name': 'Vicks VapoRub Balm 25ml', 'cat': 'Ointments & Creams', 'unit': 'box', 'mrp': 8000, 'sell': 7500, 'type': 'pharmacy'},
    '8901117001101': {'name': 'Betadine 10% Antiseptic Ointment 20g', 'cat': 'Ointments & Creams', 'unit': 'piece', 'mrp': 7500, 'sell': 7000, 'type': 'pharmacy'},
    '8901117001118': {'name': 'Volini Pain Relief Gel 30g', 'cat': 'Ointments & Creams', 'unit': 'piece', 'mrp': 9500, 'sell': 9000, 'type': 'pharmacy'},
    '8901117001125': {'name': 'Moov Fast Pain Relief Ointment 25g', 'cat': 'Ointments & Creams', 'unit': 'piece', 'mrp': 8500, 'sell': 8000, 'type': 'pharmacy'},
    '8901117001132': {'name': 'Boroline Antiseptic Ayurvedic Cream 20g', 'cat': 'Ointments & Creams', 'unit': 'piece', 'mrp': 4500, 'sell': 4200, 'type': 'pharmacy'},
    '8901117001149': {'name': 'Band-Aid Washproof Medicated Strips (Box 100)', 'cat': 'First Aid & Bandages', 'unit': 'box', 'mrp': 25000, 'sell': 23000, 'type': 'pharmacy'},
    '8901117001156': {'name': 'Savlon Antiseptic Liquid 200ml', 'cat': 'First Aid & Bandages', 'unit': 'btl', 'mrp': 8500, 'sell': 8000, 'type': 'both'},
    '8901117001163': {'name': 'Dettol Antiseptic Liquid 250ml', 'cat': 'First Aid & Bandages', 'unit': 'btl', 'mrp': 14000, 'sell': 13000, 'type': 'both'},
    '8901117001170': {'name': 'Cough Syrup Benadryl DR 100ml', 'cat': 'Syrups & Suspensions', 'unit': 'btl', 'mrp': 11500, 'sell': 10500, 'type': 'pharmacy'},
    '8901117001187': {'name': 'Ascoril LS Expectorant Cough Syrup 100ml', 'cat': 'Syrups & Suspensions', 'unit': 'btl', 'mrp': 11800, 'sell': 11000, 'type': 'pharmacy'},
  };

  MasterProductModel? _lookupFastOfflineDictionary(String barcode, {String? targetVertical}) {
    final entry = _kFastIndianDict[barcode];
    if (entry == null) return null;
    final itemType = (entry['type'] as String?)?.toLowerCase() ?? 'grocery';
    if (targetVertical != null && targetVertical.isNotEmpty) {
      if (itemType != targetVertical.toLowerCase() && itemType != 'both') {
        return null;
      }
    }
    return MasterProductModel(
      barcode: barcode,
      name: entry['name'] as String,
      category: entry['cat'] as String,
      unit: entry['unit'] as String,
      mrpPaise: (entry['mrp'] as num).toInt(),
      sellingPricePaise: (entry['sell'] as num).toInt(),
      taxRate: 0.0,
      businessType: entry['type'] as String,
    );
  }

  // ===========================================================================
  // HTTP
  // ===========================================================================

  Future<Map<String, dynamic>?> _fetchJson(String url) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = _timeout;

      final request = await client.getUrl(Uri.parse(url)).timeout(_timeout);
      request.headers.set('User-Agent', 'KamaiPlus-POS/4.21 (android-retail-counter)');
      request.headers.set('Accept', 'application/json');

      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) return null;

      final body = await response.transform(utf8.decoder).join().timeout(_timeout);
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  static String? _firstNonEmpty(List<dynamic> candidates) {
    for (final c in candidates) {
      final s = c?.toString().trim();
      if (s != null && s.isNotEmpty && s.toLowerCase() != 'null') return s;
    }
    return null;
  }
}

/// One raw hit from an online repository, before normalisation.
class _ResolvedOnlineProduct {
  final String name;
  final String? brand;
  final String rawCategory;
  final String? packSize;
  final String source;

  _ResolvedOnlineProduct({
    required this.name,
    required this.brand,
    required this.rawCategory,
    required this.packSize,
    required this.source,
  });
}
