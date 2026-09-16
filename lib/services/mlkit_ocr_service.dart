import 'dart:io';
import 'dart:ui' show Rect;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'gemini_ai_service.dart';
import 'inventory_inward_service.dart';

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

/// One OCR line plus where it sits on the page.
///
/// The geometry is the whole point. `RecognizedText.text` flattens a menu card
/// into reading order, which on a two-column card interleaves the name column
/// and the price column unpredictably — that is how a scan of a 17-dish mutton
/// menu came back as "Rate ₹320", "Mutton Hydrabadi(4pcs) ₹440", "360/- ₹380".
/// Keeping the bounding box lets a dish be matched to the price on ITS OWN ROW
/// instead of to whatever line happened to follow it.
class _OcrLine {
  final String text;
  final Rect box;

  _OcrLine(this.text, this.box);

  double get centerY => box.top + box.height / 2;
}

/// On-Device Free Offline Text Recognition (Google ML Kit)
/// 100% Free, Zero API Keys, Offline, <200ms Latency
class MlKitOcrService {
  MlKitOcrService._();
  static final MlKitOcrService instance = MlKitOcrService._();

  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Devanagari is a separate on-device model, created lazily because most
  /// merchants never photograph a Hindi or Marathi card and the model costs
  /// memory to hold open.
  TextRecognizer? _devanagariRecognizer;

  TextRecognizer get _devanagari =>
      _devanagariRecognizer ??= TextRecognizer(script: TextRecognitionScript.devanagiri);

  /// Scans a local image file for Wholesale / Mandi / Retail Bills using on-device ML Kit OCR
  Future<MlKitScanResult> scanBillImage(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      return MlKitScanResult(items: [], rawText: '');
    }

    final inputImage = InputImage.fromFilePath(imagePath);
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
    var text = recognizedText.text;
    var blocks = recognizedText.blocks;

    // A Devanagari parcha comes back all but empty from the Latin model. Retry
    // with the Devanagari one rather than reporting "nothing on this bill".
    if (_looksEmpty(text)) {
      try {
        final hindi = await _devanagari.processImage(inputImage);
        if (hindi.text.trim().length > text.trim().length) {
          text = hindi.text;
          blocks = hindi.blocks;
        }
      } catch (_) {}
    }

