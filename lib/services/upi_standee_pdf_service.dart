import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Generates and dispatches the "Official Counter UPI Standee" — a one-page
/// printable card with the store's UPI QR code, used for the Share/Print/PDF
/// buttons on `upi_standee_modal.dart`. Those three buttons used to just show
/// a fake "done!" SnackBar with nothing actually generated; this builds a
/// real document from the same QR bitmap the on-screen preview renders, using
/// the `pdf`/`printing` packages (pure Dart, no native code — unlike the
/// invoice PDF flow, which is a native-Android MethodChannel this feature
/// doesn't need to touch).
class UpiStandeePdfService {
  static Future<Uint8List> generatePdfBytes({
    required String storeName,
    required String upiId,
    required Uint8List qrPngBytes,
  }) async {
    final doc = pw.Document();
    final qrImage = pw.MemoryImage(qrPngBytes);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(28),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                storeName,
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'SCAN & PAY WITH ANY UPI APP',
                style: pw.TextStyle(fontSize: 11, letterSpacing: 1.2, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 20),
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black, width: 2),
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Image(qrImage, width: 220, height: 220),
              ),
              pw.SizedBox(height: 14),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(20),
                ),
                child: pw.Text(upiId, style: const pw.TextStyle(fontSize: 13)),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                'BHIM UPI  •  Google Pay  •  PhonePe  •  Paytm',
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
              ),
              pw.SizedBox(height: 24),
              pw.Text(
                'Generated via KamaiPlus POS',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  /// Opens the native Android/iOS print dialog for the given PDF bytes.
  static Future<void> printStandee(Uint8List pdfBytes, {required String storeName}) async {
    await Printing.layoutPdf(
      onLayout: (_) async => pdfBytes,
      name: 'UPI_Standee_$storeName',
    );
  }

  /// Opens the OS share sheet with the PDF attached — the receiving end can
  /// save it, print it, or forward it, same as any other shared file.
  static Future<void> shareStandee(Uint8List pdfBytes, {required String storeName}) async {
    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'UPI_Standee_$storeName.pdf',
    );
  }
}
