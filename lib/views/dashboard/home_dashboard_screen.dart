import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_pulse_tab.dart';
import '../pos/pos_billing_screen.dart';
import '../khata/khata_screen.dart';
import '../products/products_screen.dart';
import '../menu/menu_screen.dart';

import '../common/kamai_bottom_nav.dart';

class HomeDashboardScreen extends StatefulWidget {
  final int initialIndex;
  const HomeDashboardScreen({super.key, this.initialIndex = 2});

  static final GlobalKey<HomeDashboardScreenState> dashboardKey = GlobalKey<HomeDashboardScreenState>();

  static void switchTab(BuildContext context, int index) {
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
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _screens = [
      HomePulseTab(
        onNavigateToPos: () => setTab(2),
        onNavigateToKhata: () => setTab(3),
        onNavigateToProducts: () => setTab(1),
      ),
      const ProductsScreen(),
      const PosBillingScreen(),
      const KhataScreen(),
      MenuScreen(
        isModal: false,
        currentTabIndex: 4,
        onNavigateTab: (index) => setTab(index),
      ),
    ];
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


  void _onPageChanged(int index) {
    if (_currentIndex != index) {
      HapticFeedback.selectionClick();
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics: const NeverScrollableScrollPhysics(),
        children: _screens,
      ),
      bottomNavigationBar: KamaiBottomNav(
        currentIndex: _currentIndex,
        onTabTap: setTab,
      ),
    );
  }
}

