import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/utils/money_formatter.dart';
import '../common/in_app_notification.dart';

class DenominationTallyModal extends StatefulWidget {
  final int expectedCashPaise;
  final Map<int, int>? initialDenominations;
  final void Function(Map<int, int> denominations, int totalPaise)? onSaved;

  const DenominationTallyModal({
    super.key,
    this.expectedCashPaise = 0,
    this.initialDenominations,
    this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    int expectedCashPaise = 0,
    Map<int, int>? initialDenominations,
    void Function(Map<int, int> denominations, int totalPaise)? onSaved,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DenominationTallyModal(
        expectedCashPaise: expectedCashPaise,
        initialDenominations: initialDenominations,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<DenominationTallyModal> createState() => _DenominationTallyModalState();
}

class _DenominationTallyModalState extends State<DenominationTallyModal> {
  static const Map<int, String> _denomAssets = {
    500: 'assets/images/500.png',
    200: 'assets/images/200.png',
    100: 'assets/images/100.png',
    50: 'assets/images/50.png',
    20: 'assets/images/20.png',
    10: 'assets/images/10.png',
    5: 'assets/images/5.png',
    2: 'assets/images/2.png',
    1: 'assets/images/1.png',
  };

  late final Map<int, int> _denominations;

  @override
  void initState() {
    super.initState();
    _denominations = widget.initialDenominations != null
        ? Map.from(widget.initialDenominations!)
        : {
            500: 0,
            200: 0,
            100: 0,
            50: 0,
            20: 0,
            10: 0,
            5: 0,
            2: 0,
            1: 0,
          };
    _denominations.remove(2000);
  }

  int get _countedTotalPaise {
    int total = 0;
    _denominations.forEach((denom, count) {
      total += denom * count * 100;
    });
    return total;
  }

  void _shareViaWhatsApp() async {
    HapticFeedback.selectionClick();
    final countedPaise = _countedTotalPaise;
    final diffPaise = countedPaise - widget.expectedCashPaise;
    final now = DateTime.now();
    final dateStr = DateFormat('d MMM yyyy, hh:mm a').format(now);

    final buffer = StringBuffer();
    buffer.writeln('🧾 *CASH TALLY BREAKDOWN REPORT*');
    buffer.writeln('🏪 *KamaiPlus Cash Desk*');
    buffer.writeln('📅 Date: $dateStr');
    buffer.writeln('------------------------------');

    bool hasAny = false;
    _denominations.forEach((denom, count) {
      if (count > 0) {
        hasAny = true;
        final total = denom * count;
        final type = denom <= 5 ? 'Coin' : 'Note';
        buffer.writeln('• ₹$denom $type x $count = ₹$total');
      }
    });

    if (!hasAny) {
      buffer.writeln('• No notes/coins recorded.');
    }

    buffer.writeln('------------------------------');
    buffer.writeln('💰 *Total Physical Counted: ${MoneyFormatter.formatINR(countedPaise)}*');
    if (widget.expectedCashPaise > 0) {
      buffer.writeln('🎯 *Expected in Register: ${MoneyFormatter.formatINR(widget.expectedCashPaise)}*');
      final varianceText = diffPaise == 0
          ? '✓ Matched Exactly'
          : (diffPaise > 0
              ? '+${MoneyFormatter.formatINR(diffPaise)} (Excess)'
              : '-${MoneyFormatter.formatINR(diffPaise.abs())} (Shortage)');
      buffer.writeln('📊 *Variance: $varianceText*');
    }
    buffer.writeln('\n_Report generated via KamaiPlus POS_');

    final textEncoded = Uri.encodeComponent(buffer.toString());
    final url = Uri.parse('https://wa.me/?text=$textEncoded');
    final directWa = Uri.parse('whatsapp://send?text=$textEncoded');
    try {
      final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(directWa, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(directWa, mode: LaunchMode.externalApplication);
      } catch (_) {
        await Clipboard.setData(ClipboardData(text: buffer.toString()));
        if (mounted) {
          InAppNotification.success('Cash tally breakdown copied to clipboard!', context: context);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final countedPaise = _countedTotalPaise;
    final diffPaise = countedPaise - widget.expectedCashPaise;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.calculate_rounded, color: Color(0xFF059669), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Note & Coin Tally Counter',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Comparison Banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PHYSICAL COUNTED',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        MoneyFormatter.formatINR(countedPaise),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 36, color: const Color(0xFFE2E8F0)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'EXPECTED IN DRAWER',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        MoneyFormatter.formatINR(widget.expectedCashPaise),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        diffPaise == 0
                            ? '✓ Matched Exactly'
                            : (diffPaise > 0
                                ? '+${MoneyFormatter.formatINR(diffPaise)} Excess'
                                : '-${MoneyFormatter.formatINR(diffPaise.abs())} Short'),
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: diffPaise == 0
                              ? const Color(0xFF059669)
                              : (diffPaise > 0 ? const Color(0xFF0284C7) : const Color(0xFFDC2626)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Note Tally List
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: _denominations.keys.map((denom) {
                final count = _denominations[denom]!;
                final totalVal = denom * count;
                final label = denom <= 5 ? '₹$denom Coin' : '₹$denom Note';
                final assetPath = _denomAssets[denom];

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEEF2F6)),
                  ),
                  child: Row(
                    children: [
                      // 1. Note / Coin Image
                      Container(
                        width: 48,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: assetPath != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.asset(
                                  assetPath,
                                  fit: BoxFit.contain,
                                  width: denom <= 5 ? 24 : 44,
                                  height: 24,
                                  errorBuilder: (c, e, s) => Icon(
                                    denom <= 5 ? Icons.monetization_on_outlined : Icons.money_rounded,
                                    size: 18,
                                    color: const Color(0xFF059669),
                                  ),
                                ),
                              )
                            : Icon(
                                denom <= 5 ? Icons.monetization_on_outlined : Icons.money_rounded,
                                size: 18,
                                color: const Color(0xFF059669),
                              ),
                      ),
                      const SizedBox(width: 8),

                      // 2. Note Name
                      SizedBox(
                        width: 70,
                        child: Text(
                          label,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),

                      // 3. Minus Button
                      IconButton(
                        onPressed: count > 0
                            ? () {
                                HapticFeedback.selectionClick();
                                setState(() => _denominations[denom] = count - 1);
                              }
                            : null,
                        icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                        color: const Color(0xFF64748B),
                        visualDensity: VisualDensity.compact,
                      ),

                      // Count
                      Container(
                        width: 30,
                        alignment: Alignment.center,
                        child: Text(
                          '$count',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),

                      // 4. Plus Button
                      IconButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() => _denominations[denom] = count + 1);
                        },
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                        color: const Color(0xFF059669),
                        visualDensity: VisualDensity.compact,
                      ),
                      const Spacer(),

                      // 5. Total
                      Text(
                        '₹$totalVal',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),

          // Action row: Reset, WhatsApp Share, and Confirm
          Row(
            children: [
              TextButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _denominations.updateAll((key, value) => 0);
                  });
                },
                child: Text(
                  'Reset',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                onPressed: _shareViaWhatsApp,
                icon: Image.asset('assets/images/whatsapp_logo.png', width: 16, height: 16),
                label: Text(
                  'Share',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    widget.onSaved?.call(_denominations, countedPaise);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    'Confirm Count (${MoneyFormatter.formatINR(countedPaise)})',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
