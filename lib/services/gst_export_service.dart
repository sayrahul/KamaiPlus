import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../core/utils/money_formatter.dart';

class HsnSummaryItem {
  final String hsn;
  final String desc;
  final double rate;
  final String uqc;
  int qty;
  int taxablePaise;
  int cgstPaise;
  int sgstPaise;
  int igstPaise;
  int totalTaxPaise;
  int totalPaise;

  HsnSummaryItem({
    required this.hsn,
    required this.desc,
    required this.rate,
    required this.uqc,
    this.qty = 0,
    this.taxablePaise = 0,
    this.cgstPaise = 0,
    this.sgstPaise = 0,
    this.igstPaise = 0,
    this.totalTaxPaise = 0,
    this.totalPaise = 0,
  });

  Map<String, dynamic> toMap() => {
    'hsn': hsn,
    'desc': desc,
    'rate': '${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}%',
    'uqc': uqc,
    'qty': qty,
    'taxable_paise': taxablePaise,
    'cgst_paise': cgstPaise,
    'sgst_paise': sgstPaise,
    'igst_paise': igstPaise,
    'total_tax_paise': totalTaxPaise,
    'total_paise': totalPaise,
  };
}

/// Resolved filing period with month and year for GSTR-1 `fp` field.
class FilingPeriod {
  final int month;
  final int year;
  FilingPeriod(this.month, this.year);

  /// GSTR-1 fp format: MMYYYY (e.g. 092026)
  String toFp() => '${month.toString().padLeft(2, '0')}$year';
}

class GstExportService {
  static final GstExportService instance = GstExportService._();
  GstExportService._();

  /// Resolves a human-readable period label to the correct filing month/year.
  /// For quarterly periods, returns the LAST month of the quarter (GST convention).
  FilingPeriod resolveFilingPeriod(String period) {
    final now = DateTime.now();
    switch (period) {
      case 'This Month':
        return FilingPeriod(now.month, now.year);
      case 'Last Month':
        final target = DateTime(now.year, now.month - 1);
        return FilingPeriod(target.month, target.year);
      case 'Q1 (Apr-Jun)':
        return FilingPeriod(6, now.year); // June
      case 'Q2 (Jul-Sep)':
        return FilingPeriod(9, now.year); // September
      case 'Q3 (Oct-Dec)':
        return FilingPeriod(12, now.year); // December
      case 'Q4 (Jan-Mar)':
        return FilingPeriod(3, now.year); // March
      default:
        return FilingPeriod(now.month, now.year);
    }
  }

  /// Extracts the 2-digit state code from a GSTIN (first 2 chars).
  /// Returns null if GSTIN is invalid or too short.
  String? _stateCodeFromGstin(String? gstin) {
    if (gstin == null || gstin.trim().length < 2) return null;
    return gstin.trim().substring(0, 2);
  }

  /// Determines if a sale is inter-state (IGST) based on buyer vs seller state code.
  /// Returns true for inter-state (IGST), false for intra-state (CGST+SGST).
  bool _isInterState({
    required StoreProfileModel profile,
    String? buyerGstin,
    String? placeOfSupply,
  }) {
    final sellerState = _stateCodeFromGstin(profile.gstin);
    if (sellerState == null) return false; // Can't determine — default INTRA

    // Prefer placeOfSupply if available, then buyer GSTIN state
    final buyerState = placeOfSupply?.trim().isNotEmpty == true
        ? placeOfSupply!.trim().substring(0, 2.clamp(0, placeOfSupply.trim().length))
        : _stateCodeFromGstin(buyerGstin);

    if (buyerState == null) return false; // Unknown buyer state — default INTRA
    return buyerState != sellerState;
  }

