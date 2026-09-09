import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/database/local_database.dart';

class ExtractedBillItem {
  String productName;
  double quantity;
  String unit;
  int purchasePricePaise;
  int mrpPaise;
  int sellingPricePaise;
  String categoryName;

  ExtractedBillItem({
    required this.productName,
    required this.quantity,
    this.unit = 'pcs',
    required this.purchasePricePaise,
    required this.mrpPaise,
    required this.sellingPricePaise,
    this.categoryName = 'General',
  });

  ExtractedBillItem copyWith({
    String? productName,
    double? quantity,
    String? unit,
    int? purchasePricePaise,
    int? mrpPaise,
    int? sellingPricePaise,
    String? categoryName,
  }) {
    return ExtractedBillItem(
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      purchasePricePaise: purchasePricePaise ?? this.purchasePricePaise,
      mrpPaise: mrpPaise ?? this.mrpPaise,
      sellingPricePaise: sellingPricePaise ?? this.sellingPricePaise,
      categoryName: categoryName ?? this.categoryName,
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
      mrpPaise: mrpPaise > 0 ? mrpPaise : (purchasePaise > 0 ? (purchasePaise * 1.2).round() : 10000),
      sellingPricePaise: sellingPaise > 0 ? sellingPaise : (purchasePaise > 0 ? (purchasePaise * 1.15).round() : 9500),
      categoryName: json['category_name'] ?? json['category'] ?? 'General',
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

class GeminiAiService {
  static const String _prefKeyCustomApiKey = 'custom_gemini_api_key';
  static const int freeMonthlyPictureScanLimit = 10;

  static const List<String> _modelsToTry = [
    'gemini-2.0-flash',
    'gemini-2.5-flash',
    'gemini-1.5-flash',
  ];

  /// Get effective API key from SharedPreferences, or from environment
  static Future<String> getEffectiveApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_prefKeyCustomApiKey)?.trim() ?? '';
    if (custom.isNotEmpty) return custom;

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
    if (key.trim().isEmpty) return false;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=${key.trim()}');
      final req = await client.getUrl(uri);
      final res = await req.close();
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
  static Future<AiInwardResult> extractItemsFromImage(
    Uint8List fileBytes, {
    String mimeType = 'image/jpeg',
    String? customApiKey,
  }) async {
    try {
      // 1. Check Free Plan Quota for images (PDFs remain free unlimited)
      final isImage = mimeType.startsWith('image/');
      if (isImage) {
        final profile = await LocalDatabase.instance.getStoreProfile();
        if (!profile.isPro) {
          final currentScans = await getMonthlyScanCount();
          if (currentScans >= freeMonthlyPictureScanLimit) {
            return AiInwardResult(
              success: false,
              isQuotaExceeded: true,
              errorMessage:
                  'Free plan includes $freeMonthlyPictureScanLimit AI picture scans per month. Upgrade to KamaiPlus Pro for Unlimited AI Inward scans, or use Excel / CSV Inward (Unlimited Free).',
            );
          }
        }
      }

      // 2. Resolve API Key
      String apiKey = customApiKey?.trim() ?? '';
      if (apiKey.isEmpty) {
        apiKey = await getEffectiveApiKey();
      }

      if (apiKey.isEmpty) {
        return AiInwardResult(
          success: false,
          errorMessage:
              'Gemini AI API Key is required for live bill vision OCR. Tap "Settings" below to enter your free API Key from Google AI Studio (aistudio.google.com), or use Excel / CSV inward.',
        );
      }

      final base64Content = base64Encode(fileBytes);
      final promptText =
          'You are an expert Indian retail inventory AI. Extract all inventory purchase items, supplier details, and bill metadata from this supplier bill / mandi parcha slip / invoice.\n'
          'Format response strictly as JSON with this schema:\n'
          '{\n'
          '  "supplier_name": "string (Wholesale / Mandi vendor name or empty)",\n'
          '  "bill_number": "string (Invoice / memo number or empty)",\n'
          '  "bill_date": "YYYY-MM-DD or empty",\n'
          '  "items": [\n'
          '    {\n'
          '      "product_name": "string (brand + item + weight/size)",\n'
          '      "quantity": number,\n'
          '      "unit": "pcs|kg|gram|litre|strip|box|packet",\n'
          '      "purchase_price_paise": number (cost price in paise, e.g. Rs 120 = 12000),\n'
          '      "mrp_paise": number (MRP in paise),\n'
          '      "selling_price_paise": number (store selling price in paise),\n'
          '      "category_name": "string"\n'
          '    }\n'
          '  ]\n'
          '}\n'
          'Do not output any markdown ticks, preamble, or comments. Output ONLY valid JSON.';

      String? lastErrorMessage;

      // Try multiple models in sequence for high availability
      for (final model in _modelsToTry) {
        try {
          final uri = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
          );

          final requestPayload = {
            'contents': [
              {
                'parts': [
                  {'text': promptText},
                  {
                    'inline_data': {
                      'mime_type': mimeType,
                      'data': base64Content,
                    }
                  }
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.1,
              'response_mime_type': 'application/json',
            }
          };

          final client = HttpClient();
          client.connectionTimeout = const Duration(seconds: 30);

          final req = await client.postUrl(uri);
          req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          req.write(jsonEncode(requestPayload));

          final res = await req.close();
          final responseBody = await res.transform(utf8.decoder).join();

          if (res.statusCode == 200) {
            if (isImage) {
              await incrementScanCount();
            }

            final parsed = jsonDecode(responseBody);
            final candidates = parsed['candidates'] as List?;
            if (candidates != null && candidates.isNotEmpty) {
              final content = candidates[0]['content'];
              final parts = content['parts'] as List?;
              if (parts != null && parts.isNotEmpty) {
                String text = parts[0]['text'] ?? '';
                text = text.replaceAll('```json', '').replaceAll('```', '').trim();

                final jsonMap = jsonDecode(text);
                final itemsJson = jsonMap['items'] as List? ?? [];

                final List<ExtractedBillItem> items = itemsJson
                    .map((e) => ExtractedBillItem.fromJson(e as Map<String, dynamic>))
                    .toList();

                if (items.isEmpty) {
                  return AiInwardResult(
                    success: false,
                    errorMessage: 'No items could be recognized on this bill. Please ensure the photo is clear, well-lit, and shows item names and rates.',
                    rawResponse: text,
                  );
                }

                return AiInwardResult(
                  success: true,
                  items: items,
                  supplierName: jsonMap['supplier_name']?.toString(),
                  billNumber: jsonMap['bill_number']?.toString(),
                  billDate: jsonMap['bill_date']?.toString(),
                  rawResponse: text,
                );
              }
            }
          } else if (res.statusCode == 401 || res.statusCode == 403) {
            final parsedErr = jsonDecode(responseBody);
            final msg = parsedErr['error']?['message'] ?? 'Authentication failed';
            return AiInwardResult(
              success: false,
              errorMessage: 'Gemini API Key Authentication Failed ($msg). Please update your API key in Settings.',
            );
          } else if (res.statusCode == 429) {
            return AiInwardResult(
              success: false,
              errorMessage: 'Gemini API Rate Limit reached. Please wait a moment and try again.',
            );
          } else {
            lastErrorMessage = 'Model $model responded with HTTP ${res.statusCode}: $responseBody';
          }
        } catch (modelErr) {
          lastErrorMessage = modelErr.toString();
        }
      }

      return AiInwardResult(
        success: false,
        errorMessage: lastErrorMessage ?? 'Could not parse document. Please check connection and try again.',
      );
    } catch (e) {
      return AiInwardResult(
        success: false,
        errorMessage: 'OCR Scan Error: $e',
      );
    }
  }
}
