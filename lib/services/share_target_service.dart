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
        // Cloud AI first, on-device OCR only if it cannot answer.
        //
        // This branch used to go straight to ML Kit, so a bill photo shared in
        // from WhatsApp — one of the three ways into AI inward — never touched
        // the AI at all. The merchant got the line-reader's guesses from a
        // feature the app calls "AI", with no indication the AI had been
        // skipped. Same order as AiInwardSheet and MenuScanSheet now use.
        final bytes = await file.readAsBytes();
        final ai = await GeminiAiService.extractItemsFromImage(
          bytes,
          mimeType: _mimeTypeFor(filePath),
        );

        var items = ai.items;
        var supplierName = ai.supplierName;
        var billNumber = ai.billNumber;
        var billDate = ai.billDate;
        var usedOffline = false;

        if (items.isEmpty) {
          try {
            final offline = await MlKitOcrService.instance.scanBillImage(filePath);
            if (offline.items.isNotEmpty) {
              items = offline.items;
              supplierName = offline.supplierName;
              billNumber = offline.billNumber;
              billDate = offline.billDate;
              usedOffline = true;
            }
          } catch (_) {}
        }

        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop(); // dismiss loading
        }

        if (context.mounted) {
          if (items.isNotEmpty) {
            if (usedOffline) {
              InAppNotification.show(
                context: context,
                message: 'AI unreachable — read ${items.length} items on your phone instead. Please check each line.',
                type: NotificationType.warning,
                duration: const Duration(seconds: 5),
              );
            }
            BillScanReviewSheet.show(
              context,
              items: items,
              supplierName: supplierName,
              billNumber: billNumber,
              billDate: billDate,
            );
          } else {
            InAppNotification.show(
              context: context,
              message: ai.errorMessage ??
                  'Bill image received, but no product lines could be recognized.',
              type: NotificationType.warning,
              duration: const Duration(seconds: 5),
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

  /// A shared file arrives as a path, not a picked image, so the MIME type has
  /// to come from the extension. Sending a PNG labelled image/jpeg is rejected
  /// by the vision API outright.
  static String _mimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }
}