  /// Compiles Table 12 HSN Summary from real sales and store products.
  /// Filters out refunded/returned sales.
  List<HsnSummaryItem> generateHsnSummary({
    required List<SaleModel> sales,
    required Map<String, ProductModel> productsMap,
    StoreProfileModel? profile,
  }) {
    final Map<String, HsnSummaryItem> summaryMap = {};

    // Filter out refunded/returned sales
    final activeSales = sales.where((s) => !s.isRefunded).toList();

    for (final sale in activeSales) {
      for (final item in sale.items) {
        final prodId = item['product_id']?.toString() ?? '';
        final prodName = item['product_name']?.toString() ?? 'Retail Item';
        final product = productsMap[prodId];

        // Resolve HSN code: item json -> product model -> fallback code
        String hsn = (item['hsn_code'] ?? product?.hsnCode ?? '').toString().trim();
        if (hsn.isEmpty) {
          hsn = _inferHsnFromCategory(product?.businessType ?? 'grocery', prodName);
        }

        final double rate = (item['tax_rate'] as num?)?.toDouble() ??
            product?.taxRate ??
            0.0;
        final String uqc = (item['unit'] ?? product?.unit ?? 'PCS').toString().toUpperCase();

        final num qtyNum = (item['quantity'] as num?) ?? 1;
        final int qty = qtyNum.round().clamp(1, 999999);

        final int grossPaise = (item['gross_total_paise'] as num?)?.toInt() ??
            (((item['unit_price_paise'] as num?)?.toInt() ?? 0) * qty);

        final bool isInclusive = item['is_tax_inclusive'] != null
            ? (item['is_tax_inclusive'] == 1 || item['is_tax_inclusive'] == true)
            : (product?.isTaxInclusive ?? true);

        int taxablePaise;
        int taxPaise;

        if (rate > 0) {
          if (isInclusive) {
            taxablePaise = (grossPaise / (1.0 + (rate / 100.0))).round();
            taxPaise = grossPaise - taxablePaise;
          } else {
            taxablePaise = grossPaise;
            taxPaise = (taxablePaise * (rate / 100.0)).round();
          }
        } else {
          taxablePaise = grossPaise;
          taxPaise = 0;
        }

        // Determine IGST vs CGST/SGST split
        final bool isInterState = profile != null && _isInterState(
          profile: profile,
          buyerGstin: sale.customerGstin,
          placeOfSupply: sale.placeOfSupply,
        );

        int cgstPaise, sgstPaise, igstPaise;
        if (isInterState) {
          igstPaise = taxPaise;
          cgstPaise = 0;
          sgstPaise = 0;
        } else {
          cgstPaise = (taxPaise / 2).round();
          sgstPaise = taxPaise - cgstPaise;
          igstPaise = 0;
        }

        final key = '${hsn}_${rate.toStringAsFixed(1)}_$uqc';
        if (!summaryMap.containsKey(key)) {
          summaryMap[key] = HsnSummaryItem(
            hsn: hsn,
            desc: prodName,
            rate: rate,
            uqc: uqc,
          );
        }

        final existing = summaryMap[key]!;
        existing.qty += qty;
        existing.taxablePaise += taxablePaise;
        existing.cgstPaise += cgstPaise;
        existing.sgstPaise += sgstPaise;
        existing.igstPaise += igstPaise;
        existing.totalTaxPaise += taxPaise;
        existing.totalPaise += grossPaise;
      }
    }

    final list = summaryMap.values.toList();
    list.sort((a, b) => b.taxablePaise.compareTo(a.taxablePaise));
    return list;
  }

