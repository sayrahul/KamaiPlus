import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/utils/money_formatter.dart';
import 'inventory_inward_service.dart';

class ExtractedBillItem {
  String productName;
  double quantity;
  String unit;
  int purchasePricePaise;
  int mrpPaise;
  int sellingPricePaise;
  String categoryName;

  /// EAN/UPC printed on the pack, when the source supplied one.
  ///
  /// Carried end-to-end because it is the whole point of a bulk import: a
  /// merchant loading 1000 SKUs from a distributor sheet expects to scan them
  /// at the counter afterwards. The CSV template the app itself generates has
  /// always had a Barcode column, and the parser used to ignore it entirely —
  /// so every bulk-imported product arrived unscannable.
  String? barcode;

  /// `YYYY-MM-DD`, for verticals that track it (pharmacy). Same story as
  /// [barcode]: in the template, ignored by the parser.
  String? expiryDate;

  ExtractedBillItem({
    required this.productName,
    required this.quantity,
    this.unit = 'pcs',
    required this.purchasePricePaise,
    required this.mrpPaise,
    required this.sellingPricePaise,
    this.categoryName = 'General',
    this.barcode,
    this.expiryDate,
  });

  ExtractedBillItem copyWith({
    String? productName,
    double? quantity,
    String? unit,
    int? purchasePricePaise,
    int? mrpPaise,
    int? sellingPricePaise,
    String? categoryName,
    String? barcode,
    String? expiryDate,
  }) {
    return ExtractedBillItem(
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      purchasePricePaise: purchasePricePaise ?? this.purchasePricePaise,
      mrpPaise: mrpPaise ?? this.mrpPaise,
      sellingPricePaise: sellingPricePaise ?? this.sellingPricePaise,
      categoryName: categoryName ?? this.categoryName,
      barcode: barcode ?? this.barcode,
      expiryDate: expiryDate ?? this.expiryDate,
    );
  }

  factory ExtractedBillItem.fromJson(Map<String, dynamic> json) {
    int parsePaise(dynamic val, {bool isAlreadyPaise = false}) {
      if (val == null) return 0;
      if (val is int) {
        return isAlreadyPaise ? val : val * 100;
      }
      if (val is double) {
        return isAlreadyPaise ? val.round() : (val * 100).round();
      }
      if (val is String) {
        final clean = val.replaceAll(RegExp(r'[^0-9.]'), '');
        final d = double.tryParse(clean) ?? 0.0;
        return isAlreadyPaise ? d.round() : (d * 100).round();
      }
      return 0;
    }

    final qty = (json['quantity'] as num?)?.toDouble() ?? 1.0;
    final purchasePaise = json['purchase_price_paise'] != null
        ? parsePaise(json['purchase_price_paise'], isAlreadyPaise: true)
        : parsePaise(json['rate'] ?? json['price'] ?? json['purchase_price'], isAlreadyPaise: false);
    final mrpPaise = json['mrp_paise'] != null
        ? parsePaise(json['mrp_paise'], isAlreadyPaise: true)
        : parsePaise(json['mrp'], isAlreadyPaise: false);
    final sellingPaise = json['selling_price_paise'] != null
        ? parsePaise(json['selling_price_paise'], isAlreadyPaise: true)
        : parsePaise(json['selling_price'], isAlreadyPaise: false);

    return ExtractedBillItem(
      productName: json['product_name'] ?? json['name'] ?? json['item_name'] ?? 'Inventory Item',
      quantity: qty > 0 ? qty : 1.0,
      unit: json['unit']?.toString().toLowerCase() ?? 'pcs',
      purchasePricePaise: purchasePaise,
      // Same shared markup definition the ML Kit parser and the inward writer
      // use, so an AI-scanned item cannot be priced differently from a
      // manually inwarded one.
      mrpPaise: mrpPaise > 0
          ? mrpPaise
          : (purchasePaise > 0
              ? InventoryInwardService.defaultMrpPaise(purchasePaise)
              : 10000),
      sellingPricePaise: sellingPaise > 0
          ? sellingPaise
          : (purchasePaise > 0
              ? InventoryInwardService.defaultSellingPricePaise(purchasePaise)
              : 9500),
      categoryName: json['category_name'] ?? json['category'] ?? 'General',
      // Digits only — a scanner never produces anything else, and a stray
      // space or dash from an OCR read would make the barcode unmatchable.
      barcode: () {
        final raw = (json['barcode'] ?? json['ean'] ?? json['upc'])?.toString() ?? '';
        final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
        return digits.length >= 8 && digits.length <= 14 ? digits : null;
      }(),
      expiryDate: () {
        final raw = (json['expiry_date'] ?? json['expiry'])?.toString().trim() ?? '';
        return raw.isEmpty ? null : raw;
      }(),
    );
  }
}

