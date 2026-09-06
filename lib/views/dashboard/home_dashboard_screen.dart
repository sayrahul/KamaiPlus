import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_pulse_tab.dart';
import '../pos/pos_billing_screen.dart';
import '../khata/khata_screen.dart';
import '../products/products_screen.dart';
import '../menu/menu_screen.dart';

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  int _currentIndex = 2;
  late final PageController _pageController;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _screens = [
      HomePulseTab(
        onNavigateToPos: () => _setTab(2),
        onNavigateToKhata: () => _setTab(3),
        onNavigateToProducts: () => _setTab(1),
      ),
      const ProductsScreen(),
      const PosBillingScreen(),
      const KhataScreen(),
      MenuScreen(
        onNavigateTab: (index) => _setTab(index),
      ),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Instant switch, no sluggish transition
  void _setTab(int index) {
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
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFEEF2F6), width: 1.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x0A0F172A),
              blurRadius: 12,
              offset: Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 0: Home
                _buildNavItem(0, Icons.home_rounded, Icons.home_outlined, 'Home'),

                // 1: Product
                _buildNavItem(1, Icons.inventory_2_rounded, Icons.inventory_2_outlined, 'Product'),

                // 2: Center Elevated Billing Button (renamed to Billing)
                _buildCenterBillingButton(),

                // 3: Khata (renamed to Khata)
                _buildNavItem(3, Icons.menu_book_rounded, Icons.menu_book_outlined, 'Khata'),

                // 4: Menu
                _buildNavItem(4, Icons.grid_view_rounded, Icons.grid_view_outlined, 'Menu'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final isSelected = _currentIndex == index;
    const activeColor = Color(0xFF059669);
    const inactiveColor = Color(0xFF64748B);

    return InkWell(
      onTap: () => _setTab(index),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : inactiveIcon,
              size: 22,
              color: isSelected ? activeColor : inactiveColor,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? activeColor : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterBillingButton() {
    final isSelected = _currentIndex == 2;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _setTab(2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF059669)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: isSelected ? 0.4 : 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
            ),
            child: const Icon(
              Icons.point_of_sale_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Billing',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isSelected ? const Color(0xFF059669) : const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? const Color(0xFF059669) : Colors.transparent,
            ),
          ),
        ],
      ),
      ),
    );
  }
}
