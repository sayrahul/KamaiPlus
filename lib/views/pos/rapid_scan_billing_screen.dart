import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/utils/money_formatter.dart';
import '../../core/utils/quantity_config.dart';
import '../../core/utils/scan_rules.dart';
import '../../models/models.dart';
import '../../services/scan_feedback_service.dart';
import '../common/in_app_notification.dart';

enum ScanAddStatus { added, notFound, blocked, cancelled }

/// What happened to one scanned barcode.
class ScanAddResult {
  final ScanAddStatus status;
  final String message;
  final ProductModel? product;

  /// Quantity of [product] in the bill after this scan, and how much the scan
  /// added — so the scanner can offer an exact undo.
  final double quantityNow;
  final double addedQuantity;

  const ScanAddResult({
    required this.status,
    this.message = '',
    this.product,
    this.quantityNow = 0,
    this.addedQuantity = 0,
  });
}

/// How the billing screen's cart is driven from the scanner. The cart itself
/// stays in `PosBillingScreen`, so every scan goes through the same rules as
/// a tap on the product grid: stock limit, variant picker, expired-item
/// warning, and the price prompt for an item resolved online without a price.
class RapidScanBridge {
  final String Function() billTitle;
  final List<CartItemModel> Function() cartItems;
  final int Function() totalPaise;
  final Future<ScanAddResult> Function(String barcode) addBarcode;

  /// Sets an item's quantity (0 removes it). Returns an error message when
  /// the stock rule refuses, otherwise null.
  final String? Function(String productId, double quantity) setQuantity;

  /// Puts a removed line back exactly as it was (price, discount, notes).
  final void Function(CartItemModel item) restoreItem;

  /// Fires on every cart change — including a USB/Bluetooth scanner gun
  /// scanning while this screen is open.
  final Listenable cartChanges;

  const RapidScanBridge({
    required this.billTitle,
    required this.cartItems,
    required this.totalPaise,
    required this.addBarcode,
    required this.setQuantity,
    required this.restoreItem,
    required this.cartChanges,
  });
}

enum RapidScanExit { done, checkout }

/// Continuous camera scanning for billing: point, beep, next — every pack
/// goes straight into the current bill without reopening the camera.
class RapidScanBillingScreen extends StatefulWidget {
  final RapidScanBridge bridge;

  const RapidScanBillingScreen({super.key, required this.bridge});

  static Future<RapidScanExit?> show(BuildContext context, {required RapidScanBridge bridge}) {
    return Navigator.push<RapidScanExit>(
      context,
      MaterialPageRoute(builder: (_) => RapidScanBillingScreen(bridge: bridge)),
    );
  }

  @override
  State<RapidScanBillingScreen> createState() => _RapidScanBillingScreenState();
}

enum _BannerKind { success, error, info }

class _Banner {
  final String text;
  final _BannerKind kind;
  const _Banner(this.text, this.kind);
}

class _LastScan {
  final String productId;
  final String name;
  final double quantityBefore;
  const _LastScan(this.productId, this.name, this.quantityBefore);
}

class _RapidScanBillingScreenState extends State<RapidScanBillingScreen> with TickerProviderStateMixin {
  static const _kGreen = Color(0xFF10B981);
  static const _kRed = Color(0xFFEF4444);
  static const _kAmber = Color(0xFFF59E0B);
  static const _kSlate900 = Color(0xFF0F172A);
  static const _kSlate500 = Color(0xFF64748B);
  static const _kSlate200 = Color(0xFFE2E8F0);

