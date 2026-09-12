import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/admin_auth_service.dart';
import '../theme/admin_theme.dart';
import 'dashboard_screen.dart';
import 'merchants_screen.dart';
import 'coupons_screen.dart';
import 'broadcast_screen.dart';

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget Function() build;
  const _NavItem(this.icon, this.selectedIcon, this.label, this.build);
}

/// The admin console's whole navigation shell — responsive, not
/// desktop-only: a fixed left sidebar above [_wideBreakpoint], a bottom
/// [NavigationBar] + compact top app bar below it. An internal tool still
/// gets opened from a phone often enough (checking a merchant while away
/// from a desk) that a 232px-wide sidebar eating most of a narrow screen
/// isn't acceptable — this mirrors the same wide/narrow split
/// `dashboard_screen.dart`'s own `LayoutBuilder` already uses internally.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  static const double _wideBreakpoint = 760;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selected = 0;

  late final List<_NavItem> _items = [
    _NavItem(
      Icons.dashboard_outlined,
      Icons.dashboard_rounded,
      'Dashboard',
      () => const DashboardScreen(),
    ),
    _NavItem(
      Icons.storefront_outlined,
      Icons.storefront_rounded,
      'Merchants',
      () => const MerchantsScreen(),
    ),
    _NavItem(
      Icons.local_offer_outlined,
      Icons.local_offer_rounded,
      'Coupons',
      () => const CouponsScreen(),
    ),
    _NavItem(
      Icons.campaign_outlined,
      Icons.campaign_rounded,
      'Broadcast',
      () => const BroadcastScreen(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isWide =
        MediaQuery.of(context).size.width >= AdminShell._wideBreakpoint;
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

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.admin_panel_settings_rounded,
              color: AdminColors.accent,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(_items[_selected].label, style: AdminTheme.heading(16)),
          ],
        ),
        actions: [_AccountMenu(compact: true)],
      ),
      body: content,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selected,
        onDestinationSelected: (i) => setState(() => _selected = i),
        height: 64,
        backgroundColor: AdminColors.surface,
        indicatorColor: AdminColors.accentSoft,
        destinations: [
          for (final item in _items)
            NavigationDestination(
              icon: Icon(item.icon, color: AdminColors.inkMuted),
              selectedIcon: Icon(item.selectedIcon, color: AdminColors.accent),
              label: item.label,
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
      width: 232,
      color: AdminColors.ink,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: Row(
                children: [
                  Icon(
                    Icons.admin_panel_settings_rounded,
                    color: AdminColors.accent,
                    size: 22,
                  ),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'KamaiPlus Admin',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            for (int i = 0; i < items.length; i++)
              _SidebarButton(
                icon: selected == i ? items[i].selectedIcon : items[i].icon,
                label: items[i].label,
                selected: selected == i,
                onTap: () => onSelect(i),
              ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(color: Colors.white12, height: 1),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
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
  final bool selected;
  final VoidCallback onTap;

  const _SidebarButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          color: selected
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.transparent,
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
      icon: const Icon(Icons.account_circle_outlined, color: AdminColors.ink),
      onSelected: (v) {
        if (v == 'signout') AdminAuthService.instance.signOut();
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            email,
            style: const TextStyle(color: AdminColors.inkMuted, fontSize: 12),
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