  /// 1. REAL CA EXCEL (GSTR-1 CSV FORMAT)
  Future<File> generateCaExcelCsv({
    required StoreProfileModel profile,
    required String period,
    required List<SaleModel> sales,
    required List<HsnSummaryItem> hsnList,
  }) async {
    // Filter out refunded/returned sales for the CSV register
    final activeSales = sales.where((s) => !s.isRefunded).toList();

    final buffer = StringBuffer();

    // Store & Audit Header
    buffer.writeln('KAMAI+ GST COMPLIANCE REPORT - OFFICIAL CA AUDIT FORMAT');
    buffer.writeln('Store Name,"${_escapeCsv(profile.storeName)}"');
    buffer.writeln('Store GSTIN,"${profile.gstin.isNotEmpty ? profile.gstin : "UNREGISTERED / COMPOSITION"}"');
    buffer.writeln('Owner Name,"${_escapeCsv(profile.ownerName)}"');
    buffer.writeln('Registered Mobile,"${profile.phone}"');
    buffer.writeln('Return Period,"$period"');
    buffer.writeln('Generated At,"${DateTime.now().toLocal().toString()}"');
    buffer.writeln('');

    // Summary Totals
    final totalTaxablePaise = hsnList.fold(0, (sum, i) => sum + i.taxablePaise);
    final totalCgstPaise = hsnList.fold(0, (sum, i) => sum + i.cgstPaise);
    final totalSgstPaise = hsnList.fold(0, (sum, i) => sum + i.sgstPaise);
    final totalIgstPaise = hsnList.fold(0, (sum, i) => sum + i.igstPaise);
    final totalTaxPaise = hsnList.fold(0, (sum, i) => sum + i.totalTaxPaise);
    final totalTurnoverPaise = hsnList.fold(0, (sum, i) => sum + i.totalPaise);

    buffer.writeln('TAX COMPUTATION SUMMARY (INTEGER PAISE PRECISION)');
    buffer.writeln('Gross Turnover (INR),${(totalTurnoverPaise / 100.0).toStringAsFixed(2)}');
    buffer.writeln('Taxable Value (INR),${(totalTaxablePaise / 100.0).toStringAsFixed(2)}');
    buffer.writeln('Central GST CGST (INR),${(totalCgstPaise / 100.0).toStringAsFixed(2)}');
    buffer.writeln('State GST SGST (INR),${(totalSgstPaise / 100.0).toStringAsFixed(2)}');
    buffer.writeln('Integrated GST IGST (INR),${(totalIgstPaise / 100.0).toStringAsFixed(2)}');
    buffer.writeln('Total GST Payable (INR),${(totalTaxPaise / 100.0).toStringAsFixed(2)}');
    buffer.writeln('');

    // Section 1: Table 12 HSN Summary
    buffer.writeln('TABLE 12: HSN SUMMARY OF OUTWARD SUPPLIES');
    buffer.writeln('HSN Code,Description,UQC,Total Qty,Tax Rate,Taxable Value (INR),CGST (INR),SGST (INR),IGST (INR),Total Tax (INR),Gross Value (INR)');
    for (final item in hsnList) {
      buffer.writeln(
        '"${item.hsn}","${_escapeCsv(item.desc)}","${item.uqc}",${item.qty},"${item.rate}%",'
        '${(item.taxablePaise / 100.0).toStringAsFixed(2)},'
        '${(item.cgstPaise / 100.0).toStringAsFixed(2)},'
        '${(item.sgstPaise / 100.0).toStringAsFixed(2)},'
        '${(item.igstPaise / 100.0).toStringAsFixed(2)},'
        '${(item.totalTaxPaise / 100.0).toStringAsFixed(2)},'
        '${(item.totalPaise / 100.0).toStringAsFixed(2)}',
      );
    }
    buffer.writeln('');

    // Section 2: Table 7 B2C & Sales Invoices Register
    buffer.writeln('SALES REGISTER (DETAILED INVOICES)');
    buffer.writeln('Invoice No,Date,Customer Name,Customer Phone,Payment Mode,Subtotal (INR),Tax (INR),Discount (INR),Total Bill (INR),Status');
    for (final sale in activeSales) {
      buffer.writeln(
        '"${sale.invoiceNumber}","${sale.createdAt.toLocal().toString().substring(0, 19)}",'
        '"${_escapeCsv(sale.customerName ?? "Walk-in Customer")}","${sale.customerPhone ?? "-"}","${sale.paymentMethod.toUpperCase()}",'
        '${(sale.subtotalPaise / 100.0).toStringAsFixed(2)},'
        '${(sale.taxAmountPaise / 100.0).toStringAsFixed(2)},'
        '${(sale.discountPaise / 100.0).toStringAsFixed(2)},'
        '${(sale.totalAmountPaise / 100.0).toStringAsFixed(2)},'
        '"${sale.status}"',
      );
    }

    final tempDir = await getTemporaryDirectory();
    final cleanPeriod = period.replaceAll(RegExp(r'[^\w\d]'), '_');
    final file = File('${tempDir.path}/kamaiplus_gst_report_$cleanPeriod.csv');
    await file.writeAsString(buffer.toString(), flush: true);
    return file;
  }

