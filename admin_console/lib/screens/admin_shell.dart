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
  final String label;
  final Widget Function() build;
  const _NavItem(this.icon, this.label, this.build);
}

/// The admin console's whole navigation shell: a fixed left sidebar (this is
/// a desktop-first internal tool — no bottom-nav/mobile-first tradeoffs to
/// make here, unlike the POS app) plus a content area. Deliberately plain
/// `Navigator` push/pop for drill-downs (e.g. Merchants → one merchant's
/// detail) rather than a routing package — five-ish screens doesn't
/// justify the extra dependency and config surface for a v1 internal tool.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selected = 0;

  late final List<_NavItem> _items = [
    _NavItem(Icons.dashboard_rounded, 'Dashboard', () => const DashboardScreen()),
    _NavItem(Icons.storefront_rounded, 'Merchants', () => const MerchantsScreen()),
    _NavItem(Icons.local_offer_rounded, 'Coupons', () => const CouponsScreen()),
    _NavItem(Icons.campaign_rounded, 'Broadcast & Config', () => const BroadcastScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Scaffold(
      body: Row(
        children: [
          Container(
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
                        Icon(Icons.admin_panel_settings_rounded, color: AdminColors.accent, size: 22),
                        SizedBox(width: 8),
                        Text('KamaiPlus Admin', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                      ],
                    ),
                  ),
                  for (int i = 0; i < _items.length; i++)
                    _SidebarButton(
                      icon: _items[i].icon,
                      label: _items[i].label,
                      selected: _selected == i,
                      onTap: () => setState(() => _selected = i),
                    ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(email, style: const TextStyle(color: Colors.white70, fontSize: 11), overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => AdminAuthService.instance.signOut(),
                          icon: const Icon(Icons.logout_rounded, size: 16, color: Colors.white70),
                          label: const Text('Sign out', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _selected,
              children: [for (final item in _items) item.build()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarButton({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: selected ? AdminColors.accent : Colors.transparent, width: 3)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: selected ? Colors.white : Colors.white60),
              const SizedBox(width: 12),
              Text(label, style: TextStyle(color: selected ? Colors.white : Colors.white60, fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
