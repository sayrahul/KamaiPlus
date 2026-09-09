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
class MlKitOcrService {
  MlKitOcrService._();
  static final MlKitOcrService instance = MlKitOcrService._();

  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Scans a local image file using on-device ML Kit OCR (0 latency, 0 API cost)
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

  /// Intelligent retail invoice line parser
  MlKitScanResult _parseRecognizedText(String rawText, List<TextBlock> blocks) {
    final List<ExtractedBillItem> items = [];
    String? supplierName;
    String? billNumber;
    String? billDate;

    final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    // 1. Try to find Supplier Name (usually first 1-3 lines that look like a business)
    for (int i = 0; i < lines.length && i < 4; i++) {
      final line = lines[i];
      if (line.toLowerCase().contains('store') ||
          line.toLowerCase().contains('traders') ||
          line.toLowerCase().contains('agency') ||
          line.toLowerCase().contains('kirana') ||
          line.toLowerCase().contains('enterprises') ||
          line.toLowerCase().contains('wholesale')) {
        supplierName = line;
        break;
      }
    }
    if (supplierName == null && lines.isNotEmpty && lines.first.length > 3) {
      // Fallback: first non-numeric header line
      if (!RegExp(r'^[0-9\W]+$').hasMatch(lines.first)) {
        supplierName = lines.first;
      }
    }

    // 2. Try to find Date and Bill / Invoice No
    final billNoRegex = RegExp(r'(?:inv(?:oice)?|bill|memo|receipt)[\s#:]*([A-Za-z0-9\-_/]+)', caseSensitive: false);
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
    // Typical line: "Sugar 5kg 42.00 210.00" or "Amul Butter 100g x 2 = 110"
    for (final line in lines) {
      // Ignore header or summary lines
      final lower = line.toLowerCase();
      if (lower.contains('total') ||
          lower.contains('subtotal') ||
          lower.contains('gst') ||
          lower.contains('cgst') ||
          lower.contains('sgst') ||
          lower.contains('tax') ||
          lower.contains('phone') ||
          lower.contains('mob:') ||
          lower.contains('thank you') ||
          lower.contains('cashier')) {
        continue;
      }

      final item = _parseItemLine(line);
      if (item != null) {
        items.add(item);
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
    // e.g. "Basmati Rice 10kg 950.00"
    final priceRegex = RegExp(r'(\d+(?:\.\d{1,2})?)\s*$');
    final match = priceRegex.firstMatch(line);
    if (match == null) return null;

    final priceStr = match.group(1)!;
    final priceDouble = double.tryParse(priceStr) ?? 0.0;
    if (priceDouble <= 0) return null;

    final nameAndQtyPart = line.substring(0, match.start).trim();
    if (nameAndQtyPart.length < 2) return null;

    // Detect quantity and unit (e.g. "5 kg", "2 pcs", "10 pkt", "1 box")
    double qty = 1.0;
    String unit = 'pcs';
    String productName = nameAndQtyPart;

    final qtyUnitRegex = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|g|gm|ltr|l|ml|pcs|pc|pkt|packet|box|dz|dozen)', caseSensitive: false);
    final qtyMatch = qtyUnitRegex.firstMatch(nameAndQtyPart);

    if (qtyMatch != null) {
      qty = double.tryParse(qtyMatch.group(1)!) ?? 1.0;
      final rawUnit = qtyMatch.group(2)!.toLowerCase();
      unit = (rawUnit == 'pc' || rawUnit == 'packet') ? 'pcs' : rawUnit;
      // Clean productName
      productName = nameAndQtyPart.replaceFirst(qtyMatch.group(0)!, '').trim();
    } else {
      // Look for standalone number e.g. "Soap 5 150"
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
    productName = productName.replaceAll(RegExp(r'[@x\-:=]+$'), '').trim();
    if (productName.isEmpty) {
      productName = 'Item ${priceDouble.round()}';
    }

    final totalPaise = (priceDouble * 100).round();
    final unitCostPaise = qty > 0 ? (totalPaise / qty).round() : totalPaise;
    // Estimated retail selling price (15% margin)
    final sellingPricePaise = (unitCostPaise * 1.15).round();
    final mrpPaise = (unitCostPaise * 1.20).round();

    return ExtractedBillItem(
      productName: productName,
      quantity: qty,
      unit: unit,
      purchasePricePaise: unitCostPaise,
      sellingPricePaise: sellingPricePaise,
      mrpPaise: mrpPaise,
      categoryName: 'General',
    );
  }

  void dispose() {
    _textRecognizer.close();
  }
}
