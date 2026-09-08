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
}
