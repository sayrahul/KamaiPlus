import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'gemini_ai_service.dart';

class MlKitScanResult {
  final List<ExtractedBillItem> items;
  final String? supplierName;
  final String? billNumber;
  final String? billDate;
  final String rawText;

  MlKitScanResult({
    required this.items,
    this.supplierName,
    this.billNumber,
    this.billDate,
    required this.rawText,
  });
}

/// On-Device Free Offline Text Recognition (Google ML Kit)
/// 100% Free, Zero API Keys, Offline, <200ms Latency
class MlKitOcrService {
  MlKitOcrService._();
  static final MlKitOcrService instance = MlKitOcrService._();

  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Scans a local image file for Wholesale / Mandi / Retail Bills using on-device ML Kit OCR
  Future<MlKitScanResult> scanBillImage(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      return MlKitScanResult(items: [], rawText: '');
    }

    final inputImage = InputImage.fromFilePath(imagePath);
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
    final text = recognizedText.text;

    return _parseRecognizedText(text, recognizedText.blocks);
  }

  /// Scans a local image file for Restaurant Menu Cards using on-device ML Kit OCR (0 latency, 0 API key)
  Future<List<ExtractedMenuItem>> scanMenuImage(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) return [];

    final inputImage = InputImage.fromFilePath(imagePath);
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
    return _parseRecognizedMenu(recognizedText.text);
  }

  /// Intelligent restaurant menu card parser (Category detection, Dish name + Price extraction)
  List<ExtractedMenuItem> _parseRecognizedMenu(String rawText) {
    final List<ExtractedMenuItem> items = [];
    final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    String currentCategory = 'Main Course';

    final categoryKeywords = {
      'starter': 'Starters',
      'soup': 'Soups',
      'main course': 'Main Course',
      'curry': 'Main Course',
      'paneer': 'Paneer Special',
      'roti': 'Breads & Roti',
      'naan': 'Breads & Roti',
      'bread': 'Breads & Roti',
      'rice': 'Rice & Biryani',
      'biryani': 'Rice & Biryani',
      'dal': 'Dal & Lentils',
      'chinese': 'Chinese',
      'noodle': 'Chinese',
      'south indian': 'South Indian',
      'dosa': 'South Indian',
      'beverage': 'Beverages',
      'drink': 'Beverages',
      'tea': 'Beverages',
      'coffee': 'Beverages',
      'snack': 'Snacks',
      'chaat': 'Chaat & Snacks',
      'sweet': 'Desserts',
      'dessert': 'Desserts',
      'ice cream': 'Desserts',
      'thali': 'Thali Special',
    };

    final priceEndRegex = RegExp(r'(?:₹|Rs\.?|INR)?\s*(\d{2,4})\s*$', caseSensitive: false);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lower = line.toLowerCase();

      // Check if line looks like a category header
      bool isCategory = false;
      for (final entry in categoryKeywords.entries) {
        if (lower.contains(entry.key) && line.length < 30 && !priceEndRegex.hasMatch(line)) {
          currentCategory = entry.value;
          isCategory = true;
          break;
        }
      }
      if (isCategory) continue;

      // Ignore common non-dish menu footer lines
      if (lower.contains('gst') ||
          lower.contains('taxes') ||
          lower.contains('welcome') ||
          lower.contains('timing') ||
          lower.contains('contact') ||
          lower.contains('thank you') ||
          lower.contains('address')) {
        continue;
      }

      // Check 1: Dish name and price on the same line (e.g. "Paneer Butter Masala 220")
      final match = priceEndRegex.firstMatch(line);
      if (match != null) {
        final priceStr = match.group(1)!;
        final price = int.tryParse(priceStr) ?? 0;
        if (price >= 10 && price <= 5000) {
          String dishName = line.substring(0, match.start).trim();
          dishName = dishName.replaceAll(RegExp(r'[\.\-_/:\*#@~]+$'), '').trim();
          dishName = dishName.replaceAll(RegExp(r'^[\.\-_/:\*#@~]+'), '').trim();
          if (dishName.length >= 2 && !RegExp(r'^\d+$').hasMatch(dishName)) {
            items.add(ExtractedMenuItem(
              dishName: dishName,
              priceInPaise: price * 100,
              category: currentCategory,
            ));
            continue;
          }
        }
      }

      // Check 2: Dish name on line i and standalone price on line i+1 (multi-column)
      if (i + 1 < lines.length) {
        final nextLine = lines[i + 1].trim();
        final standalonePrice = RegExp(r'^(?:₹|Rs\.?|INR)?\s*(\d{2,4})\s*$', caseSensitive: false).firstMatch(nextLine);
        if (standalonePrice != null && line.length >= 3 && !priceEndRegex.hasMatch(line)) {
          final price = int.tryParse(standalonePrice.group(1)!) ?? 0;
          if (price >= 10 && price <= 5000) {
            String dishName = line.replaceAll(RegExp(r'[\.\-_/:\*#@~]+$'), '').trim();
            if (dishName.length >= 2 && !RegExp(r'^\d+$').hasMatch(dishName)) {
              items.add(ExtractedMenuItem(
                dishName: dishName,
                priceInPaise: price * 100,
                category: currentCategory,
              ));
              i++; // skip next line as it was consumed as price
              continue;
            }
          }
        }
      }
    }

    return items;
  }

  /// Intelligent retail invoice line parser
  MlKitScanResult _parseRecognizedText(String rawText, List<TextBlock> blocks) {
    final List<ExtractedBillItem> items = [];
    String? supplierName;
    String? billNumber;
    String? billDate;

    final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    // 1. Try to find Supplier Name (usually first 1-4 lines that look like a business)
    for (int i = 0; i < lines.length && i < 4; i++) {
      final line = lines[i];
      final lower = line.toLowerCase();
      if (lower.contains('store') ||
          lower.contains('traders') ||
          lower.contains('agency') ||
          lower.contains('kirana') ||
          lower.contains('enterprises') ||
          lower.contains('wholesale') ||
          lower.contains('distributor') ||
          lower.contains('mandi') ||
          lower.contains('mart')) {
        supplierName = line;
        break;
      }
    }
    if (supplierName == null && lines.isNotEmpty && lines.first.length > 3) {
      if (!RegExp(r'^[0-9\W]+$').hasMatch(lines.first)) {
        supplierName = lines.first;
      }
    }

    // 2. Try to find Date and Bill / Invoice No
    final billNoRegex = RegExp(r'(?:inv(?:oice)?|bill|memo|receipt|challan)[\s#:]*([A-Za-z0-9\-_/]+)', caseSensitive: false);
    final dateRegex = RegExp(r'(\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4})');

    for (final line in lines) {
      if (billNumber == null) {
        final match = billNoRegex.firstMatch(line);
        if (match != null && match.groupCount >= 1) {
          billNumber = match.group(1);
        }
      }
      if (billDate == null) {
        final match = dateRegex.firstMatch(line);
        if (match != null) {
          billDate = match.group(1);
        }
      }
    }

    // 3. Parse Item Rows
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lower = line.toLowerCase();

      // Ignore header or summary lines
      if (lower.contains('total') ||
          lower.contains('subtotal') ||
          lower.contains('grand total') ||
          lower.contains('gst') ||
          lower.contains('cgst') ||
          lower.contains('sgst') ||
          lower.contains('tax') ||
          lower.contains('phone') ||
          lower.contains('mob:') ||
          lower.contains('thank you') ||
          lower.contains('cashier') ||
          lower.contains('authorised signatory')) {
        continue;
      }

      // Try single line item
      final item = _parseItemLine(line);
      if (item != null) {
        items.add(item);
        continue;
      }

      // Try 2-line pair (Line i = Name, Line i+1 = Qty & Price)
      if (i + 1 < lines.length) {
        final nextLine = lines[i + 1];
        final combined = '$line $nextLine';
        final pairItem = _parseItemLine(combined);
        if (pairItem != null) {
          items.add(pairItem);
          i++; // skip next line
          continue;
        }
      }
    }

    return MlKitScanResult(
      items: items,
      supplierName: supplierName,
      billNumber: billNumber,
      billDate: billDate,
      rawText: rawText,
    );
  }

  ExtractedBillItem? _parseItemLine(String line) {
    // Look for price or numbers at the end of line
    // e.g. "Basmati Rice 10kg 950.00" or "Amul Butter 100g 55"
    final priceRegex = RegExp(r'(?:₹|Rs\.?|INR)?\s*(\d+(?:\.\d{1,2})?)\s*$', caseSensitive: false);
    final match = priceRegex.firstMatch(line);
    if (match == null) return null;

    final priceStr = match.group(1)!;
    final priceDouble = double.tryParse(priceStr) ?? 0.0;
    if (priceDouble <= 0 || priceDouble > 500000) return null;

    final nameAndQtyPart = line.substring(0, match.start).trim();
    if (nameAndQtyPart.length < 2) return null;

    // Detect quantity and unit (e.g. "5 kg", "2 pcs", "10 pkt", "1 box", "500 gm", "1 ltr")
    double qty = 1.0;
    String unit = 'pcs';
    String productName = nameAndQtyPart;

    final qtyUnitRegex = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|g|gm|ltr|l|ml|pcs|pc|pkt|packet|box|dz|dozen|bag|tin|btl|bottle|can)', caseSensitive: false);
    final qtyMatch = qtyUnitRegex.firstMatch(nameAndQtyPart);

    if (qtyMatch != null) {
      qty = double.tryParse(qtyMatch.group(1)!) ?? 1.0;
      final rawUnit = qtyMatch.group(2)!.toLowerCase();
      unit = (rawUnit == 'pc' || rawUnit == 'packet') ? 'pcs' : rawUnit;
      productName = nameAndQtyPart.replaceFirst(qtyMatch.group(0)!, '').trim();
    } else {
      // Standalone number e.g. "Soap 5 150"
      final standaloneQtyRegex = RegExp(r'(\d+)\s*$');
      final sMatch = standaloneQtyRegex.firstMatch(nameAndQtyPart);
      if (sMatch != null) {
        final parsedQty = double.tryParse(sMatch.group(1)!) ?? 1.0;
        if (parsedQty > 0 && parsedQty <= 1000) {
          qty = parsedQty;
          productName = nameAndQtyPart.substring(0, sMatch.start).trim();
        }
      }
    }

    // Clean product name from trailing symbols like @, x, -, =
    productName = productName.replaceAll(RegExp(r'[@x\-:=#\.\*]+$'), '').trim();
    productName = productName.replaceAll(RegExp(r'^[@x\-:=#\.\*]+'), '').trim();
    if (productName.isEmpty) {
      productName = 'Stock Item ${priceDouble.round()}';
    }

    // Auto classify category by product name
    final pLower = productName.toLowerCase();
    String category = 'General';
    if (pLower.contains('milk') || pLower.contains('butter') || pLower.contains('cheese') || pLower.contains('paneer') || pLower.contains('curd') || pLower.contains('dahi')) {
      category = 'Dairy & Milk';
    } else if (pLower.contains('rice') || pLower.contains('atta') || pLower.contains('flour') || pLower.contains('dal') || pLower.contains('oil') || pLower.contains('sugar') || pLower.contains('salt')) {
      category = 'Grocery & Staples';
    } else if (pLower.contains('biscuit') || pLower.contains('cookie') || pLower.contains('namkeen') || pLower.contains('chips') || pLower.contains('snack') || pLower.contains('noodle')) {
      category = 'Snacks & Packaged Food';
    } else if (pLower.contains('soap') || pLower.contains('shampoo') || pLower.contains('paste') || pLower.contains('brush') || pLower.contains('detergent')) {
      category = 'Personal & Home Care';
    } else if (pLower.contains('coke') || pLower.contains('pepsi') || pLower.contains('juice') || pLower.contains('water') || pLower.contains('tea') || pLower.contains('coffee')) {
      category = 'Beverages';
    }

    final totalPaise = (priceDouble * 100).round();
    final unitCostPaise = qty > 0 ? (totalPaise / qty).round() : totalPaise;
    final sellingPricePaise = (unitCostPaise * 1.15).round();
    final mrpPaise = (unitCostPaise * 1.20).round();

    return ExtractedBillItem(
      productName: productName,
      quantity: qty,
      unit: unit,
      purchasePricePaise: unitCostPaise,
      sellingPricePaise: sellingPricePaise,
      mrpPaise: mrpPaise,
      categoryName: category,
    );
  }

  void dispose() {
    _textRecognizer.close();
  }
}
