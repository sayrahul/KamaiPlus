import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'gemini_ai_service.dart';
import 'mlkit_ocr_service.dart';
import '../views/purchases/bill_scan_review_sheet.dart';
import '../views/common/in_app_notification.dart';

/// Share-To Target Service ("Send to KamaiPlus" from WhatsApp / Gallery)
class ShareTargetService {
  ShareTargetService._();
  static final ShareTargetService instance = ShareTargetService._();

  static const MethodChannel _channel = MethodChannel('com.kamaiplus.pos/share_target');

  GlobalKey<NavigatorState>? _navigatorKey;

  void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _channel.setMethodCallHandler(_handleMethodCall);
    checkInitialSharedFile();
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onFileShared') {
      final filePath = call.arguments?.toString();
      if (filePath != null && filePath.isNotEmpty) {
        processSharedFile(filePath);
      }
    }
  }

  Future<void> checkInitialSharedFile() async {
    try {
      final filePath = await _channel.invokeMethod<String>('getInitialSharedFile');
      if (filePath != null && filePath.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          processSharedFile(filePath);
        });
      }
    } catch (_) {}
  }

  Future<void> processSharedFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    final context = _navigatorKey?.currentContext;
    if (context == null || !context.mounted) return;

    // Show quick progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          elevation: 8,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(strokeWidth: 3),
                SizedBox(width: 18),
                Text(
                  'Reading Shared Bill...',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final isPdf = filePath.toLowerCase().endsWith('.pdf');
      if (isPdf) {
        final bytes = await file.readAsBytes();
        final result = await GeminiAiService.extractItemsFromImage(bytes, mimeType: 'application/pdf');

        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop(); // dismiss loading
        }

        if (context.mounted) {
          if (result.items.isNotEmpty) {
            BillScanReviewSheet.show(
              context,
              items: result.items,
              supplierName: result.supplierName,
              billNumber: result.billNumber,
              billDate: result.billDate,
            );
          } else {
            InAppNotification.show(
              context: context,
              message: result.errorMessage ?? 'Could not parse products from shared PDF.',
              type: NotificationType.warning,
            );
          }
        }
      } else {
        final result = await MlKitOcrService.instance.scanBillImage(filePath);
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop(); // dismiss loading
        }

        if (context.mounted) {
          if (result.items.isNotEmpty) {
            BillScanReviewSheet.show(
              context,
              items: result.items,
              supplierName: result.supplierName,
              billNumber: result.billNumber,
              billDate: result.billDate,
            );
          } else {
            InAppNotification.show(
              context: context,
              message: 'Bill image received, but no product lines could be recognized.',
              type: NotificationType.warning,
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // dismiss loading
        InAppNotification.error('Failed to parse bill: $e', context: context);
      }
    }
  }
}