  late final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 250,
    facing: CameraFacing.back,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.itf14,
      BarcodeFormat.codabar,
      BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
    ],
  );

  final ScanDebouncer _debouncer = ScanDebouncer();
  late final AnimationController _laser =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
  // Starts at its end (fully faded) so the screen does not flash on open.
  late final AnimationController _flash =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420), value: 1.0);

  bool _busy = false;
  bool _paused = false;
  bool _torchOn = false;
  bool _closeUp = false;
  Color _flashColor = _kGreen;
  _Banner? _banner;
  Timer? _bannerTimer;
  _LastScan? _last;
  int _scanCount = 0;

  @override
  void initState() {
    super.initState();
    ScanFeedbackService.instance.load();
    widget.bridge.cartChanges.addListener(_onCartChanged);
  }

  @override
  void dispose() {
    widget.bridge.cartChanges.removeListener(_onCartChanged);
    _bannerTimer?.cancel();
    _laser.dispose();
    _flash.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------

  void _onDetect(BarcodeCapture capture) {
    final now = DateTime.now();
    for (final barcode in capture.barcodes) {
      final code = normalizeScannedCode(barcode.rawValue);
      if (code == null) continue;
      if (_debouncer.isRecent(code, now)) {
        // Same pack still in view — keep it "seen" so it is not added twice.
        _debouncer.seen(code, now);
        continue;
      }
      // Not marked as seen while busy: a new pack shown during a lookup is
      // picked up on the next frame instead of being silently skipped.
      if (_busy || _paused) continue;
      _debouncer.seen(code, now);
      _process(code);
      return;
    }
  }

  Future<void> _process(String code) async {
    setState(() => _busy = true);
    try {
      final r = await widget.bridge.addBarcode(code);
      if (!mounted) return;
      switch (r.status) {
        case ScanAddStatus.added:
          _scanCount++;
          ScanFeedbackService.instance.success();
          _pulse(_kGreen);
          final p = r.product!;
          _last = _LastScan(p.id, p.name, r.quantityNow - r.addedQuantity);
          _showBanner(
            r.message.isNotEmpty ? r.message : '${p.name}  •  Qty ${formatCartQty(r.quantityNow)}',
            _BannerKind.success,
          );
          break;
        case ScanAddStatus.blocked:
          ScanFeedbackService.instance.error();
          _pulse(_kRed);
          _showBanner(r.message, _BannerKind.error);
          break;
        case ScanAddStatus.notFound:
          ScanFeedbackService.instance.error();
          _pulse(_kRed);
          _showBanner(r.message.isNotEmpty ? r.message : 'Barcode $code not found', _BannerKind.error);
          break;
        case ScanAddStatus.cancelled:
          _showBanner('Skipped', _BannerKind.info);
          break;
      }
    } catch (e) {
      if (mounted) {
        ScanFeedbackService.instance.error();
        _showBanner('Could not add $code: $e', _BannerKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _pulse(Color color) {
    _flashColor = color;
    _flash.forward(from: 0);
  }

  void _showBanner(String text, _BannerKind kind) {
    _bannerTimer?.cancel();
    setState(() => _banner = _Banner(text, kind));
    _bannerTimer = Timer(Duration(milliseconds: kind == _BannerKind.error ? 3200 : 2200), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  Future<void> _togglePause() async {
    HapticFeedback.selectionClick();
    setState(() => _paused = !_paused);
    try {
      if (_paused) {
        await _controller.pause();
      } else {
        await _controller.start();
      }
    } catch (_) {}
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      setState(() => _torchOn = !_torchOn);
      HapticFeedback.selectionClick();
    } catch (_) {}
  }

  Future<void> _toggleCloseUp() async {
    try {
      // setZoomScale is linear 0.0 (widest) .. 1.0 (maximum zoom).
      await _controller.setZoomScale(_closeUp ? 0.0 : 0.35);
      setState(() => _closeUp = !_closeUp);
      HapticFeedback.selectionClick();
    } catch (_) {}
  }

  Future<void> _manualEntry() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Type Barcode', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          style: GoogleFonts.jetBrainsMono(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1),
          decoration: InputDecoration(
            hintText: 'e.g. 8901063010123',
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(backgroundColor: _kSlate900, foregroundColor: Colors.white),
            child: const Text('Add to Bill'),
          ),
        ],
      ),
    );
    final clean = normalizeScannedCode(code);
    if (clean != null && mounted && !_busy) await _process(clean);
  }

  // ---------------------------------------------------------------------------
  // Quantity
  // ---------------------------------------------------------------------------

  CartItemModel? _itemFor(String productId) {
    for (final i in widget.bridge.cartItems()) {
      if (i.product.id == productId) return i;
    }
    return null;
  }

  void _setQty(CartItemModel item, double qty) {
    final error = widget.bridge.setQuantity(item.product.id, qty);
    if (error != null) {
      ScanFeedbackService.instance.error();
      _showBanner(error, _BannerKind.error);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {});
  }

  void _step(CartItemModel item, int delta) {
    final next = item.quantity + delta;
    if (next <= 0) {
      _remove(item);
    } else {
      _setQty(item, next);
    }
  }

  void _remove(CartItemModel item) {
    widget.bridge.setQuantity(item.product.id, 0);
    if (_last?.productId == item.product.id) _last = null;
    setState(() {});
    InAppNotification.info(
      'Removed ${item.product.name}',
      context: context,
      actionLabel: 'UNDO',
      onAction: () {
        widget.bridge.restoreItem(item);
        if (mounted) setState(() {});
      },
    );
  }

  void _undoLast() {
    final last = _last;
    if (last == null) return;
    widget.bridge.setQuantity(last.productId, last.quantityBefore);
    setState(() => _last = null);
    _showBanner('Undone: ${last.name}', _BannerKind.info);
  }

  Future<void> _editQty(CartItemModel item) async {
    final config = quantityConfigForUnit(item.product.unit, subUnitsPerPack: item.product.subUnitsPerPack);
    final ctrl = TextEditingController(text: formatCartQty(item.quantity));
    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        void submit() {
          final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
          if (v != null && v >= 0) Navigator.pop(ctx, v);
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.product.name,
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: _kSlate900),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${config.unitLabel} • ${MoneyFormatter.formatINR(item.unitPricePaise)} each',
                style: GoogleFonts.inter(fontSize: 11.5, color: _kSlate500),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final chip in config.chips)
                    ActionChip(
                      label: Text(chip.label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                      backgroundColor: const Color(0xFFF1F5F9),
                      side: const BorderSide(color: _kSlate200),
                      onPressed: () => Navigator.pop(ctx, chip.value),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.jetBrainsMono(fontSize: 20, fontWeight: FontWeight.w800),
                      decoration: InputDecoration(
                        labelText: 'Quantity',
                        suffixText: item.product.unit,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onSubmitted: (_) => submit(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kSlate900,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Set', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (result == null || !mounted) return;
    final fresh = _itemFor(item.product.id);
    if (fresh == null) return;
    if (result <= 0) {
      _remove(fresh);
    } else {
      _setQty(fresh, result);
    }
  }

  void _exit(RapidScanExit exit) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(exit);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final items = widget.bridge.cartItems().reversed.toList();
    final lastItem = _last == null ? null : _itemFor(_last!.productId);
    final totalQty = items.fold<double>(0, (s, i) => s + i.quantity);
    final cameraHeight = (MediaQuery.of(context).size.height * 0.36).clamp(220.0, 340.0);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: Column(
        children: [
          SizedBox(height: cameraHeight + MediaQuery.of(context).padding.top, child: _buildCamera()),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Column(
                children: [
                  _buildBanner(),
                  _buildListHeader(items.length, totalQty),
                  // The last-scan card scrolls with the list, so only thin
                  // rows stay fixed and a short phone never runs out of room.
                  Expanded(
                    child: items.isEmpty
                        ? _buildEmpty()
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                            physics: const BouncingScrollPhysics(),
                            children: [
                              if (lastItem != null) _buildLastScanCard(lastItem),
                              for (final item in items)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: _buildItemRow(item),
                                ),
                            ],
                          ),
                  ),
                  _buildBottomBar(items.isNotEmpty),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCamera() {
    return LayoutBuilder(builder: (context, box) {
      final top = MediaQuery.of(context).padding.top;
      final w = box.maxWidth;
      final h = box.maxHeight;
      // A wide window suits 1D barcodes; only codes inside it are read, so
      // the pack next to the one being scanned is never picked up.
      final window = Rect.fromCenter(
        center: Offset(w / 2, top + (h - top) / 2 + 12),
        width: w * 0.8,
        height: (h - top) * 0.46,
      );

      return Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            scanWindow: window,
            tapToFocus: true,
            errorBuilder: (context, error) => _buildCameraError(error),
          ),
          CustomPaint(painter: _WindowMaskPainter(window, _paused ? _kSlate500 : _kAmber)),
          if (!_paused)
            AnimatedBuilder(
              animation: _laser,
              builder: (_, _) => Positioned(
                left: window.left + 10,
                width: window.width - 20,
                top: window.top + 6 + _laser.value * (window.height - 12),
                child: Container(
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: _kRed,
                    boxShadow: [BoxShadow(color: _kRed.withValues(alpha: 0.7), blurRadius: 8, spreadRadius: 1)],
                  ),
                ),
              ),
            ),
          IgnorePointer(
            child: FadeTransition(
              opacity: Tween(begin: 0.35, end: 0.0).animate(_flash),
              child: Container(color: _flashColor),
            ),
          ),
          Positioned(top: top + 6, left: 8, right: 8, child: _buildTopBar()),
          Positioned(
            left: 0,
            right: 0,
            top: window.bottom + 10,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: _buildStatusPill()),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildCameraError(MobileScannerException error) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(denied ? Icons.no_photography_outlined : Icons.error_outline, color: Colors.white70, size: 36),
          const SizedBox(height: 10),
          Text(
            denied
                ? 'Camera permission is off. Allow camera access in Settings to scan, or type the barcode.'
                : 'Camera could not start. You can still type the barcode.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _manualEntry,
            icon: const Icon(Icons.keyboard_alt_outlined, color: Colors.white, size: 18),
            label: const Text('Type Barcode', style: TextStyle(color: Colors.white)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _roundButton({required IconData icon, required VoidCallback onTap, bool active = false, String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: active ? _kAmber : Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icon, size: 20, color: active ? _kSlate900 : Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        _roundButton(icon: Icons.close_rounded, onTap: () => _exit(RapidScanExit.done), tooltip: 'Close'),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.barcode_reader, size: 16, color: _kAmber),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Rapid Scan • ${widget.bridge.billTitle()}',
                    style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        ValueListenableBuilder<bool>(
          valueListenable: ScanFeedbackService.instance.beepEnabled,
          builder: (_, on, _) => _roundButton(
            icon: on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            onTap: () => ScanFeedbackService.instance.setBeepEnabled(!on),
            tooltip: on ? 'Beep on' : 'Beep off',
          ),
        ),
        const SizedBox(width: 6),
        _roundButton(
          icon: Icons.zoom_in_rounded,
          onTap: _toggleCloseUp,
          active: _closeUp,
          tooltip: 'Close-up for small barcodes',
        ),
        const SizedBox(width: 6),
        _roundButton(
          icon: _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
          onTap: _toggleTorch,
          active: _torchOn,
          tooltip: 'Torch',
        ),
      ],
    );
  }

  Widget _buildStatusPill() {
    final String text;
    final IconData icon;
    if (_paused) {
      text = 'Paused — tap ▶ to resume';
      icon = Icons.pause_circle_outline_rounded;
    } else if (_busy) {
      text = 'Adding…';
      icon = Icons.hourglass_top_rounded;
    } else {
      text = 'Point at barcode • $_scanCount scanned';
      icon = Icons.center_focus_strong_rounded;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: _paused ? Colors.white70 : _kGreen),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _roundButton(
          icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          onTap: _togglePause,
          tooltip: _paused ? 'Resume scanning' : 'Pause scanning',
        ),
      ],
    );
  }

  Widget _buildBanner() {
    final b = _banner;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: b == null
          ? const SizedBox(height: 10, key: ValueKey('none'))
          : Container(
              key: ValueKey(b.text),
              margin: const EdgeInsets.fromLTRB(14, 12, 14, 2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: switch (b.kind) {
                  _BannerKind.success => const Color(0xFFECFDF5),
                  _BannerKind.error => const Color(0xFFFEF2F2),
                  _BannerKind.info => const Color(0xFFF1F5F9),
                },
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: switch (b.kind) {
                    _BannerKind.success => const Color(0xFFA7F3D0),
                    _BannerKind.error => const Color(0xFFFECACA),
                    _BannerKind.info => _kSlate200,
                  },
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    switch (b.kind) {
                      _BannerKind.success => Icons.check_circle_rounded,
                      _BannerKind.error => Icons.error_rounded,
                      _BannerKind.info => Icons.info_rounded,
                    },
                    size: 18,
                    color: switch (b.kind) {
                      _BannerKind.success => const Color(0xFF059669),
                      _BannerKind.error => const Color(0xFFDC2626),
                      _BannerKind.info => _kSlate500,
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      b.text,
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: _kSlate900),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildListHeader(int lines, double totalQty) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
      child: Row(
        children: [
          Flexible(
            child: Text(
              'BILL ITEMS ($lines)  • Qty ${formatCartQty(totalQty)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: _kSlate500, letterSpacing: 0.6),
            ),
          ),
          const SizedBox(width: 6),
          TextButton.icon(
            onPressed: _manualEntry,
            icon: const Icon(Icons.keyboard_alt_outlined, size: 16),
            label: Text('Type code', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
            style: TextButton.styleFrom(foregroundColor: _kSlate900, visualDensity: VisualDensity.compact),
          ),
        ],
      ),
    );
  }

  Widget _buildLastScanCard(CartItemModel item) {
    const quick = [1.0, 2.0, 3.0, 5.0, 10.0];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kGreen.withValues(alpha: 0.6), width: 1.4),
        boxShadow: [BoxShadow(color: _kGreen.withValues(alpha: 0.10), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(6)),
                child: Text(
                  'LAST SCANNED',
                  style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFF047857)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.product.name,
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: _kSlate900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: _undoLast,
                icon: const Icon(Icons.undo_rounded, size: 16),
                label: const Text('Undo'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  visualDensity: VisualDensity.compact,
                  textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _stepper(item, large: true),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${MoneyFormatter.formatINR(item.unitPricePaise)} × ${formatCartQty(item.quantity)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 11.5, color: _kSlate500),
                ),
              ),
              Text(
                MoneyFormatter.formatINR(item.grossTotalPaise),
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, color: _kSlate900)
                    .copyWith(fontFeatures: MoneyFormatter.tabularFeatures),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Quick quantity — wraps instead of scrolling sideways, so every
          // chip stays visible on a 360dp phone.
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final q in quick)
                ChoiceChip(
                  label: Text('×${formatCartQty(q)}'),
                  selected: item.quantity == q,
                  onSelected: (_) => _setQty(item, q),
                  labelStyle: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: item.quantity == q ? Colors.white : _kSlate900,
                  ),
                  selectedColor: _kSlate900,
                  backgroundColor: const Color(0xFFF1F5F9),
                  side: const BorderSide(color: _kSlate200),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                ),
              ActionChip(
                avatar: const Icon(Icons.edit_rounded, size: 14),
                label: const Text('Custom'),
                onPressed: () => _editQty(item),
                labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                backgroundColor: const Color(0xFFFFFBEB),
                side: const BorderSide(color: Color(0xFFFDE68A)),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepper(CartItemModel item, {bool large = false}) {
    final size = large ? 34.0 : 30.0;
    Widget btn(IconData icon, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kSlate200),
            ),
            child: Icon(icon, size: 18, color: _kSlate900),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(item.quantity <= 1 ? Icons.delete_outline_rounded : Icons.remove_rounded, () => _step(item, -1)),
        InkWell(
          onTap: () => _editQty(item),
          child: Container(
            constraints: BoxConstraints(minWidth: large ? 44 : 38),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            child: Text(
              formatCartQty(item.quantity),
              style: GoogleFonts.jetBrainsMono(fontSize: large ? 17 : 15, fontWeight: FontWeight.w800, color: _kSlate900),
            ),
          ),
        ),
        btn(Icons.add_rounded, () => _step(item, 1)),
      ],
    );
  }

  Widget _buildItemRow(CartItemModel item) {
    final isLast = item.product.id == _last?.productId;
    return Dismissible(
      key: ValueKey('scan_${item.product.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
      ),
      onDismissed: (_) => _remove(item),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isLast ? _kGreen.withValues(alpha: 0.5) : _kSlate200),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _editQty(item),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.product.name,
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _kSlate900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${MoneyFormatter.formatINR(item.unitPricePaise)} × ${formatCartQty(item.quantity)} ${item.product.unit}',
                      style: GoogleFonts.inter(fontSize: 11, color: _kSlate500),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  MoneyFormatter.formatINR(item.grossTotalPaise),
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: _kSlate900)
                      .copyWith(fontFeatures: MoneyFormatter.tabularFeatures),
                ),
                const SizedBox(height: 4),
                _stepper(item),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.barcode_reader, size: 44, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 10),
            Text(
              'Scan items one after another',
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF334155)),
            ),
            const SizedBox(height: 4),
            Text(
              'Each beep adds the item to the bill. Show the same pack again for one more, '
              'or set the quantity right here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: _kSlate500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(bool hasItems) {
    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 10 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _kSlate200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BILL TOTAL', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: _kSlate500)),
                Text(
                  MoneyFormatter.formatINR(widget.bridge.totalPaise()),
                  style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w900, color: _kSlate900)
                      .copyWith(fontFeatures: MoneyFormatter.tabularFeatures),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => _exit(RapidScanExit.done),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 46),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Done', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800, color: _kSlate900)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: hasItems ? () => _exit(RapidScanExit.checkout) : null,
            icon: const Icon(Icons.shopping_cart_checkout_rounded, size: 18),
            label: Text('Checkout', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 46),
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Darkens everything outside the scan window and draws its corner marks.
class _WindowMaskPainter extends CustomPainter {
  final Rect window;
  final Color accent;

  _WindowMaskPainter(this.window, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(window, const Radius.circular(14));
    final mask = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(mask, Paint()..color = Colors.black.withValues(alpha: 0.55));

    final p = Paint()
      ..color = accent
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 26.0;
    final r = window;
    for (final c in [
      [r.topLeft, const Offset(len, 0), const Offset(0, len)],
      [r.topRight, const Offset(-len, 0), const Offset(0, len)],
      [r.bottomLeft, const Offset(len, 0), const Offset(0, -len)],
      [r.bottomRight, const Offset(-len, 0), const Offset(0, -len)],
    ]) {
      final o = c[0];
      canvas.drawLine(o, o + c[1], p);
      canvas.drawLine(o, o + c[2], p);
    }
  }

  @override
  bool shouldRepaint(_WindowMaskPainter old) => old.window != window || old.accent != accent;
}