class AiInwardResult {
  final bool success;
  final String? errorMessage;
  final bool isQuotaExceeded;
  final List<ExtractedBillItem> items;
  final String? rawResponse;
  final String? supplierName;
  final String? billNumber;
  final String? billDate;

  AiInwardResult({
    required this.success,
    this.errorMessage,
    this.isQuotaExceeded = false,
    this.items = const [],
    this.rawResponse,
    this.supplierName,
    this.billNumber,
    this.billDate,
  });
}

/// A single dish parsed from a restaurant menu photo.
///
/// Deliberately much smaller than [ExtractedBillItem]: a menu card carries a dish
/// name and a selling price, never a wholesale cost, MRP, or received quantity —
/// those fields exist on a supplier invoice, not a menu.
class ExtractedMenuItem {
  String dishName;
  int priceInPaise;
  String category;

  ExtractedMenuItem({
    required this.dishName,
    required this.priceInPaise,
    this.category = 'General',
  });

  /// Header words and stray price cells that an OCR pass turns into "dishes".
  ///
  /// The server applies the same guard, and this is the second line: a merchant
  /// on an older build, or the offline ML Kit fallback, can still hand this
  /// parser a row named "Rate" or "360/-". Kept in the model rather than the UI
  /// so every path that builds a dish gets it.
  static const Set<String> _nonDishWords = {
    'rate', 'rates', 'item', 'items', 'price', 'prices', 'mrp', 'amount',
    'qty', 'quantity', 'total', 'subtotal', 'sub total', 'grand total',
    'sr', 'sr no', 's no', 'sno', 'no', 'serial', 'serial no',
    'dish', 'dishes', 'name', 'menu', 'veg', 'non veg', 'nonveg',
    'half', 'full', 'plate', 'new', 'special', 'category', 'description',
    'particulars', 'hsn', 'gst', 'our menu', 'food menu', 'price list',
    'rate list', 'rate card',
  };

  /// True when [name] is a real dish rather than table furniture.
  ///
  /// Unicode-aware on purpose: "मटन कसा" and "பன்னீர்" are dishes, and a
  /// `[a-z]` test would have thrown away every non-Latin menu in the country.
  static bool isRealDishName(String name) {
    final trimmed = name.trim();
    if (trimmed.length < 2) return false;
    if (!RegExp(r'\p{L}', unicode: true).hasMatch(trimmed)) return false;
    final key = trimmed
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .trim();
    return key.isNotEmpty && !_nonDishWords.contains(key);
  }

  /// Strips the serial number a printed menu puts before each row, so
  /// "21.Chicken Hydrabadi(5pcs)" becomes "Chicken Hydrabadi(5pcs)".
  static String cleanDishName(String raw) {
    var name = raw.trim();
    name = name.replaceFirst(RegExp(r'^[\d#]+\s*[.)\-:\s]+\s*'), '');
    name = name.replaceAll(RegExp(r'\s{2,}'), ' ');
    return name.trim();
  }

