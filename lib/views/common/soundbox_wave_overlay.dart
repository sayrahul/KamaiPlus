import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/utils/money_formatter.dart';
import '../../services/soundbox_service.dart';

/// Visual Animated Soundbox Wave Ripple Overlay
/// Appears when a payment announcement fires, displaying radiating soundwave ripples
/// and the received payment amount in real time.
class SoundboxWaveOverlay extends StatefulWidget {
  const SoundboxWaveOverlay({super.key});

  @override
  State<SoundboxWaveOverlay> createState() => _SoundboxWaveOverlayState();
}

class _SoundboxWaveOverlayState extends State<SoundboxWaveOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    SoundboxService.instance.activeAnnouncementNotifier.addListener(_onAnnouncementChanged);
  }

  void _onAnnouncementChanged() {
    final event = SoundboxService.instance.activeAnnouncementNotifier.value;
    if (event != null) {
      HapticFeedback.selectionClick();
      _dismissTimer?.cancel();
      _dismissTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          SoundboxService.instance.dismissAnnouncement();
        }
      });
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    SoundboxService.instance.activeAnnouncementNotifier.removeListener(_onAnnouncementChanged);
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SoundboxEvent?>(
      valueListenable: SoundboxService.instance.activeAnnouncementNotifier,
      builder: (context, event, _) {
        if (event == null) return const SizedBox.shrink();

        final rupees = MoneyFormatter.formatINR(event.paise);

        return Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 14,
          right: 14,
          child: Dismissible(
            key: UniqueKey(),
            direction: DismissDirection.up,
            onDismissed: (_) => SoundboxService.instance.dismissAnnouncement(),
            child: GestureDetector(
              onTap: () => SoundboxService.instance.dismissAnnouncement(),
              child: AnimatedBuilder(
                animation: _animCtrl,
                builder: (context, child) {
                  return Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF064E3B), Color(0xFF047857), Color(0xFF059669)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Color.lerp(
                          const Color(0xFF34D399),
                          const Color(0xFFA7F3D0),
                          _animCtrl.value,
                        )!,
                        width: 1.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF059669).withValues(alpha: 0.35 * _animCtrl.value + 0.15),
                          blurRadius: 18 + (6 * _animCtrl.value),
                          spreadRadius: 2 * _animCtrl.value,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        // Animated Ripple Soundwave Speaker Icon
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer ripple ring
                            Container(
                              width: 44 + (10 * _animCtrl.value),
                              height: 44 + (10 * _animCtrl.value),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.2 * (1.0 - _animCtrl.value)),
                              ),
                            ),
                            // Inner speaker box
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF10B981),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
                              ),
                              child: const Icon(Icons.volume_up_rounded, color: Colors.white, size: 22),
                            ),
                          ],
                        ),
                        const SizedBox(width: 14),

                        // Announcement text & amount
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'SOUNDBOX VOICE',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFFA7F3D0),
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      event.paymentMethod.toUpperCase(),
                                      style: GoogleFonts.inter(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '✓ $rupees Received!',
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ).copyWith(fontFeatures: MoneyFormatter.tabularFeatures),
                              ),
                            ],
                          ),
                        ),

                        // Dismiss Cross
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
