import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_pulse_tab.dart';
import '../pos/pos_billing_screen.dart';
import '../khata/khata_screen.dart';
import '../products/products_screen.dart';
import '../menu/menu_screen.dart';
import '../../services/app_control_service.dart';
import '../common/kamai_bottom_nav.dart';

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
    _pageController.dispose();
    super.dispose();
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

