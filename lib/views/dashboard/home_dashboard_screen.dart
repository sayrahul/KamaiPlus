import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'home_pulse_tab.dart';
import '../pos/pos_billing_screen.dart';
import '../khata/khata_screen.dart';
import '../products/products_screen.dart';
import '../menu/menu_screen.dart';
import '../../services/app_control_service.dart';
import '../../services/daily_summary_service.dart';
import '../../services/firestore_sync_service.dart';
import '../common/kamai_bottom_nav.dart';
import '../common/in_app_notification.dart';

class HomeDashboardScreen extends StatefulWidget {
  final int initialIndex;
  final bool autoOpenCheckout;
  final bool autoOpenCustomerDropdown;
  final bool autoOpenSplit;
  final bool autoOpenFirstEdit;

  const HomeDashboardScreen({
    super.key,
    this.initialIndex = 2,
    this.autoOpenCheckout = false,
    this.autoOpenCustomerDropdown = false,
    this.autoOpenSplit = false,
    this.autoOpenFirstEdit = false,
  });

  static final GlobalKey<HomeDashboardScreenState> dashboardKey = GlobalKey<HomeDashboardScreenState>();

  static void switchTab(BuildContext context, int index) {
    if (index == 4) {
      if (dashboardKey.currentState != null) {
        Navigator.popUntil(context, (route) => route.isFirst);
        final state = dashboardKey.currentState!;
        MenuScreen.show(
          state.context,
          currentTabIndex: state._currentIndex,
          onNavigateTab: (idx) => state.setTab(idx),
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => HomeDashboardScreen(key: dashboardKey, initialIndex: 2)),
          (route) => false,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (dashboardKey.currentContext != null) {
            MenuScreen.show(
              dashboardKey.currentContext!,
              currentTabIndex: 2,
              onNavigateTab: (idx) => dashboardKey.currentState?.setTab(idx),
            );
          }
        });
      }
      return;
    }

    if (dashboardKey.currentState != null) {
      dashboardKey.currentState!.setTab(index);
      Navigator.popUntil(context, (route) => route.isFirst);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => HomeDashboardScreen(key: dashboardKey, initialIndex: index)),
        (route) => false,
      );
    }
  }

  @override
  State<HomeDashboardScreen> createState() => HomeDashboardScreenState();
}

class HomeDashboardScreenState extends State<HomeDashboardScreen> {
  int _currentIndex = 2;
  late final PageController _pageController;
  late final List<Widget> _screens;
  bool _forceUpdatePromptShown = false;
  /// Maintenance banner is shown once per app session, not on every config
  /// push — the admin may toggle other fields while it stays on.
  bool _maintenanceNoticeShown = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = (widget.initialIndex >= 0 && widget.initialIndex < 4) ? widget.initialIndex : 2;
    _pageController = PageController(initialPage: _currentIndex);
    _screens = [
      HomePulseTab(
        onNavigateToPos: () => setTab(2),
        onNavigateToKhata: () => setTab(3),
        onNavigateToProducts: () => setTab(1),
      ),
      ProductsScreen(autoOpenFirstEdit: widget.autoOpenFirstEdit),
      PosBillingScreen(
        autoOpenCheckout: widget.autoOpenCheckout,
        autoOpenCustomerDropdown: widget.autoOpenCustomerDropdown,
        autoOpenSplit: widget.autoOpenSplit,
      ),
      const KhataScreen(),
    ];

    // Fire-and-forget: shows yesterday's sales recap once per calendar day,
    // the first time the dashboard is opened that day.
    DailySummaryService.checkAndNotify();

