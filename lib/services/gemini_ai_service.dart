import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/utils/money_formatter.dart';
import 'inventory_inward_service.dart';
import 'remote_config_service.dart';

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

  factory ExtractedMenuItem.fromJson(Map<String, dynamic> json) {
    // A value already denominated in paise (the 'price_paise' field Gemini is
    // asked to return) — no fractional part is meaningful here.
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

    return ExtractedMenuItem(
      dishName: (json['dish_name'] ?? json['name'] ?? 'Menu Item').toString(),
      priceInPaise: json['price_paise'] != null
          ? parseAlreadyPaise(json['price_paise'])
          // Fallback 'price' field is in rupees (e.g. 180.50) — use the same
          // tested rupee→paise conversion the rest of the app relies on
          // (money_formatter.dart, covered by money_math_test.dart), rather
          // than rounding the rupee value to a whole number before scaling it
          // up, which would silently drop the paise.
          : MoneyFormatter.parseRupeesToPaise(json['price']?.toString() ?? '0'),
      category: (json['category'] ?? 'General').toString(),
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
  static const String _prefKeyCustomApiKey = 'custom_gemini_api_key';
  static const int freeMonthlyPictureScanLimit = 10;

  /// Whole-request budget for one Gemini call.
  ///
  /// HttpClient.connectionTimeout only bounds establishing the TCP connection —
  /// it does NOT bound waiting for the response. With no timeout on req.close()
  /// or on reading the body, a server that accepted the connection and then
  /// went quiet left the caller waiting forever, and the scanning dialog that
  /// wraps this call is barrierDismissible: false, so the merchant was stuck on
  /// a modal with no way out. That is the "gets stuck" failure this bounds.
  static const Duration requestTimeout = Duration(seconds: 45);

  // The model list now lives in `functions/index.js` (AI_MODELS), not here.
  // Google has already retired models under this app once — 1.5-flash started
  // returning 404 and every installed copy broke until a Play Store release
  // reached each merchant. On the server it is a redeploy.

  /// Get effective API key from Firestore global_config, Remote Config, cached key, or environment
  static Future<String> getEffectiveApiKey() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Cached key from Firestore platform_settings/global_config
    final cached = prefs.getString('cached_gemini_api_key')?.trim() ?? '';
    if (cached.isNotEmpty) return cached;

    // 2. Custom override / Admin provided
    final custom = prefs.getString(_prefKeyCustomApiKey)?.trim() ?? '';
    if (custom.isNotEmpty) return custom;

    // 3. Remote Config Service
    final remoteKey = RemoteConfigService.instance.geminiApiKey.trim();
    if (remoteKey.isNotEmpty) return remoteKey;

    // 4. Live fetch from Firestore platform_settings/global_config
    try {
      final doc = await FirebaseFirestore.instance.collection('platform_settings').doc('global_config').get();
      if (doc.exists) {
        final k = doc.data()?['gemini_api_key']?.toString().trim() ?? '';
        if (k.isNotEmpty) {
          await prefs.setString('cached_gemini_api_key', k);
          return k;
        }
      }
    } catch (_) {}

    const fromEnv = String.fromEnvironment('GEMINI_API_KEY');
    if (fromEnv.isNotEmpty) return fromEnv;

    return '';
  }

  /// Save custom Google AI Studio API key provided by merchant
  static Future<void> setCustomApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    if (key.trim().isEmpty) {
      await prefs.remove(_prefKeyCustomApiKey);
    } else {
      await prefs.setString(_prefKeyCustomApiKey, key.trim());
    }
  }

  /// Tests if an API key is valid by making a lightweight request to Google AI Studio
  static Future<bool> testApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return false;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      final isBearer = trimmed.startsWith('AQ.') || trimmed.startsWith('ya29.');
      final uri = isBearer
          ? Uri.parse('https://generativelanguage.googleapis.com/v1beta/models')
          : Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$trimmed');
      final req = await client.getUrl(uri);
      if (isBearer) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $trimmed');
      } else {
        req.headers.set('x-goog-api-key', trimmed);
      }
      final res = await req.close().timeout(const Duration(seconds: 10));
      client.close(force: true);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static String _getCurrentMonthKey() {
    return 'ai_picture_scan_count_${DateFormat('yyyy_MM').format(DateTime.now())}';
  }

  static Future<int> getMonthlyScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_getCurrentMonthKey()) ?? 0;
  }

  static Future<int> getRemainingFreeScans() async {
    final count = await getMonthlyScanCount();
    final remaining = freeMonthlyPictureScanLimit - count;
    return remaining < 0 ? 0 : remaining;
  }

  static Future<void> incrementScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getCurrentMonthKey();
    final current = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, current + 1);
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

      final req = await client.postUrl(Uri.parse(_aiEndpoint));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
      req.write(jsonEncode({
        'kind': kind,
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

    return MenuScanResult(success: true, items: items);
  }
}
