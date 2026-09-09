import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../main.dart';

enum NotificationType { success, error, info, warning }

class InAppNotification {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;
  static final ValueNotifier<bool> _isShowing = ValueNotifier(false);

  /// Shows an in-app floating notification that renders ABOVE all dialogs and modals.
  /// Includes an explicit 'X' button and automatically hides after 3.5 seconds.
  static void show({
    BuildContext? context,
    required String message,
    NotificationType type = NotificationType.success,
    IconData? customIcon,
    Color? customColor,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 3500),
  }) {
    // 1. Dismiss any existing notification first
    hide();

    // 2. Resolve overlay context (Root navigator overlay renders on top of ALL dialogs & modals)
    OverlayState? overlayState;
    if (rootNavigatorKey.currentState?.overlay != null) {
      overlayState = rootNavigatorKey.currentState!.overlay;
    } else if (context != null) {
      overlayState = Overlay.of(context, rootOverlay: true);
    }

    if (overlayState == null) return;

    Color iconColor;
    IconData iconData;
    switch (type) {
      case NotificationType.success:
        iconColor = const Color(0xFF10B981);
        iconData = customIcon ?? Icons.check_circle_rounded;
        break;
      case NotificationType.error:
        iconColor = const Color(0xFFF43F5E);
        iconData = customIcon ?? Icons.error_outline_rounded;
        break;
      case NotificationType.warning:
        iconColor = const Color(0xFFF59E0B);
        iconData = customIcon ?? Icons.warning_amber_rounded;
        break;
      case NotificationType.info:
        iconColor = const Color(0xFF38BDF8);
        iconData = customIcon ?? Icons.info_outline_rounded;
        break;
    }

    if (customColor != null) {
      iconColor = customColor;
    }

    _currentEntry = OverlayEntry(
      builder: (ctx) => _NotificationWidget(
        message: message,
        iconData: iconData,
        iconColor: iconColor,
        actionLabel: actionLabel,
        onAction: onAction,
        onClose: hide,
      ),
    );

    overlayState.insert(_currentEntry!);
    _isShowing.value = true;

    // 3. Auto-hide after 3-4 seconds (3500ms)
    _dismissTimer = Timer(duration, () {
      hide();
    });
  }

  /// Immediately hides and disposes the current notification
  static void hide() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    if (_currentEntry != null) {
      try {
        _currentEntry?.remove();
      } catch (_) {}
      _currentEntry = null;
      _isShowing.value = false;
    }
  }

  // Convenience helpers
  static void success(String message, {BuildContext? context, String? actionLabel, VoidCallback? onAction}) {
    show(
      context: context,
      message: message,
      type: NotificationType.success,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void error(String message, {BuildContext? context}) {
    show(
      context: context,
      message: message,
      type: NotificationType.error,
    );
  }

  static void info(String message, {BuildContext? context, String? actionLabel, VoidCallback? onAction}) {
    show(
      context: context,
      message: message,
      type: NotificationType.info,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

class _NotificationWidget extends StatefulWidget {
  final String message;
  final IconData iconData;
  final Color iconColor;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onClose;

  const _NotificationWidget({
    required this.message,
    required this.iconData,
    required this.iconColor,
    this.actionLabel,
    this.onAction,
    required this.onClose,
  });

  @override
  State<_NotificationWidget> createState() => _NotificationWidgetState();
}

class _NotificationWidgetState extends State<_NotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));

    _animCtrl.forward();
  }

  void _dismissWithAnimation() {
    _animCtrl.reverse().then((_) {
      if (mounted) widget.onClose();
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomInset = mq.viewInsets.bottom;
    // Position above bottom navbar (approx 84-90px) or above keyboard
    final effectiveBottom = bottomInset > 0 ? (bottomInset + 16.0) : 84.0;

    return Positioned(
      bottom: effectiveBottom,
      left: 14,
      right: 14,
      child: Material(
        color: Colors.transparent,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Dismissible(
              key: const ValueKey('in_app_notification_dismissible'),
              direction: DismissDirection.horizontal,
              onDismissed: (_) => widget.onClose(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155), width: 1.1),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Notification Type Icon
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: widget.iconColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(widget.iconData, color: widget.iconColor, size: 20),
                    ),
                    const SizedBox(width: 10),

                    // Message Text
                    Expanded(
                      child: Text(
                        widget.message,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Optional Action Button (e.g. OPEN)
                    if (widget.actionLabel != null && widget.onAction != null) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          widget.onAction?.call();
                          _dismissWithAnimation();
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF475569)),
                          ),
                          child: Text(
                            widget.actionLabel!,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFFBBF24),
                            ),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(width: 8),

                    // Explicit 'X' Close Button (requested by user)
                    InkWell(
                      onTap: _dismissWithAnimation,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF94A3B8),
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
