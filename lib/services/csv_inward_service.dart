import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import '../core/utils/money_formatter.dart';
import 'gemini_ai_service.dart';

class CsvInwardResult {
  final bool success;
  final String? errorMessage;
  final List<ExtractedBillItem> items;
  final String? fileName;

  CsvInwardResult({
    required this.success,
    this.errorMessage,
    this.items = const [],
    this.fileName,
  });
}

class CsvInwardService {
  /// Opens file picker for CSV, TSV or text files and parses rows offline into [ExtractedBillItem]
  static Future<CsvInwardResult> pickAndParseCsv() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt', 'tsv'],
      );

      if (files.isEmpty) {
        return CsvInwardResult(success: false, errorMessage: 'No file selected.');
      }

      final file = files.first;
      final bytes = await file.readAsBytes();
      String content;

      try {
        content = utf8.decode(bytes);
      } catch (_) {
        content = latin1.decode(bytes);
      }

      final items = parseCsvContent(content);
      if (items.isEmpty) {
        return CsvInwardResult(
          success: false,
          errorMessage: 'No valid inventory rows found in "${file.name}". Please ensure headers like "Item Name", "Quantity", and "Price" exist.',
          fileName: file.name,
        );
      }

      return CsvInwardResult(
        success: true,
        items: items,
        fileName: file.name,
      );
    } catch (e) {
      return CsvInwardResult(success: false, errorMessage: 'Failed to process file: $e');
    }
  }

  /// Parses raw CSV/TSV text content into [ExtractedBillItem] list
  static List<ExtractedBillItem> parseCsvContent(String content) {
    final lines = const LineSplitter().convert(content).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.length < 2) return [];

    // Detect delimiter: comma, tab, or semicolon
    final firstLine = lines.first;
    String delimiter = ',';
    if (firstLine.contains('\t')) {
      delimiter = '\t';
    } else if (firstLine.contains(';') && !firstLine.contains(',')) {
      delimiter = ';';
    }

    // Helper to split CSV respecting simple quotes
    List<String> splitRow(String row) {
      final List<String> cells = [];
      final StringBuffer current = StringBuffer();
      bool inQuotes = false;

      for (int i = 0; i < row.length; i++) {
        final char = row[i];
        if (char == '"') {
          inQuotes = !inQuotes;
        } else if (char == delimiter && !inQuotes) {
          cells.add(current.toString().trim());
          current.clear();
        } else {
          current.write(char);
        }
      }
      cells.add(current.toString().trim());
      return cells.map((c) => c.replaceAll('"', '').trim()).toList();
    }

    final headers = splitRow(lines.first).map((h) => h.toLowerCase()).toList();

    // Map column indices
    int nameCol = -1;
    int qtyCol = -1;
    int unitCol = -1;
    int purchaseCol = -1;
    int mrpCol = -1;
    int sellingCol = -1;
    int catCol = -1;

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i];
      if (nameCol == -1 && (h.contains('item') || h.contains('product') || h.contains('name') || h.contains('description') || h.contains('title') || h.contains('particular'))) {
        nameCol = i;
      } else if (qtyCol == -1 && (h == 'qty' || h.contains('quantity') || h.contains('count') || h.contains('pcs') || h.contains('nos'))) {
        qtyCol = i;
      } else if (unitCol == -1 && (h == 'unit' || h == 'uom' || h == 'uqc' || h.contains('measure'))) {
        unitCol = i;
      } else if (purchaseCol == -1 && (h.contains('purchase') || h.contains('cost') || h.contains('buy') || h.contains('rate') || h == 'price' || h.contains('pur rate'))) {
        purchaseCol = i;
      } else if (mrpCol == -1 && (h.contains('mrp') || h.contains('maximum retail'))) {
        mrpCol = i;
      } else if (sellingCol == -1 && (h.contains('sell') || h.contains('sale') || h.contains('retail') || h.contains('sp'))) {
        sellingCol = i;
      } else if (catCol == -1 && (h.contains('category') || h.contains('group') || h.contains('dept'))) {
        catCol = i;
      }
    }

    // If name column not detected, assume first column
    if (nameCol == -1 && headers.isNotEmpty) nameCol = 0;

    final List<ExtractedBillItem> items = [];

    for (int r = 1; r < lines.length; r++) {
      final cells = splitRow(lines[r]);
      if (cells.isEmpty || (nameCol < cells.length && cells[nameCol].isEmpty)) continue;

      final name = nameCol < cells.length ? cells[nameCol] : '';
      if (name.isEmpty) continue;

      // Quantity
      double qty = 1.0;
      if (qtyCol != -1 && qtyCol < cells.length) {
        final rawQty = cells[qtyCol].replaceAll(RegExp(r'[^0-9.]'), '');
        qty = double.tryParse(rawQty) ?? 1.0;
        if (qty <= 0) qty = 1.0;
      }

      // Unit
      String unit = 'pcs';
      if (unitCol != -1 && unitCol < cells.length && cells[unitCol].isNotEmpty) {
        unit = cells[unitCol].toLowerCase();
      }

      // Purchase price paise
      int purchasePaise = 0;
      if (purchaseCol != -1 && purchaseCol < cells.length) {
        purchasePaise = MoneyFormatter.parseRupeesToPaise(cells[purchaseCol]);
      }

      // MRP paise
      int mrpPaise = 0;
      if (mrpCol != -1 && mrpCol < cells.length) {
        mrpPaise = MoneyFormatter.parseRupeesToPaise(cells[mrpCol]);
      }
      if (mrpPaise == 0 && purchasePaise > 0) {
        mrpPaise = (purchasePaise * 1.2).round();
      }

      // Selling price paise
      int sellingPaise = 0;
      if (sellingCol != -1 && sellingCol < cells.length) {
        sellingPaise = MoneyFormatter.parseRupeesToPaise(cells[sellingCol]);
      }
      if (sellingPaise == 0 && purchasePaise > 0) {
        sellingPaise = (purchasePaise * 1.15).round();
      }

      // Category
      String category = 'General';
      if (catCol != -1 && catCol < cells.length && cells[catCol].isNotEmpty) {
        category = cells[catCol];
      }

      items.add(ExtractedBillItem(
        productName: name,
        quantity: qty,
        unit: unit,
        purchasePricePaise: purchasePaise,
        mrpPaise: mrpPaise,
        sellingPricePaise: sellingPaise,
        categoryName: category,
      ));
    }

    return items;
  }

  /// Generates a standard sample inward CSV template with realistic items for Indian retail
  static String generateSampleInwardCsv({String businessType = 'grocery'}) {
    final buffer = StringBuffer();
    buffer.writeln('Item Name,Quantity,Unit,Purchase Price,MRP,Selling Price,Category,Barcode,Expiry Date');

    if (businessType == 'pharmacy') {
      buffer.writeln('Paracetamol 650mg (Strip 10),20,strip,18.50,32.00,30.00,Medicines,8901234567890,2026-12-31');
      buffer.writeln('Azithromycin 500mg (Strip 3),15,strip,45.00,75.00,70.00,Antibiotics,8901234567891,2026-10-31');
      buffer.writeln('Cetirizine 10mg (Strip 10),30,strip,8.00,18.00,16.00,Antiallergic,8901234567892,2027-05-31');
      buffer.writeln('Volini Spray 100g,10,pcs,120.00,170.00,160.00,Pain Relief,8901234567893,2026-08-31');
      buffer.writeln('Dettol Antiseptic Liquid 250ml,12,btl,110.00,145.00,140.00,First Aid,8901234567894,2027-03-31');
    } else if (businessType == 'restaurant') {
      buffer.writeln('Basmati Rice Premium (5kg),10,bag,350.00,450.00,450.00,Grains,8901234567880,2026-11-30');
      buffer.writeln('Fortune Sunflower Oil (1L),24,pkt,105.00,135.00,135.00,Oils,8901234567881,2026-09-30');
      buffer.writeln('Amul Fresh Cream 250ml,15,pkt,55.00,70.00,70.00,Dairy,8901234567882,2026-06-30');
      buffer.writeln('Paneer Fresh 1kg,8,kg,280.00,350.00,350.00,Dairy,8901234567883,2026-04-15');
      buffer.writeln('Everest Garam Masala 100g,20,box,62.00,82.00,82.00,Spices,8901234567884,2027-01-31');
    } else if (businessType == 'apparel') {
      buffer.writeln('Men Cotton T-Shirt Round Neck,50,pcs,180.00,499.00,399.00,Men,8901234567870,');
      buffer.writeln('Men Slim Fit Denim Jeans 32,25,pcs,450.00,1299.00,999.00,Men,8901234567871,');
      buffer.writeln('Women Cotton Kurti M,30,pcs,250.00,799.00,599.00,Women,8901234567872,');
      buffer.writeln('Boys Casual Shorts,20,pcs,120.00,349.00,249.00,Kids,8901234567873,');
    } else {
      // Default: Grocery / FMCG
      buffer.writeln('Aashirvaad Shudh Chakki Atta 5kg,10,bag,210.00,265.00,250.00,Grocery,8901030012345,2026-11-30');
      buffer.writeln('Tata Salt Vaccum Evaporated 1kg,50,pkt,21.00,28.00,26.00,Spices,8901030054321,2027-04-30');
      buffer.writeln('Fortune Sunlite Sunflower Oil 1L,20,pkt,108.00,140.00,132.00,Oils,8901030067890,2026-10-31');
      buffer.writeln('Surf Excel Easy Wash 1kg,15,pkt,115.00,150.00,142.00,Cleaning,8901030099887,2027-06-30');
      buffer.writeln('Maggi 2-Minute Noodles 70g,96,pkt,11.50,14.00,14.00,Snacks,8901030077665,2026-12-31');
    }

    return buffer.toString();
  }
}