  /// 2. REAL TALLY PRIME / ERP XML EXPORT
  Future<File> generateTallyXml({
    required StoreProfileModel profile,
    required String period,
    required List<SaleModel> sales,
  }) async {
    // Filter out refunded/returned sales
    final activeSales = sales.where((s) => !s.isRefunded).toList();

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="utf-8"?>');
    buffer.writeln('<ENVELOPE>');
    buffer.writeln('  <HEADER>');
    buffer.writeln('    <TALLYREQUEST>Import Data</TALLYREQUEST>');
    buffer.writeln('  </HEADER>');
    buffer.writeln('  <BODY>');
    buffer.writeln('    <IMPORTDATA>');
    buffer.writeln('      <REQUESTDESC>');
    buffer.writeln('        <REPORTNAME>Vouchers</REPORTNAME>');
    buffer.writeln('        <STATICVARIABLES>');
    buffer.writeln('          <SVCURRENTCOMPANY>${_escapeXml(profile.storeName)}</SVCURRENTCOMPANY>');
    buffer.writeln('        </STATICVARIABLES>');
    buffer.writeln('      </REQUESTDESC>');
    buffer.writeln('      <REQUESTDATA>');

    for (final sale in activeSales) {
      final dateStr = '${sale.createdAt.year}${sale.createdAt.month.toString().padLeft(2, '0')}${sale.createdAt.day.toString().padLeft(2, '0')}';
      final totalRupees = (sale.totalAmountPaise / 100.0).toStringAsFixed(2);
      final taxableRupees = (sale.subtotalPaise / 100.0).toStringAsFixed(2);
      final cgstRupees = ((sale.taxAmountPaise / 2) / 100.0).toStringAsFixed(2);
      final sgstRupees = ((sale.taxAmountPaise - (sale.taxAmountPaise / 2).round()) / 100.0).toStringAsFixed(2);

      buffer.writeln('        <TALLYMESSAGE xmlns:UDF="TallyUDF">');
      buffer.writeln('          <VOUCHER VCHTYPE="Sales" ACTION="Create">');
      buffer.writeln('            <DATE>$dateStr</DATE>');
      buffer.writeln('            <EFFECTIVEDATE>$dateStr</EFFECTIVEDATE>');
      buffer.writeln('            <VOUCHERTYPENAME>Sales</VOUCHERTYPENAME>');
      buffer.writeln('            <VOUCHERNUMBER>${_escapeXml(sale.invoiceNumber)}</VOUCHERNUMBER>');
      buffer.writeln('            <PARTYLEDGERNAME>${_escapeXml(sale.customerName ?? "Cash")}</PARTYLEDGERNAME>');
      buffer.writeln('            <BASICBASEPARTYNAME>${_escapeXml(sale.customerName ?? "Cash")}</BASICBASEPARTYNAME>');
      buffer.writeln('            <NARRATION>Kamai+ Bill #${sale.invoiceNumber} via ${sale.paymentMethod.toUpperCase()}</NARRATION>');
      buffer.writeln('            <ISINVOICE>Yes</ISINVOICE>');
      
      // Debit: Customer / Cash ledger
      buffer.writeln('            <ALLLEDGERENTRIES.LIST>');
      buffer.writeln('              <LEDGERNAME>${_escapeXml(sale.customerName ?? (sale.paymentMethod == "upi" ? "Bank Account" : "Cash"))}</LEDGERNAME>');
      buffer.writeln('              <ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE>');
      buffer.writeln('              <AMOUNT>-$totalRupees</AMOUNT>');
      buffer.writeln('            </ALLLEDGERENTRIES.LIST>');

      // Credit: Sales Account
      buffer.writeln('            <ALLLEDGERENTRIES.LIST>');
      buffer.writeln('              <LEDGERNAME>Sales Account</LEDGERNAME>');
      buffer.writeln('              <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>');
      buffer.writeln('              <AMOUNT>$taxableRupees</AMOUNT>');
      buffer.writeln('            </ALLLEDGERENTRIES.LIST>');

      // Credit: CGST Output
      if (sale.taxAmountPaise > 0) {
        buffer.writeln('            <ALLLEDGERENTRIES.LIST>');
        buffer.writeln('              <LEDGERNAME>Output CGST</LEDGERNAME>');
        buffer.writeln('              <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>');
        buffer.writeln('              <AMOUNT>$cgstRupees</AMOUNT>');
        buffer.writeln('            </ALLLEDGERENTRIES.LIST>');

        // Credit: SGST Output
        buffer.writeln('            <ALLLEDGERENTRIES.LIST>');
        buffer.writeln('              <LEDGERNAME>Output SGST</LEDGERNAME>');
        buffer.writeln('              <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>');
        buffer.writeln('              <AMOUNT>$sgstRupees</AMOUNT>');
        buffer.writeln('            </ALLLEDGERENTRIES.LIST>');
      }

      buffer.writeln('          </VOUCHER>');
      buffer.writeln('        </TALLYMESSAGE>');
    }

    buffer.writeln('      </REQUESTDATA>');
    buffer.writeln('    </IMPORTDATA>');
    buffer.writeln('  </BODY>');
    buffer.writeln('</ENVELOPE>');

    final tempDir = await getTemporaryDirectory();
    final cleanPeriod = period.replaceAll(RegExp(r'[^\w\d]'), '_');
    final file = File('${tempDir.path}/kamaiplus_tally_sales_$cleanPeriod.xml');
    await file.writeAsString(buffer.toString(), flush: true);
    return file;
  }