  factory ExtractedMenuItem.fromJson(Map<String, dynamic> json) {
    // A value already denominated in paise — no fractional part is meaningful.
    int parseAlreadyPaise(dynamic val) {
      if (val == null) return 0;
      if (val is int) return val;
      if (val is double) return val.round();
      if (val is String) {
        final clean = val.replaceAll(RegExp(r'[^0-9.]'), '');
        return (double.tryParse(clean) ?? 0.0).round();
      }
      return 0;
    }

    // Accept BOTH response shapes.
    //
    // The server's normalizer emits menu keys (dish_name/price_paise/category)
    // and bill keys (product_name/selling_price_paise/category_name) on every
    // item. It did not always: it sent only the bill keys while this parser
    // read only the menu keys, so a menu Gemini had read perfectly — the
    // function logged "17 item(s)" — arrived here as seventeen rows of
    // "Menu Item" at ₹0.00, and the sheet fell back to offline OCR junk.
    // Reading every spelling means neither side can break the other again.
    final rawName = (json['dish_name'] ??
            json['product_name'] ??
            json['name'] ??
            json['item_name'] ??
            json['item'] ??
            '')
        .toString();

    final paise = parseAlreadyPaise(json['price_paise']) != 0
        ? parseAlreadyPaise(json['price_paise'])
        : parseAlreadyPaise(json['selling_price_paise']) != 0
            ? parseAlreadyPaise(json['selling_price_paise'])
            : parseAlreadyPaise(json['mrp_paise']) != 0
                ? parseAlreadyPaise(json['mrp_paise'])
                // A bare 'price'/'rate' field is in rupees (e.g. 180.50) — use
                // the same tested rupee→paise conversion the rest of the app
                // relies on (money_formatter.dart, covered by
                // money_math_test.dart) rather than rounding to whole rupees
                // first, which would silently drop the paise.
                : MoneyFormatter.parseRupeesToPaise(
                    (json['price'] ?? json['rate'] ?? '0').toString());

    final cleaned = cleanDishName(rawName);

    return ExtractedMenuItem(
      dishName: cleaned.isEmpty ? 'Menu Item' : cleaned,
      priceInPaise: paise,
      category:
          (json['category'] ?? json['category_name'] ?? 'General').toString(),
    );
  }
}

class MenuScanResult {
  final bool success;
  final String? errorMessage;
  final bool isQuotaExceeded;
  final List<ExtractedMenuItem> items;

  MenuScanResult({
    required this.success,
    this.errorMessage,
    this.isQuotaExceeded = false,
    this.items = const [],
  });
}

class GeminiAiService {
  /// Daily allowances, mirroring FREE_DAILY_IMAGE_SCANS / PRO_DAILY_IMAGE_SCANS
  /// in `functions/ai_extract_core.js`. The server is the authority; these are
  /// only for wording the UI before a request is made.
  static const int freeDailyPictureScanLimit = 10;
  static const int proDailyPictureScanLimit = 100;

  /// Whole-request budget for one Gemini call.
  ///
  /// HttpClient.connectionTimeout only bounds establishing the TCP connection —
  /// it does NOT bound waiting for the response. With no timeout on req.close()
  /// or on reading the body, a server that accepted the connection and then
  /// went quiet left the caller waiting forever, and the scanning dialog that
  /// wraps this call is barrierDismissible: false, so the merchant was stuck on
  /// a modal with no way out. That is the "gets stuck" failure this bounds.
  static const Duration requestTimeout = Duration(seconds: 45);

  // The model list now lives in `functions/ai_extract_core.js` (DEFAULT_AI_MODELS),
  // not here. Google has already retired models under this app once — 1.5-flash
  // started returning 404 and every installed copy broke until a Play Store
  // release reached each merchant. On the server it is a redeploy.

