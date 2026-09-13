import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/admin_auth_service.dart';
import '../theme/admin_theme.dart';
import 'dashboard_screen.dart';
import 'merchants_screen.dart';
import 'inactive_radar_screen.dart';
import 'vertical_analytics_screen.dart';
import 'push_notifications_screen.dart';
import 'coupons_screen.dart';
import 'broadcast_screen.dart';

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String? badge;
  final String category;
  final Widget Function() build;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.build,
    required this.category,
    this.badge,
  });
}

/// The admin console's responsive navigation shell.
/// Above 860px width: Fixed rich dark left sidebar.
/// Below 860px width: Mobile App Bar + Quick Bottom Bar + Enterprise Navigation Drawer.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  static const double _wideBreakpoint = 860;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selected = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late final List<_NavItem> _items = [
    _NavItem(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
      label: 'Dashboard',
      category: 'OPERATIONS',
      build: () => const DashboardScreen(),
    ),
    _NavItem(
      icon: Icons.storefront_outlined,
      selectedIcon: Icons.storefront_rounded,
      label: 'Merchants',
      category: 'OPERATIONS',
      build: () => const MerchantsScreen(),
    ),
    _NavItem(
      icon: Icons.radar_outlined,
      selectedIcon: Icons.radar_rounded,
      label: 'Inactive Radar',
      category: 'OPERATIONS',
      badge: 'DROPOFF',
      build: () => const InactiveRadarScreen(),
    ),
    _NavItem(
      icon: Icons.pie_chart_outline_rounded,
      selectedIcon: Icons.pie_chart_rounded,
      label: 'Vertical Analytics',
      category: 'INTELLIGENCE',
      badge: 'INSIGHTS',
      build: () => const VerticalAnalyticsScreen(),
    ),
    _NavItem(
      icon: Icons.notifications_active_outlined,
      selectedIcon: Icons.notifications_active_rounded,
      label: 'Push Alerts (FCM)',
      category: 'ENGAGEMENT',
      badge: 'DISPATCH',
      build: () => const PushNotificationsScreen(),
    ),
    _NavItem(
      icon: Icons.local_offer_outlined,
      selectedIcon: Icons.local_offer_rounded,
      label: 'Coupons',
      category: 'ENGAGEMENT',
      build: () => const CouponsScreen(),
    ),
    _NavItem(
      icon: Icons.system_security_update_rounded,
      selectedIcon: Icons.system_security_update_rounded,
      label: 'Release & Control',
      category: 'PLATFORM',
      badge: 'v4.21',
      build: () => const BroadcastScreen(),
    ),
  ];

  void _showMoreBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AdminColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      Text('More Admin Modules', style: AdminTheme.heading(18)),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: AdminColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (int i = 3; i < _items.length; i++)
                      InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() => _selected = i);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: (MediaQuery.of(context).size.width - 44) / 2,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _selected == i ? AdminColors.accentSoft : AdminColors.bgElevated,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _selected == i ? AdminColors.accentBorder : AdminColors.borderDark,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _items[i].selectedIcon,
                                color: _selected == i ? AdminColors.accent : AdminColors.textWhite,
                                size: 24,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _items[i].label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _selected == i ? AdminColors.accent : AdminColors.textWhite,
                                ),
                              ),
                              if (_items[i].badge != null) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AdminColors.accent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _items[i].badge!,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: AdminColors.accent,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= AdminShell._wideBreakpoint;
    final content = IndexedStack(
      index: _selected,
      children: [for (final item in _items) item.build()],
    );

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            _DesktopSidebar(
              items: _items,
              selected: _selected,
              onSelect: (i) => setState(() => _selected = i),
            ),
            Expanded(child: content),
          ],
        ),
      );
    }

    // Determine bottom nav selected index (0: Dashboard, 1: Merchants, 2: Inactive Radar, 3: More)
    final bottomIndex = _selected <= 2 ? _selected : 3;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AdminColors.textWhite),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _items[_selected].selectedIcon,
              color: AdminColors.accent,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(_items[_selected].label, style: AdminTheme.heading(16)),
          ],
        ),
        actions: const [_AccountMenu(compact: true)],
      ),
      drawer: _MobileDrawer(
        items: _items,
        selected: _selected,
        onSelect: (i) {
          Navigator.pop(context);
          setState(() => _selected = i);
        },
      ),
      body: content,
      bottomNavigationBar: NavigationBar(
        selectedIndex: bottomIndex,
        onDestinationSelected: (i) {
          if (i == 3) {
            _showMoreBottomSheet();
          } else {
            setState(() => _selected = i);
          }
        },
        height: 64,
        backgroundColor: AdminColors.bgSidebar,
        indicatorColor: AdminColors.accentSoft,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined, color: AdminColors.textMuted),
            selectedIcon: Icon(Icons.dashboard_rounded, color: AdminColors.accent),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined, color: AdminColors.textMuted),
            selectedIcon: Icon(Icons.storefront_rounded, color: AdminColors.accent),
            label: 'Merchants',
          ),
          NavigationDestination(
            icon: Icon(Icons.radar_outlined, color: AdminColors.textMuted),
            selectedIcon: Icon(Icons.radar_rounded, color: AdminColors.accent),
            label: 'Radar',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined, color: AdminColors.textMuted),
            selectedIcon: Icon(Icons.grid_view_rounded, color: AdminColors.accent),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  final List<_NavItem> items;
  final int selected;
  final ValueChanged<int> onSelect;

  const _DesktopSidebar({
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: AdminColors.bgSidebar,
        border: Border(right: BorderSide(color: AdminColors.borderDark)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AdminColors.accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: AdminColors.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'KamaiPlus',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          'Admin Console',
                          style: TextStyle(
                            color: Colors.white54,
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    if (i == 0 || items[i].category != items[i - 1].category) ...[
                      Padding(
                        padding: EdgeInsets.fromLTRB(22, i == 0 ? 6 : 18, 20, 6),
                        child: Text(
                          items[i].category,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ],
                    _SidebarButton(
                      icon: selected == i ? items[i].selectedIcon : items[i].icon,
                      label: items[i].label,
                      badge: items[i].badge,
                      selected: selected == i,
                      onTap: () => onSelect(i),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: _AccountMenu(compact: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileDrawer extends StatelessWidget {
  final List<_NavItem> items;
  final int selected;
  final ValueChanged<int> onSelect;

  const _MobileDrawer({
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AdminColors.bgSidebar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AdminColors.accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: AdminColors.accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'KamaiPlus',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Super Admin System',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    if (i == 0 || items[i].category != items[i - 1].category) ...[
                      Padding(
                        padding: EdgeInsets.fromLTRB(22, i == 0 ? 6 : 16, 20, 6),
                        child: Text(
                          items[i].category,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ],
                    _SidebarButton(
                      icon: selected == i ? items[i].selectedIcon : items[i].icon,
                      label: items[i].label,
                      badge: items[i].badge,
                      selected: selected == i,
                      onTap: () => onSelect(i),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: _AccountMenu(compact: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          color: selected ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                  color: selected ? AdminColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 9),
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : Colors.white60,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white60,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected ? AdminColors.accent : Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: selected ? Colors.white : Colors.white70,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the signed-in email + a sign-out action. Two visual forms sharing
/// one behavior: a plain inline block in the desktop sidebar's footer
/// (there's room to just show it), a compact icon + popup menu in the
/// mobile app bar (no room for the email inline without crowding the
/// screen title).
class _AccountMenu extends StatelessWidget {
  final bool compact;
  const _AccountMenu({required this.compact});

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    if (!compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            email,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => AdminAuthService.instance.signOut(),
            icon: const Icon(
              Icons.logout_rounded,
              size: 16,
              color: Colors.white70,
            ),
            label: const Text(
              'Sign out',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
            ),
          ),
        ],
      );
    }

    return PopupMenuButton<String>(
      icon: const Icon(Icons.account_circle_outlined, color: AdminColors.textWhite),
      onSelected: (v) {
        if (v == 'signout') AdminAuthService.instance.signOut();
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            email,
            style: const TextStyle(color: AdminColors.textMuted, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'signout',
          child: Row(
            children: [
              Icon(Icons.logout_rounded, size: 18, color: AdminColors.red),
              SizedBox(width: 10),
              Text('Sign out', style: TextStyle(color: AdminColors.red)),
            ],
          ),
        ),
      ],
    );
  }
}