  /// 3. OFFICIAL GSTR-1 OFFLINE PORTAL JSON
  /// Throws [ArgumentError] if store GSTIN is not configured (B4 fix).
  Future<File> generateGstr1Json({
    required StoreProfileModel profile,
    required String period,
    required List<SaleModel> sales,
    required List<HsnSummaryItem> hsnList,
    required Map<String, CustomerModel> customersMap,
  }) async {
    // B4: Block export if GSTIN not set — no fake placeholder
    if (profile.gstin.trim().isEmpty) {
      throw ArgumentError(
        'Store GSTIN is not configured. Please set your GSTIN in Settings > Store Profile before exporting GSTR-1 JSON.',
      );
    }

    // B2: Use selected period to derive correct filing period, NOT DateTime.now()
    final fp = resolveFilingPeriod(period);
    final sellerStateCode = _stateCodeFromGstin(profile.gstin) ?? '27';

    // Filter out refunded/returned sales for turnover calculations
    final activeSales = sales.where((s) => !s.isRefunded).toList();
    // Refunded sales go into credit notes
    final refundedSales = sales.where((s) => s.isRefunded).toList();

    final totalTaxablePaise = hsnList.fold(0, (sum, i) => sum + i.taxablePaise);
    final totalTurnoverPaise = hsnList.fold(0, (sum, i) => sum + i.totalPaise);

    // --- Table 12: HSN Summary ---
    final hsnData = hsnList.asMap().entries.map((entry) {
      final idx = entry.key + 1;
      final i = entry.value;
      return {
        'num': idx,
        'hsn_sc': i.hsn,
        'desc': i.desc,
        'uqc': i.uqc,
        'qty': i.qty,
        'val': double.parse((i.totalPaise / 100.0).toStringAsFixed(2)),
        'txval': double.parse((i.taxablePaise / 100.0).toStringAsFixed(2)),
        'iamt': double.parse((i.igstPaise / 100.0).toStringAsFixed(2)),
        'camt': double.parse((i.cgstPaise / 100.0).toStringAsFixed(2)),
        'samt': double.parse((i.sgstPaise / 100.0).toStringAsFixed(2)),
        'csamt': 0.0,
      };
    }).toList();

    // --- B1: Table 4A B2B Invoices (sales with buyer GSTIN) ---
    final b2bSales = activeSales.where((s) {
      final saleGst = s.customerGstin?.trim();
      if (saleGst != null && saleGst.isNotEmpty) return true;
      if (s.customerId != null) {
        final cust = customersMap[s.customerId];
        if (cust != null && cust.gstin != null && cust.gstin!.trim().isNotEmpty) return true;
      }
      return false;
    }).toList();

    // Group B2B by buyer GSTIN
    final Map<String, List<SaleModel>> b2bGrouped = {};
    for (final sale in b2bSales) {
      String buyerGstin = sale.customerGstin?.trim() ?? '';
      if (buyerGstin.isEmpty && sale.customerId != null) {
        final cust = customersMap[sale.customerId];
        buyerGstin = cust?.gstin?.trim() ?? '';
      }
      if (buyerGstin.isNotEmpty) {
        b2bGrouped.putIfAbsent(buyerGstin, () => []).add(sale);
      }
    }

    final b2bArray = b2bGrouped.entries.map((entry) {
      final ctin = entry.key;
      final invoices = entry.value.map((sale) {
        final isInter = _isInterState(
          profile: profile,
          buyerGstin: ctin,
          placeOfSupply: sale.placeOfSupply,
        );

        // Calculate tax from sale items
        int saleTaxPaise = sale.taxAmountPaise;
        final taxRate = _dominantTaxRate(sale);

        return {
          'inum': sale.invoiceNumber,
          'idt': _formatDate(sale.createdAt),
          'val': double.parse((sale.totalAmountPaise / 100.0).toStringAsFixed(2)),
          'pos': _stateCodeFromGstin(ctin) ?? sellerStateCode,
          'rchrg': 'N',
          'inv_typ': 'R',
          'itms': [
            {
              'num': 1,
              'itm_det': {
                'txval': double.parse((sale.subtotalPaise / 100.0).toStringAsFixed(2)),
                'rt': taxRate,
                'iamt': isInter
                    ? double.parse((saleTaxPaise / 100.0).toStringAsFixed(2))
                    : 0.0,
                'camt': isInter
                    ? 0.0
                    : double.parse(((saleTaxPaise / 2) / 100.0).toStringAsFixed(2)),
                'samt': isInter
                    ? 0.0
                    : double.parse(((saleTaxPaise - (saleTaxPaise / 2).round()) / 100.0).toStringAsFixed(2)),
                'csamt': 0.0,
              },
            },
          ],
        };
      }).toList();

      return {
        'ctin': ctin,
        'inv': invoices,
      };
    }).toList();

    // --- Table 7: B2CS (B2C Small) — non-GSTIN sales grouped by rate ---
    final b2bSaleIds = b2bSales.map((s) => s.id).toSet();
    final b2cSales = activeSales.where((s) => !b2bSaleIds.contains(s.id)).toList();

    final Map<String, Map<String, dynamic>> b2csMap = {};
    for (final sale in b2cSales) {
      final isInter = _isInterState(
        profile: profile,
        placeOfSupply: sale.placeOfSupply,
      );
      final splyTy = isInter ? 'INTER' : 'INTRA';
      final pos = isInter
          ? (sale.placeOfSupply?.trim().substring(0, 2.clamp(0, (sale.placeOfSupply?.trim().length ?? 0))) ?? sellerStateCode)
          : sellerStateCode;
      final taxRate = _dominantTaxRate(sale);

      final key = '${splyTy}_${pos}_$taxRate';
      if (!b2csMap.containsKey(key)) {
        b2csMap[key] = {
          'sply_ty': splyTy,
          'pos': pos,
          'typ': 'OE',
          'rt': taxRate,
          'txval': 0.0,
          'iamt': 0.0,
          'camt': 0.0,
          'samt': 0.0,
          'csamt': 0.0,
        };
      }
      final cur = b2csMap[key]!;
      final txval = sale.subtotalPaise / 100.0;
      cur['txval'] = double.parse(((cur['txval'] as double) + txval).toStringAsFixed(2));
      if (isInter) {
        cur['iamt'] = double.parse(((cur['iamt'] as double) + (sale.taxAmountPaise / 100.0)).toStringAsFixed(2));
      } else {
        cur['camt'] = double.parse(((cur['camt'] as double) + ((sale.taxAmountPaise / 2) / 100.0)).toStringAsFixed(2));
        cur['samt'] = double.parse(((cur['samt'] as double) + ((sale.taxAmountPaise - (sale.taxAmountPaise / 2).round()) / 100.0)).toStringAsFixed(2));
      }
    }

    // --- B6: Credit Notes (CDNR for B2B returns, CDNUR for B2C returns) ---
    final cdnrMap = <String, List<Map<String, dynamic>>>{};
    final cdnurList = <Map<String, dynamic>>[];

    for (final sale in refundedSales) {
      String buyerGstin = sale.customerGstin?.trim() ?? '';
      if (buyerGstin.isEmpty && sale.customerId != null) {
        final cust = customersMap[sale.customerId];
        buyerGstin = cust?.gstin?.trim() ?? '';
      }

      final isInter = _isInterState(
        profile: profile,
        buyerGstin: buyerGstin.isNotEmpty ? buyerGstin : null,
        placeOfSupply: sale.placeOfSupply,
      );
      final taxRate = _dominantTaxRate(sale);
      final saleTaxPaise = sale.taxAmountPaise;

      final noteEntry = {
        'ntty': 'C',
        'nt_num': 'CN-${sale.invoiceNumber}',
        'nt_dt': _formatDate(sale.createdAt),
        'val': double.parse((sale.totalAmountPaise / 100.0).toStringAsFixed(2)),
        'pos': isInter
            ? (sale.placeOfSupply?.trim().substring(0, 2.clamp(0, (sale.placeOfSupply?.trim().length ?? 0))) ?? sellerStateCode)
            : sellerStateCode,
        'rchrg': 'N',
        'inv_typ': 'R',
        'itms': [
          {
            'num': 1,
            'itm_det': {
              'txval': double.parse((sale.subtotalPaise / 100.0).toStringAsFixed(2)),
              'rt': taxRate,
              'iamt': isInter
                  ? double.parse((saleTaxPaise / 100.0).toStringAsFixed(2))
                  : 0.0,
              'camt': isInter
                  ? 0.0
                  : double.parse(((saleTaxPaise / 2) / 100.0).toStringAsFixed(2)),
              'samt': isInter
                  ? 0.0
                  : double.parse(((saleTaxPaise - (saleTaxPaise / 2).round()) / 100.0).toStringAsFixed(2)),
              'csamt': 0.0,
            },
          },
        ],
      };

      if (buyerGstin.isNotEmpty) {
        // CDNR — B2B credit note
        cdnrMap.putIfAbsent(buyerGstin, () => []).add(noteEntry);
      } else {
        // CDNUR — B2C credit note
        cdnurList.add(noteEntry);
      }
    }

    final cdnrArray = cdnrMap.entries.map((e) => {
      'ctin': e.key,
      'nt': e.value,
    }).toList();

    // Count cancelled invoices (refunded)
    final cancCount = refundedSales.length;
    final netIssue = activeSales.length;

    final gstr1Payload = {
      'gstin': profile.gstin.trim(),
      'fp': fp.toFp(),
      'cur_gt': double.parse((totalTurnoverPaise / 100.0).toStringAsFixed(2)),
      'gt': double.parse((totalTaxablePaise / 100.0).toStringAsFixed(2)),
      'version': 'GSTR1_V2.0_OFFLINE',
      'hash': 'hash_${DateTime.now().millisecondsSinceEpoch}',
      'hsn': {
        'data': hsnData,
      },
      'b2cs': b2csMap.values.toList(),
      'b2b': b2bArray,
      'cdnr': cdnrArray,
      'cdnur': cdnurList,
      'doc_issue': {
        'doc_det': [
          {
            'doc_num': 1,
            'doc_typ': 'Invoices for outward supply',
            'from': sales.isNotEmpty ? sales.last.invoiceNumber : '1',
            'to': sales.isNotEmpty ? sales.first.invoiceNumber : '1',
            'totnum': sales.length,
            'canc': cancCount,
            'net_issue': netIssue,
          }
        ]
      }
    };

    final tempDir = await getTemporaryDirectory();
    final cleanPeriod = period.replaceAll(RegExp(r'[^\w\d]'), '_');
    final file = File('${tempDir.path}/kamaiplus_gstr1_$cleanPeriod.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(gstr1Payload), flush: true);
    return file;
  }

  /// Extracts the dominant tax rate from a sale's items (most common rate by value).
  double _dominantTaxRate(SaleModel sale) {
    final Map<double, int> rateValueMap = {};
    for (final item in sale.items) {
      final rate = (item['tax_rate'] as num?)?.toDouble() ?? 0.0;
      final value = (item['gross_total_paise'] as num?)?.toInt() ?? 0;
      rateValueMap[rate] = (rateValueMap[rate] ?? 0) + value;
    }
    if (rateValueMap.isEmpty) return 0.0;
    return rateValueMap.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  /// Formats date as DD-MM-YYYY for GSTR-1 JSON
  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year}';
  }