    // Listen live to Super Admin Remote Version & Force Update Config
    FirestoreSyncService.instance.globalConfigNotifier.addListener(_checkVersionPolicy);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkVersionPolicy();
    });

    if (widget.initialIndex == 4) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          MenuScreen.show(
            context,
            currentTabIndex: _currentIndex,
            onNavigateTab: (idx) => setTab(idx),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    FirestoreSyncService.instance.globalConfigNotifier.removeListener(_checkVersionPolicy);
    _pageController.dispose();
    super.dispose();
  }

  /// The versionCode this build actually has, read from the installed package.
  ///
  /// This used to be `const currentVersionCode = 42201` — a constant someone
  /// had to remember to hand-edit on every release. Forget it once and the
  /// force-update gate compares the WRONG number: either it never fires (a
  /// broken build stays in the field) or it fires forever (every merchant is
  /// nagged to update to the version they already have). Reading the real one
  /// removes the release-day footgun entirely.
  int? _installedVersionCode;

  Future<int> _currentVersionCode() async {
    final cached = _installedVersionCode;
    if (cached != null) return cached;
    try {
      final info = await PackageInfo.fromPlatform();
      final parsed = int.tryParse(info.buildNumber);
      if (parsed != null && parsed > 0) {
        _installedVersionCode = parsed;
        return parsed;
      }
    } catch (_) {}
    // Unreadable package info must not look like an ancient build, or every
    // merchant gets a force-update dialog they cannot satisfy. A very high
    // number fails safe: no prompt.
    _installedVersionCode = 1 << 30;
    return _installedVersionCode!;
  }

  Future<void> _checkVersionPolicy() async {
    final config = FirestoreSyncService.instance.globalConfigNotifier.value;
    if (config == null || !mounted) return;

    // 1. Maintenance mode. Written by the Admin Console's Release & Control
    //    screen since it was built, and read by NOTHING until now — the admin
    //    flipped the toggle and every merchant carried on unaware.
    final maintenanceOn = config['maintenance_mode'] == true;
    if (maintenanceOn && !_maintenanceNoticeShown) {
      _maintenanceNoticeShown = true;
      final msg = config['maintenance_message']?.toString().trim();
      InAppNotification.show(
        context: context,
        message: (msg == null || msg.isEmpty)
            ? 'KamaiPlus is undergoing scheduled maintenance. Billing keeps working offline; cloud sync may be delayed.'
            : msg,
        customIcon: Icons.cloud_off_rounded,
        customColor: const Color(0xFFF59E0B),
        duration: const Duration(seconds: 8),
      );
    }

    // 2. Version policy.
    final minVersionCode = (config['min_version_code'] as num?)?.toInt() ?? 0;
    final forceUpdate = config['force_update'] == true;
    final latestName = config['latest_version_name']?.toString() ?? '';
    final playStoreUrl = config['play_store_url']?.toString() ??
        'https://play.google.com/store/apps/details?id=com.kamaiplus.pos';

    final currentVersionCode = await _currentVersionCode();
    if (!mounted) return;

    if (currentVersionCode < minVersionCode && !_forceUpdatePromptShown) {
      _forceUpdatePromptShown = true;
      _showUpdateDialog(
        latestVersionName: latestName.isEmpty ? 'the latest version' : latestName,
        forceUpdate: forceUpdate,
        playStoreUrl: playStoreUrl,
      );
    }
  }

  void _showUpdateDialog({
    required String latestVersionName,
    required bool forceUpdate,
    required String playStoreUrl,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (ctx) => PopScope(
        canPop: !forceUpdate,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.rocket_launch_rounded,
                    color: Color(0xFF10B981),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Naya Update Upalabhdh Hai! 🚀',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Version $latestVersionName',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF334155),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  forceUpdate
                      ? 'Important security improvements and new features are available. Please update KamaiPlus from Google Play to continue billing.'
                      : 'A faster and improved version of KamaiPlus is available on Google Play. Update now for the best retail experience.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    color: const Color(0xFF475569),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final uri = Uri.parse(playStoreUrl);
                      try {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.shop_two_rounded, size: 20),
                    label: Text(
                      'Update on Google Play',
                      style: GoogleFonts.outfit(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (!forceUpdate) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      _forceUpdatePromptShown = false;
                      Navigator.pop(ctx);
                    },
                    child: Text(
                      'Later',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Instant switch, no sluggish transition
  void setTab(int index) {
    if (index < 0 || index >= _screens.length) return;
    if (_currentIndex == index) return;
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
    _pageController.jumpToPage(index);
  }

  void _onBottomNavTap(int index) {
    if (index == 4) {
      HapticFeedback.selectionClick();
      MenuScreen.show(
        context,
        currentTabIndex: _currentIndex,
        onNavigateTab: (targetIndex) => setTab(targetIndex),
      );
      return;
    }
    setTab(index);
  }

  void _onPageChanged(int index) {
    if (_currentIndex != index) {
      HapticFeedback.selectionClick();
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentIndex != 0) {
          setTab(0);
        } else {
          AppControlService.minimizeToBackground();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: PageView(
          controller: _pageController,
          onPageChanged: _onPageChanged,
          physics: const NeverScrollableScrollPhysics(),
          children: _screens,
        ),
        bottomNavigationBar: KamaiBottomNav(
          currentIndex: _currentIndex,
          onTabTap: _onBottomNavTap,
        ),
      ),
    );
  }
}