    return _parseRecognizedText(text, blocks);
  }

  static bool _looksEmpty(String text) =>
      text.trim().length < 20 || !RegExp(r'\p{L}', unicode: true).hasMatch(text);

  /// Scans a local image file for Restaurant Menu Cards using on-device ML Kit
  /// OCR (0 latency, 0 API key).
  ///
  /// This is the fallback for when the cloud scan cannot be reached at all. It
  /// is deliberately conservative: a merchant reviewing an offline result has
  /// no way to tell a confident reading from a guess, so a row this parser is
  /// unsure about is dropped rather than shown.
  Future<List<ExtractedMenuItem>> scanMenuImage(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) return [];

    final inputImage = InputImage.fromFilePath(imagePath);

    List<_OcrLine> lines = [];
    try {
      lines = _toLines(await _textRecognizer.processImage(inputImage));
    } catch (_) {}

    // Devanagari menus read as noise through the Latin model — a handful of
    // stray Latin-looking fragments. Whichever model found more real text wins.
    if (lines.length < 4) {
      try {
        final hindi = _toLines(await _devanagari.processImage(inputImage));
        if (hindi.length > lines.length) lines = hindi;
      } catch (_) {}
    }

    return _parseMenuLines(lines);
  }

  static List<_OcrLine> _toLines(RecognizedText recognized) {
    final out = <_OcrLine>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final t = line.text.trim();
        if (t.isNotEmpty) out.add(_OcrLine(t, line.boundingBox));
      }
    }
    out.sort((a, b) => a.centerY.compareTo(b.centerY));
    return out;
  }

  // Devanagari digits, so "१२०/-" reads as 120.
  static const String _devanagariDigits = '०१२३४५६७८९';

  static String _normalizeDigits(String s) {
    final buf = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      final idx = _devanagariDigits.indexOf(ch);
      buf.write(idx >= 0 ? '$idx' : ch);
    }
    return buf.toString();
  }

  /// A cell holding nothing but a price: "320", "320/-", "₹320", "320|-".
  static final RegExp _standalonePrice = RegExp(
    r'^(?:₹|rs\.?|inr)?\s*(\d{1,5})(?:[.,]\d{1,2})?\s*(?:/[-–—|]?|[-–—|])?\s*$',
    caseSensitive: false,
  );

  /// A price sitting at the end of a line that also holds the dish name.
  static final RegExp _trailingPrice = RegExp(
    r'(?:₹|rs\.?|inr)?\s*(\d{1,5})(?:[.,]\d{1,2})?\s*(?:/[-–—|]?|[-–—|])?\s*$',
    caseSensitive: false,
  );

  static int? _priceOf(String text, RegExp re) {
    final m = re.firstMatch(_normalizeDigits(text).trim());
    if (m == null) return null;
    final rupees = int.tryParse(m.group(1)!.replaceAll(RegExp(r'[^0-9]'), ''));
    if (rupees == null) return null;
    // Below ₹5 is almost always a serial number or a stray digit; above ₹20,000
    // is not a dish on an Indian menu card.
    if (rupees < 5 || rupees > 20000) return null;
    return rupees;
  }

  static const Map<String, String> _categoryKeywords = {
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
    'chicken': 'Chicken Special',
    'mutton': 'Mutton Special',
    'fish': 'Fish & Seafood',
    'egg': 'Egg Special',
    'non-veg': 'Non-Veg Special',
    'non veg': 'Non-Veg Special',
    'seafood': 'Fish & Seafood',
    'kabab': 'Starters & Tandoor',
    'kebab': 'Starters & Tandoor',
    'tandoor': 'Starters & Tandoor',
  };

  /// Lines that are page furniture rather than menu content.
  static bool _isFooterNoise(String lower) =>
      lower.contains('gst') ||
      lower.contains('taxes') ||
      lower.contains('welcome') ||
      lower.contains('timing') ||
      lower.contains('contact') ||
      lower.contains('thank you') ||
      lower.contains('address') ||
      lower.contains('delivery') ||
      lower.contains('www.') ||
      lower.contains('@');

  /// Row-aware menu parser.
  ///
  /// Walks the page geometrically: every line that is only a price becomes a
  /// candidate cell, and every name line claims the nearest unused price whose
  /// vertical span overlaps its own. Only if nothing on the row matches does it
  /// fall back to "the next line in reading order", which is all the previous
  /// version ever did.
  static List<ExtractedMenuItem> _parseMenuLines(List<_OcrLine> lines) {
    if (lines.isEmpty) return [];

    final priceCells = <int, int>{}; // line index -> rupees
    final headings = <int, String>{}; // line index -> category

    // Pass 1: which lines are nothing but a price?
    for (var i = 0; i < lines.length; i++) {
      final standalone = _priceOf(lines[i].text, _standalonePrice);
      if (standalone != null) priceCells[i] = standalone;
    }

    bool hasPriceOnRow(int index) {
      for (final cellIndex in priceCells.keys) {
        if (cellIndex == index) continue;
        if (_rowOverlap(lines[index].box, lines[cellIndex].box) >= 0.35) return true;
      }
      return false;
    }

    // Pass 2: section banners.
    //
    // Matching a category keyword is not enough on its own — "MUTTON" the
    // banner and "Mutton Kasa(4pcs)" the dish both contain "mutton", and
    // treating the dish as a heading would silently swallow it. A banner is
    // distinguished by having no price anywhere on its row, and by being either
    // shouted in capitals or nothing but the category word itself.
    for (var i = 0; i < lines.length; i++) {
      if (priceCells.containsKey(i)) continue;

      final raw = lines[i].text;
      final lower = raw.toLowerCase();
      if (_isFooterNoise(lower)) continue;
      if (raw.length >= 30) continue;
      if (_priceOf(raw, _trailingPrice) != null) continue;
      if (hasPriceOnRow(i)) continue;

      final letters = raw.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
      final isShouted = letters.length >= 3 && letters == letters.toUpperCase();
      final bare = lower.replaceAll(RegExp(r'[^a-z ]'), ' ').trim().replaceAll(RegExp(r'\s+'), ' ');

      for (final entry in _categoryKeywords.entries) {
        if (!lower.contains(entry.key)) continue;
        if (isShouted || bare == entry.key) {
          headings[i] = entry.value;
        }
        break;
      }
    }

    String categoryAt(int index) {
      var category = 'Main Course';
      for (final entry in headings.entries) {
        if (entry.key <= index) {
          category = entry.value;
        } else {
          break;
        }
      }
      return category;
    }

    final used = <int>{};
    final items = <ExtractedMenuItem>[];

    for (var i = 0; i < lines.length; i++) {
      if (priceCells.containsKey(i) || headings.containsKey(i)) continue;

      final line = lines[i];
      if (_isFooterNoise(line.text.toLowerCase())) continue;

      // Case 1: name and price on one line — "Paneer Butter Masala 220".
      final inline = _priceOf(line.text, _trailingPrice);
      if (inline != null) {
        final m = _trailingPrice.firstMatch(_normalizeDigits(line.text).trim())!;
        final name = _cleanName(line.text.substring(0, m.start));
        if (ExtractedMenuItem.isRealDishName(name)) {
          items.add(ExtractedMenuItem(
            dishName: name,
            priceInPaise: inline * 100,
            category: categoryAt(i),
          ));
        }
        continue;
      }

      final name = _cleanName(line.text);
      if (!ExtractedMenuItem.isRealDishName(name)) continue;

      // Case 2: the price lives in its own column. Find the unused price cell
      // whose vertical span overlaps this row, preferring one to the right.
      int? bestIndex;
      double bestScore = double.infinity;
      for (final entry in priceCells.entries) {
        if (used.contains(entry.key)) continue;
        final cell = lines[entry.key];
        if (_rowOverlap(line.box, cell.box) < 0.35) continue;
        // A price printed to the LEFT of the dish name is a different column
        // of a different table; only consider cells that start at or after the
        // name's left edge.
        if (cell.box.left < line.box.left) continue;
        final score = (cell.centerY - line.centerY).abs();
        if (score < bestScore) {
          bestScore = score;
          bestIndex = entry.key;
        }
      }

      // Case 3: single-column card — the very next line is the price.
      if (bestIndex == null &&
          i + 1 < lines.length &&
          priceCells.containsKey(i + 1) &&
          !used.contains(i + 1)) {
        bestIndex = i + 1;
      }

      if (bestIndex == null) continue;

      used.add(bestIndex);
      items.add(ExtractedMenuItem(
        dishName: name,
        priceInPaise: priceCells[bestIndex]! * 100,
        category: categoryAt(i),
      ));
    }

    return items;
  }

  /// How much two rows overlap vertically, as a fraction of the shorter one.
  static double _rowOverlap(Rect a, Rect b) {
    final top = a.top > b.top ? a.top : b.top;
    final bottom = a.bottom < b.bottom ? a.bottom : b.bottom;
    final overlap = bottom - top;
    if (overlap <= 0) return 0;
    final shorter = a.height < b.height ? a.height : b.height;
    return shorter <= 0 ? 0 : overlap / shorter;
  }

  /// Strips serial numbers and leading/trailing punctuation an OCR pass leaves
  /// behind, using the same rules the cloud path applies.
  static String _cleanName(String raw) {
    var name = ExtractedMenuItem.cleanDishName(raw);
    name = name.replaceAll(RegExp(r'[.\-_/:*#~|]+$'), '').trim();
    name = name.replaceAll(RegExp(r'^[.\-_/:*#~|]+'), '').trim();
    return name;
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
    final priceRegex = RegExp(r'(?:₹|Rs\.?|INR)?\s*(\d+(?:\.\d{1,2})?)\s*(?:/[-–—]?|/-)?\s*$', caseSensitive: false);
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
    // One definition of the default retail markup, shared with the Gemini
    // parser and the inward writer. These two numbers used to be written out
    // by hand in all three places, so "change the markup" meant changing it
    // three times and the AI-scanned price could drift from the manual one.
    final sellingPricePaise =
        InventoryInwardService.defaultSellingPricePaise(unitCostPaise);
    final mrpPaise = InventoryInwardService.defaultMrpPaise(unitCostPaise);

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
    _devanagariRecognizer?.close();
    _devanagariRecognizer = null;
  }
}