  /// Deletes any Gemini API key an older build left in app storage.
  ///
  /// Until this release the app pulled `gemini_api_key` out of Firestore and
  /// wrote it to SharedPreferences, so the project's key sat in plaintext in
  /// every merchant's app data and could be lifted off the device to spend this
  /// project's quota and billing. Extraction moved server-side, but the copies
  /// already written stayed where they were — nothing removes a preference key
  /// just because the code that wrote it is gone. Called once on startup.
  ///
  /// The key-handling methods that used to live here (getEffectiveApiKey,
  /// setCustomApiKey, testApiKey) are gone with it; their only caller was a
  /// dialog asking merchants to supply a key, which the app's own invariants
  /// forbid, and which nothing had linked to for some time.
  static Future<void> purgeAnyCachedApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_gemini_api_key');
      await prefs.remove('custom_gemini_api_key');
    } catch (_) {}
  }

  /// Local mirror of the server's daily bucket, for display only.
  ///
  /// The server is what enforces the limit (per business, keyed to the IST
  /// day), so this counter drifting or being cleared changes nothing about
  /// what a merchant can actually do — it exists so the sheet can say
  /// "N scans left today" without a round trip before the user has even
  /// picked a photo.
  static String _getCurrentDayKey() {
    return 'ai_picture_scan_count_${DateFormat('yyyy_MM_dd').format(DateTime.now())}';
  }

  /// Scans used today, as far as this device knows.
  static Future<int> getTodayScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_getCurrentDayKey()) ?? 0;
  }

  /// Last daily allowance the server reported, so the UI can show the right
  /// number for a Pro merchant (100) rather than the free one (10).
  static Future<int> getDailyLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt('ai_daily_scan_limit') ?? 0;
    return stored > 0 ? stored : freeDailyPictureScanLimit;
  }

  static Future<int> getRemainingScansToday() async {
    final count = await getTodayScanCount();
    final limit = await getDailyLimit();
    final remaining = limit - count;
    return remaining < 0 ? 0 : remaining;
  }

  static Future<void> incrementScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getCurrentDayKey();
    final current = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, current + 1);
  }

  /// Syncs the local mirror to whatever the server just reported, so a merchant
  /// who scanned on another device — or whose local count drifted — sees the
  /// truth rather than a stale number.
  static Future<void> _recordServerQuota(Map<String, dynamic>? quota) async {
    if (quota == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final used = (quota['used'] as num?)?.toInt();
      final limit = (quota['limit'] as num?)?.toInt();
      if (used != null) await prefs.setInt(_getCurrentDayKey(), used);
      if (limit != null && limit > 0) await prefs.setInt('ai_daily_scan_limit', limit);
    } catch (_) {}
  }

  /// Extracts structured inward items from bill parcha photo or PDF using Gemini Vision API
  /// Backend AI extraction endpoint (`aiExtract` in `functions/index.js`).
  ///
  /// The app used to call Google directly with a key fetched from Firestore
  /// and cached in SharedPreferences — which means the key sat on every
  /// merchant's phone and could be pulled off it to spend this project's quota
  /// and billing. A key handed to every device is not a secret. It now never
  /// leaves the server.
  ///
  /// Three more things moved server-side with it: the free-scan quota (which
  /// was SharedPreferences-based, so clearing app data reset it), the model
  /// list (a retired model is now a redeploy, not a Play Store rollout), and
  /// PDF parsing, which has no offline fallback and so depended entirely on
  /// that key working.
  static const String _aiEndpoint =
      'https://us-central1-kamaiplus.cloudfunctions.net/aiExtract';

  /// One call to the proxy. Returns the decoded JSON body plus the HTTP status
  /// so callers can distinguish "quota exhausted" from "AI could not read it".
  static Future<({int status, Map<String, dynamic>? body, String? error})> _callProxy({
    required String kind,
    required Uint8List fileBytes,
    required String mimeType,
  }) async {
    HttpClient? client;
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        return (status: 401, body: null, error: 'Please sign in to use AI scan.');
      }

      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);

      final prefs = await SharedPreferences.getInstance();
      final businessType = prefs.getString('business_type') ?? 'grocery';

      final req = await client.postUrl(Uri.parse(_aiEndpoint));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
      req.write(jsonEncode({
        'kind': kind,
        'business_type': businessType,
        'mime_type': mimeType,
        'data_base64': base64Encode(fileBytes),
      }));

      final res = await req.close().timeout(requestTimeout);
      final raw = await res.transform(utf8.decoder).join().timeout(requestTimeout);
      final decoded = jsonDecode(raw);
      return (
        status: res.statusCode,
        body: decoded is Map<String, dynamic> ? decoded : null,
        error: null,
      );
    } on TimeoutException {
      return (
        status: 408,
        body: null,
        error: 'AI scan timed out. Check your connection, or use Offline Scan / Excel-CSV inward.'
      );
    } catch (e) {
      return (
        status: 0,
        body: null,
        error: 'Could not reach AI service. Use Offline Scan or Excel / CSV inward. ($e)'
      );
    } finally {
      client?.close(force: true);
    }
  }

  /// Extracts purchase items, supplier and bill metadata from a supplier bill,
  /// mandi parcha photo, or PDF invoice.
  ///
  /// [customApiKey] is accepted and ignored — kept so existing call sites
  /// compile unchanged. Keys are a server concern now; nothing the device
  /// supplies could be trusted anyway.
  static Future<AiInwardResult> extractItemsFromImage(
    Uint8List fileBytes, {
    String mimeType = 'image/jpeg',
    String? customApiKey,
  }) async {
    final res = await _callProxy(
      kind: 'bill',
      fileBytes: fileBytes,
      mimeType: mimeType,
    );

    if (res.error != null) {
      return AiInwardResult(success: false, errorMessage: res.error);
    }
    final body = res.body;

    if (res.status == 429) {
      return AiInwardResult(
        success: false,
        isQuotaExceeded: true,
        errorMessage: body?['error']?.toString() ??
            'Free plan AI scan limit reached. Upgrade to Pro, or use Excel / CSV inward (unlimited free).',
      );
    }
    if (res.status != 200 || body == null) {
      return AiInwardResult(
        success: false,
        errorMessage: body?['error']?.toString() ??
            'AI could not read this file. Try the offline scan, or upload Excel / CSV.',
      );
    }

    final itemsJson = body['items'] as List? ?? [];
    final items = itemsJson
        .whereType<Map<String, dynamic>>()
        .map(ExtractedBillItem.fromJson)
        .toList();

    if (items.isEmpty) {
      return AiInwardResult(
        success: false,
        errorMessage:
            'No items could be recognized on this bill. Please ensure the photo is clear, well-lit, and shows item names and rates.',
      );
    }

    // The server counts the scan (only when it produced items), so the local
    // counter is kept purely to render "N free scans left" without a round
    // trip. It is no longer what enforces the limit.
    if (mimeType.startsWith('image/')) {
      await incrementScanCount();
    }
    await _recordServerQuota(body['quota'] as Map<String, dynamic>?);

    return AiInwardResult(
      success: true,
      items: items,
      supplierName: body['supplier_name']?.toString(),
      billNumber: body['bill_number']?.toString(),
      billDate: body['bill_date']?.toString(),
    );
  }

  /// Extracts dish names, prices, and categories from a restaurant menu card
  /// photo. Deliberately a separate prompt from the bill one — a menu has no
  /// supplier, no cost price and no quantity received, and asking the purchase
  /// prompt to read one would treat the menu price as a wholesale cost and mark
  /// it up. Shares the same free-tier monthly scan allowance.
  ///
  /// [customApiKey] / [knownCategories] are accepted and ignored — kept so
  /// existing call sites compile unchanged.
  static Future<MenuScanResult> extractMenuItemsFromImage(
    Uint8List fileBytes, {
    String mimeType = 'image/jpeg',
    String? customApiKey,
    List<String> knownCategories = const [],
  }) async {
    final res = await _callProxy(
      kind: 'menu',
      fileBytes: fileBytes,
      mimeType: mimeType,
    );

    if (res.error != null) {
      return MenuScanResult(success: false, errorMessage: res.error);
    }
    final body = res.body;

    if (res.status == 429) {
      return MenuScanResult(
        success: false,
        isQuotaExceeded: true,
        errorMessage: body?['error']?.toString() ??
            'Free plan AI scan limit reached. Upgrade to Pro, or add dishes manually.',
      );
    }
    if (res.status != 200 || body == null) {
      return MenuScanResult(
        success: false,
        errorMessage: body?['error']?.toString() ??
            'AI could not read this menu. Try the offline scan, or add dishes manually.',
      );
    }

    final itemsJson = body['items'] as List? ?? [];
    final items = itemsJson
        .whereType<Map<String, dynamic>>()
        .map(ExtractedMenuItem.fromJson)
        // A row with no price or a table-header name is not a dish the merchant
        // can review — showing "Rate ₹0.00" is worse than showing nothing,
        // because it looks like a real reading of their menu.
        .where((d) =>
            d.priceInPaise > 0 && ExtractedMenuItem.isRealDishName(d.dishName))
        .toList();

    if (items.isEmpty) {
      return MenuScanResult(
        success: false,
        errorMessage:
            'No dishes could be recognized. Please ensure the menu photo is clear and shows dish names with prices.',
      );
    }

    if (mimeType.startsWith('image/')) {
      await incrementScanCount();
    }
    await _recordServerQuota(body['quota'] as Map<String, dynamic>?);

    return MenuScanResult(success: true, items: items);
  }
}
