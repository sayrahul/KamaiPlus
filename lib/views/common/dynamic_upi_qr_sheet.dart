import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import 'in_app_notification.dart';

/// The one full-screen "show the customer a UPI QR" sheet, shared by every
/// place in the app that collects a UPI payment.
///
/// It exists as a shared component rather than a method on one screen because
/// it was previously a private method of `_PosCheckoutModalState`, so the
/// Khata "Settle Credit Bills" flow could not reach it and shipped its own
/// small, inert QR thumbnail instead — no enlarge, no countdown, no copyable
/// UPI id. A cashier taking an udhar payment got a visibly different (and
/// worse) experience than one taking a counter payment for the same amount.
///
/// What it owns:
///  * a REAL countdown. The original was the literal string `'Valid: 05:00'`
///    with no timer behind it — it read as a working clock while never moving.
///  * regeneration on expiry, issuing a fresh `tr=` transaction reference so
///    each QR shown is distinguishable in the merchant's UPI statement.
///  * an optional multi-account switcher, a copyable UPI id, and an optional
///    "send to customer on WhatsApp" action.
///
/// The expiry is a counter convention, NOT a bank-enforced one — a UPI intent
/// URI has no validity window. It is the point at which a stale QR should be
/// reissued rather than left on screen indefinitely.
class DynamicUpiQrSheet {
  DynamicUpiQrSheet._();

  /// How long a generated QR is offered before the sheet asks for a new one.
  static const Duration validity = Duration(minutes: 5);

  /// Builds the raw `upi://pay?...` URI a scanner app consumes.
  ///
  /// Deliberately the raw scheme, never an https wrapper — wrapping it would
  /// break scanning (see `upi_link_utils.dart`, which exists for the opposite
  /// case: pasting a tappable link into a WhatsApp message).
  static String buildQrPayload({
    required String upiVpa,
    required String storeName,
    required int amountPaise,
    required String note,
    required String txnRef,
  }) {
    return 'upi://pay?pa=$upiVpa'
        '&pn=${Uri.encodeComponent(storeName)}'
        '&am=${(amountPaise / 100.0).toStringAsFixed(2)}'
        '&cu=INR'
        '&tn=${Uri.encodeComponent(note)}'
        '&tr=$txnRef';
  }

