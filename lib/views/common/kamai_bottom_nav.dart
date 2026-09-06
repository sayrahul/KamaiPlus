import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../dashboard/home_dashboard_screen.dart';

class KamaiBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int>? onTabTap;

  const KamaiBottomNav({
    super.key,
    this.currentIndex = -1,
    this.onTabTap,
  });

  void _handleTap(BuildContext context, int index) {
    HapticFeedback.selectionClick();
    if (onTabTap != null) {
      onTabTap!(index);
      return;
    }

    HomeDashboardScreen.switchTab(context, index);
  }


  @override
  Widget build(BuildContext context) {
    return Container(
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
              _buildNavItem(context, 0, Icons.home_rounded, Icons.home_outlined, 'Home'),

              // 1: Product
              _buildNavItem(context, 1, Icons.inventory_2_rounded, Icons.inventory_2_outlined, 'Product'),

              // 2: Center Billing
              _buildCenterBillingButton(context),

              // 3: Khata
              _buildNavItem(context, 3, Icons.menu_book_rounded, Icons.menu_book_outlined, 'Khata'),

              // 4: Menu
              _buildNavItem(context, 4, Icons.grid_view_rounded, Icons.grid_view_outlined, 'Menu'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    int index,
    IconData activeIcon,
    IconData inactiveIcon,
    String label,
  ) {
    final isSelected = currentIndex == index;
    const activeColor = Color(0xFF059669);
    const inactiveColor = Color(0xFF64748B);

    return Expanded(
      child: InkWell(
        onTap: () => _handleTap(context, index),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
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
      ),
    );
  }

  Widget _buildCenterBillingButton(BuildContext context) {
    final isSelected = currentIndex == 2;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _handleTap(context, 2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
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
      ),
    );
  }
}
