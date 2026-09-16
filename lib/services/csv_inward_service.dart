import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

import '../core/utils/money_formatter.dart';
import 'gemini_ai_service.dart';
import 'inventory_inward_service.dart';

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
        // .xlsx is what a distributor actually sends, and what every button in
        // this app has always called "Upload Excel / CSV". It was not in this
        // list, so an Excel file could not even be SELECTED in the picker —
        // the label promised something the code refused.
        allowedExtensions: ['xlsx', 'xls', 'csv', 'txt', 'tsv'],
      );

      if (files.isEmpty) {
        return CsvInwardResult(success: false, errorMessage: 'No file selected.');
      }

      final file = files.first;
      final bytes = await file.readAsBytes();
      final lowerName = file.name.toLowerCase();

      final List<ExtractedBillItem> items;
      if (lowerName.endsWith('.xlsx') || lowerName.endsWith('.xls')) {
        items = parseExcelBytes(bytes);
      } else {
        String content;
        try {
          content = utf8.decode(bytes);
        } catch (_) {
          content = latin1.decode(bytes);
        }
        items = parseCsvContent(content);
      }

      if (items.isEmpty) {
        return CsvInwardResult(
          success: false,
          errorMessage: lowerName.endsWith('.xls') && !lowerName.endsWith('.xlsx')
              ? 'Could not read "${file.name}". The old .xls format is not supported — open it in Excel and "Save As" .xlsx or .csv.'
              : 'No valid inventory rows found in "${file.name}". Please ensure the first row has headers like "Item Name", "Quantity", "Purchase Price".',
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

  /// Reads a `.xlsx` workbook into inventory rows, entirely on-device.
  ///
  /// Excel support exists because "Upload Excel / CSV" is what every inward
  /// button in this app has always been labelled, while the picker accepted
  /// only `.csv` — and a distributor's stock list arrives as `.xlsx`. Asking a
  /// shopkeeper to open Excel and re-save as CSV before they can load 1000 SKUs
  /// is exactly the friction that makes someone give up on the app on day one.
  ///
  /// Takes the FIRST sheet with a usable header row. Column meaning is resolved
  /// by [mapColumns], the same logic the CSV path uses, so a file behaves
  /// identically whichever format it arrives in.
  static List<ExtractedBillItem> parseExcelBytes(Uint8List bytes) {
    late final Excel book;
    try {
      book = Excel.decodeBytes(bytes);
    } catch (_) {
      return [];
    }

    for (final sheetName in book.tables.keys) {
      final sheet = book.tables[sheetName];
      if (sheet == null || sheet.rows.length < 2) continue;

      String cellText(dynamic cell) {
        final v = cell?.value;
        if (v == null) return '';
        // The `excel` package wraps values in typed CellValue objects; their
        // toString() is the displayed text for every type this cares about.
        return v.toString().trim();
      }

      final headerRow = sheet.rows.first.map(cellText).toList();
      final cols = mapColumns(headerRow);
      // A sheet whose first row is not headers (a title banner, say) will map
      // nothing useful — skip to the next sheet rather than importing garbage.
      if (cols.name < 0) continue;

      final items = <ExtractedBillItem>[];
      for (int r = 1; r < sheet.rows.length; r++) {
        final row = sheet.rows[r].map(cellText).toList();
        final item = _rowToItem(row, cols);
        if (item != null) items.add(item);
      }
      if (items.isNotEmpty) return items;
    }
    return [];
  }

  /// Builds one inventory row from already-split cells. Shared by the Excel and
  /// CSV paths so the two can never drift apart on pricing or barcodes.
  static ExtractedBillItem? _rowToItem(
    List<String> cells,
    ({
      int name,
      int qty,
      int unit,
      int purchase,
      int mrp,
      int selling,
      int category,
      int barcode,
      int expiry,
    }) cols,
  ) {
    String at(int i) => (i >= 0 && i < cells.length) ? cells[i] : '';

    final name = at(cols.name).trim();
    if (name.isEmpty) return null;

    double qty = 1.0;
    final rawQty = at(cols.qty).replaceAll(RegExp(r'[^0-9.]'), '');
    if (rawQty.isNotEmpty) {
      qty = double.tryParse(rawQty) ?? 1.0;
      if (qty <= 0) qty = 1.0;
    }

    final unitRaw = at(cols.unit).trim();
    final unit = unitRaw.isEmpty ? 'pcs' : unitRaw.toLowerCase();

    final purchasePaise = MoneyFormatter.parseRupeesToPaise(at(cols.purchase));
    var mrpPaise = MoneyFormatter.parseRupeesToPaise(at(cols.mrp));
    var sellingPaise = MoneyFormatter.parseRupeesToPaise(at(cols.selling));

    if (mrpPaise == 0 && purchasePaise > 0) {
      mrpPaise = InventoryInwardService.defaultMrpPaise(purchasePaise);
    }
    if (sellingPaise == 0 && purchasePaise > 0) {
      sellingPaise = InventoryInwardService.defaultSellingPricePaise(purchasePaise);
    }

    final catRaw = at(cols.category).trim();

    String? barcode;
    final digits = at(cols.barcode).replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 8 && digits.length <= 14) barcode = digits;

    return ExtractedBillItem(
      productName: name,
      quantity: qty,
      unit: unit,
      purchasePricePaise: purchasePaise,
      mrpPaise: mrpPaise,
      sellingPricePaise: sellingPaise,
      categoryName: catRaw.isEmpty ? 'General' : catRaw,
      barcode: barcode,
      expiryDate: normalizeExpiry(at(cols.expiry)),
    );
  }

  /// Which spreadsheet column holds what. -1 means "not present".
  static ({
    int name,
    int qty,
    int unit,
    int purchase,
    int mrp,
    int selling,
    int category,
    int barcode,
    int expiry,
  }) mapColumns(List<String> rawHeaders) {
    final headers = rawHeaders.map((h) => h.toLowerCase().trim()).toList();

    int find(bool Function(String h) match, {Set<int> taken = const {}}) {
      for (int i = 0; i < headers.length; i++) {
        if (taken.contains(i)) continue;
        if (match(headers[i])) return i;
      }
      return -1;
    }

    // Order matters, and it is deliberately most-specific-first. The previous
    // implementation walked the headers ONCE with an if/else-if chain, so the
    // first rule that matched a column won it — and the purchase rule
    // (which includes 'rate') ran before the selling rule. A sheet with a
    // "Sale Rate" column had its SELLING price silently read as the cost.
    final barcode = find((h) =>
        h.contains('barcode') || h == 'ean' || h == 'upc' || h.contains('bar code'));
    final expiry = find((h) => h.contains('expiry') || h.contains('exp date') || h == 'exp');
    final mrp = find((h) => h.contains('mrp') || h.contains('maximum retail'));

    final taken = <int>{if (barcode >= 0) barcode, if (expiry >= 0) expiry, if (mrp >= 0) mrp};

    final selling = find(
        (h) => h.contains('sell') || h.contains('sale') || h.contains('retail') || h == 'sp',
        taken: taken);
    if (selling >= 0) taken.add(selling);

    final purchase = find(
        (h) =>
            h.contains('purchase') ||
            h.contains('cost') ||
            h.contains('buy') ||
            h == 'rate' ||
            h == 'price' ||
            h.contains('pur rate'),
        taken: taken);
    if (purchase >= 0) taken.add(purchase);

    final qty = find(
        (h) => h == 'qty' || h.contains('quantity') || h.contains('count') || h == 'nos',
        taken: taken);
    if (qty >= 0) taken.add(qty);

    final unit = find((h) => h == 'unit' || h == 'uom' || h == 'uqc' || h.contains('measure'),
        taken: taken);
    if (unit >= 0) taken.add(unit);

    final category =
        find((h) => h.contains('category') || h.contains('group') || h.contains('dept'), taken: taken);
    if (category >= 0) taken.add(category);

    var name = find(
        (h) =>
            h.contains('item') ||
            h.contains('product') ||
            h.contains('name') ||
            h.contains('description') ||
            h.contains('title') ||
            h.contains('particular'),
        taken: taken);
    // Nothing recognisable: the first column of a stock sheet is the item.
    if (name == -1 && headers.isNotEmpty) name = 0;

    return (
      name: name,
      qty: qty,
      unit: unit,
      purchase: purchase,
      mrp: mrp,
      selling: selling,
      category: category,
      barcode: barcode,
      expiry: expiry,
    );
  }

  /// Normalises the many date spellings a supplier sheet uses into `YYYY-MM-DD`.
  /// Returns null for anything it cannot read confidently — a wrong expiry on a
  /// medicine is worse than no expiry.
  static String? normalizeExpiry(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    // Already ISO.
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
    if (iso != null) {
      final y = iso.group(1)!;
      final m = iso.group(2)!.padLeft(2, '0');
      final d = iso.group(3)!.padLeft(2, '0');
      return '$y-$m-$d';
    }

    // dd/MM/yyyy or dd-MM-yyyy (Indian sheets are day-first, not month-first).
    final dmy = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})$').firstMatch(s);
    if (dmy != null) {
      final d = int.parse(dmy.group(1)!);
      final m = int.parse(dmy.group(2)!);
      var y = int.parse(dmy.group(3)!);
      if (y < 100) y += 2000;
      if (m < 1 || m > 12 || d < 1 || d > 31) return null;
      return '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
    }

    // MM/yyyy or MM-yy — the usual pharmacy strip format. Treated as the LAST
    // day is unknown, so the 1st is used; callers only compare month-level.
    final my = RegExp(r'^(\d{1,2})[/\-.](\d{2,4})$').firstMatch(s);
    if (my != null) {
      final m = int.parse(my.group(1)!);
      var y = int.parse(my.group(2)!);
      if (y < 100) y += 2000;
      if (m < 1 || m > 12) return null;
      return '$y-${m.toString().padLeft(2, '0')}-01';
    }

    return null;
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
    final cols = mapColumns(headers);
    final nameCol = cols.name;
    final qtyCol = cols.qty;
    final unitCol = cols.unit;
    final purchaseCol = cols.purchase;
    final mrpCol = cols.mrp;
    final sellingCol = cols.selling;
    final catCol = cols.category;
    final barcodeCol = cols.barcode;
    final expiryCol = cols.expiry;

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
      // Selling price paise
      int sellingPaise = 0;
      if (sellingCol != -1 && sellingCol < cells.length) {
        sellingPaise = MoneyFormatter.parseRupeesToPaise(cells[sellingCol]);
      }

      // Missing prices fall back to the SHARED markup helpers rather than the
      // inline 1.2 / 1.15 that used to live here. Same numbers, but one
      // definition — an item imported from a sheet cannot now be priced
      // differently from the identical item inwarded by hand or by AI scan.
      if (mrpPaise == 0 && purchasePaise > 0) {
        mrpPaise = InventoryInwardService.defaultMrpPaise(purchasePaise);
      }
      if (sellingPaise == 0 && purchasePaise > 0) {
        sellingPaise = InventoryInwardService.defaultSellingPricePaise(purchasePaise);
      }

      // Category
      String category = 'General';
      if (catCol != -1 && catCol < cells.length && cells[catCol].isNotEmpty) {
        category = cells[catCol];
      }

      // Barcode — digits only. The app's own sample template has always had
      // this column and the parser ignored it completely, so every bulk import
      // produced products that could never be scanned at the counter.
      String? barcode;
      if (barcodeCol != -1 && barcodeCol < cells.length) {
        final digits = cells[barcodeCol].replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length >= 8 && digits.length <= 14) barcode = digits;
      }

      // Expiry — same story as barcode, and it is what drives the pharmacy
      // FEFO batch rows and the Near Expiry radar.
      String? expiry;
      if (expiryCol != -1 && expiryCol < cells.length) {
        expiry = normalizeExpiry(cells[expiryCol]);
      }

      items.add(ExtractedBillItem(
        productName: name,
        quantity: qty,
        unit: unit,
        purchasePricePaise: purchasePaise,
        mrpPaise: mrpPaise,
        sellingPricePaise: sellingPaise,
        categoryName: category,
        barcode: barcode,
        expiryDate: expiry,
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