  /// Shows the sheet.
  ///
  /// [accounts] / [selectedAccountId] / [onAccountChanged] are optional — pass
  /// them only where the merchant has more than one UPI account configured and
  /// the caller can persist the switch.
  ///
  /// [customerName] + [customerPhone] enable the WhatsApp hand-off row.
  static Future<void> show(
    BuildContext context, {
    required String upiVpa,
    required String storeName,
    required int amountPaise,
    String title = 'Dynamic UPI QR',
    String note = 'POS Bill',
    List<UpiAccountModel> accounts = const [],
    String? selectedAccountId,
    void Function(UpiAccountModel account)? onAccountChanged,
    String? customerName,
    String? customerPhone,
    String? whatsAppMessage,
  }) {
    // Countdown state lives outside the builder so a rebuild — switching UPI
    // account, say — does not restart the clock.
    Timer? ticker;
    var remaining = validity;
    var txnRef = DateTime.now().millisecondsSinceEpoch.toString();
    var activeVpa = upiVpa;

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            // One ticker per sheet; guarded so a rebuild cannot stack a second.
            ticker ??= Timer.periodic(const Duration(seconds: 1), (t) {
              if (remaining.inSeconds <= 0) {
                t.cancel();
                return;
              }
              remaining -= const Duration(seconds: 1);
              setSheetState(() {});
            });

            final expired = remaining.inSeconds <= 0;
            final mmss = '${remaining.inMinutes.toString().padLeft(2, '0')}:'
                '${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';

            void regenerate() {
              HapticFeedback.mediumImpact();
              ticker?.cancel();
              ticker = null;
              txnRef = DateTime.now().millisecondsSinceEpoch.toString();
              remaining = validity;
              setSheetState(() {});
            }

            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF334155),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(Icons.qr_code_scanner_rounded,
                                  color: Color(0xFF34D399), size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  title,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (accounts.length > 1) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: accounts.map((acc) {
                            final isSel = acc.id == (selectedAccountId ?? '');
                            return Padding(
                              padding: const EdgeInsets.only(right: 6, bottom: 10),
                              child: InkWell(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  selectedAccountId = acc.id;
                                  activeVpa = acc.upiVpa;
                                  onAccountChanged?.call(acc);
                                  setSheetState(() {});
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isSel ? const Color(0xFF10B981) : const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSel ? const Color(0xFF34D399) : const Color(0xFF334155),
                                      width: isSel ? 1.4 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.account_balance_wallet_rounded,
                                          size: 12,
                                          color: isSel ? Colors.white : const Color(0xFF94A3B8)),
                                      const SizedBox(width: 5),
                                      Text(
                                        acc.label,
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                                          color: isSel ? Colors.white : const Color(0xFFCBD5E1),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 4)),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Covered, not removed, on expiry — the cashier needs
                          // to see WHY nothing is scanning.
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Opacity(
                                opacity: expired ? 0.12 : 1,
                                child: QrImageView(
                                  data: buildQrPayload(
                                    upiVpa: activeVpa,
                                    storeName: storeName,
                                    amountPaise: amountPaise,
                                    note: note,
                                    txnRef: txnRef,
                                  ),
                                  version: QrVersions.auto,
                                  size: 230,
                                ),
                              ),
                              if (expired)
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.timer_off_rounded,
                                        size: 34, color: Color(0xFFDC2626)),
                                    const SizedBox(height: 8),
                                    Text('QR Expired',
                                        style: GoogleFonts.outfit(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          color: const Color(0xFF991B1B),
                                        )),
                                    const SizedBox(height: 10),
                                    ElevatedButton.icon(
                                      onPressed: regenerate,
                                      icon: const Icon(Icons.refresh_rounded, size: 16),
                                      label: Text('Generate New QR',
                                          style: GoogleFonts.outfit(
                                              fontWeight: FontWeight.w800, fontSize: 12.5)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF059669),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Scan to Pay Exact ₹${(amountPaise / 100.0).toStringAsFixed(2)}',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: activeVpa));
                        HapticFeedback.selectionClick();
                        InAppNotification.success('UPI ID copied: $activeVpa', context: ctx);
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.copy_rounded, size: 13, color: Color(0xFF34D399)),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'UPI: $activeVpa',
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('• Tap to copy',
                                style: GoogleFonts.inter(
                                    fontSize: 10, color: const Color(0xFF94A3B8))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'PhonePe • GPay • Paytm • BHIM',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: expired ? regenerate : null,
                          borderRadius: BorderRadius.circular(6),
                          child: Row(
                            children: [
                              Icon(
                                expired ? Icons.refresh_rounded : Icons.timer_outlined,
                                size: 13,
                                color: expired ? const Color(0xFFF87171) : const Color(0xFFFBBF24),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                expired ? 'Expired · Tap to refresh' : 'Valid: $mmss',
                                style: GoogleFonts.robotoMono(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: expired ? const Color(0xFFF87171) : const Color(0xFFFBBF24),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    if (customerPhone != null && customerPhone.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          final digits = customerPhone.replaceAll(RegExp(r'\D'), '');
                          final target = digits.length == 10 ? '91$digits' : digits;
                          final text = Uri.encodeComponent(
                            whatsAppMessage ??
                                'Dear ${customerName ?? 'Customer'},\n\n'
                                    'Your $storeName amount due: '
                                    '₹${(amountPaise / 100.0).toStringAsFixed(2)}\n'
                                    '📌 UPI ID: $activeVpa\n\n'
                                    'Thank you!',
                          );
                          final url = Uri.parse('https://wa.me/$target?text=$text');
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url, mode: LaunchMode.externalApplication);
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF25D366), width: 1.2),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.send_rounded, size: 14, color: Color(0xFF25D366)),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Send Payment Request to ${customerName ?? 'Customer'}',
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF25D366),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
      // Stop the ticker whichever way the sheet closes — swipe, back, or X.
    ).whenComplete(() => ticker?.cancel());
  }
}