  /// 4. REAL SHARE WITH CA VIA SYSTEM CHOOSER & WHATSAPP
  Future<void> shareFileWithCa({
    required File file,
    required String period,
    required StoreProfileModel profile,
    required int taxablePaise,
    required int totalTaxPaise,
    String? caPhone,
  }) async {
    final store = profile.storeName.isNotEmpty ? profile.storeName : 'KamaiPlus Retail Store';
    final gstin = profile.gstin.isNotEmpty ? profile.gstin : 'Unregistered / Retail';

    final text = '📋 *GST Tax Return Package ($period)*\n'
        '🏪 *Store:* $store\n'
        '🆔 *GSTIN:* $gstin\n'
        '💰 *Taxable Turnover:* ${MoneyFormatter.formatINR(taxablePaise)}\n'
        '🧾 *Total GST (50% CGST + 50% SGST):* ${MoneyFormatter.formatINR(totalTaxPaise)}\n'
        '📁 Official audit compliance file attached.\n'
        '⚡ Generated via Kamai+ Android POS';

    // Share via SharePlus with attached real file
    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [XFile(file.path)],
      text: text,
      subject: 'GST Compliance Report - $store ($period)',
    );
  }

  /// Direct WhatsApp Text message with figures
  Future<void> launchDirectWhatsApp({
    required String period,
    required StoreProfileModel profile,
    required int taxablePaise,
    required int totalTaxPaise,
    String? caPhone,
  }) async {
    final store = profile.storeName.isNotEmpty ? profile.storeName : 'KamaiPlus Retail Store';
    final gstin = profile.gstin.isNotEmpty ? profile.gstin : 'Unregistered / Retail';

    final message = 'Hello Sir, sharing my store GST Figures for *$period*:\n\n'
        '🏪 *Store:* $store\n'
        '🆔 *GSTIN:* $gstin\n'
        '💰 *Taxable Sales:* ${MoneyFormatter.formatINR(taxablePaise)}\n'
        '🧾 *Total GST:* ${MoneyFormatter.formatINR(totalTaxPaise)}\n'
        '• CGST: ${MoneyFormatter.formatINR((totalTaxPaise / 2).round())}\n'
        '• SGST: ${MoneyFormatter.formatINR(totalTaxPaise - (totalTaxPaise / 2).round())}\n\n'
        'Kindly confirm filing. Shared via Kamai+ POS.';

    final phoneClean = (caPhone ?? '').replaceAll(RegExp(r'[^\d]'), '');
    final uri = phoneClean.isNotEmpty
        ? Uri.parse('https://wa.me/91$phoneClean?text=${Uri.encodeComponent(message)}')
        : Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _inferHsnFromCategory(String category, String productName) {
    final n = productName.toLowerCase();
    if (n.contains('oil') || n.contains('tel')) return '1512';
    if (n.contains('soap') || n.contains('surf') || n.contains('detergent')) return '3401';
    if (n.contains('rice') || n.contains('chawal')) return '1006';
    if (n.contains('atta') || n.contains('flour') || n.contains('maida')) return '1101';
    if (n.contains('milk') || n.contains('doodh') || n.contains('paneer') || n.contains('curd')) return '0402';
    if (n.contains('biscuit') || n.contains('snack') || n.contains('namkeen')) return '2106';
    if (n.contains('maggi') || n.contains('noodle') || n.contains('pasta')) return '1902';
    if (n.contains('paste') || n.contains('brush') || n.contains('colgate')) return '3306';
    if (category == 'pharmacy') return '3004';
    if (category == 'restaurant') return '9963';
    if (category == 'apparel') return '6203';
    if (category == 'electronics') return '8517';
    return '1902';
  }

  String _escapeCsv(String val) => val.replaceAll('"', '""');
  String _escapeXml(String val) => val
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
