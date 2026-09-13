import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/admin_models.dart';
import '../services/admin_firestore_service.dart';
import '../theme/admin_theme.dart';

class PushNotificationsScreen extends StatefulWidget {
  const PushNotificationsScreen({super.key});

  @override
  State<PushNotificationsScreen> createState() => _PushNotificationsScreenState();
}

class _PushNotificationsScreenState extends State<PushNotificationsScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();

  String _targetAudience = 'all'; // 'all', 'pro', 'free', 'inactive'
  String _actionRoute = 'home'; // 'home', 'billing', 'products', 'pro_upgrade', 'external'
  bool _sending = false;

  final DateFormat _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _addEmoji(String emoji) {
    final text = _titleCtrl.text;
    final selection = _titleCtrl.selection;
    if (selection.isValid && selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, emoji);
      _titleCtrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + emoji.length),
      );
    } else {
      _titleCtrl.text = '$emoji $text';
    }
    setState(() {});
  }

  Future<void> _handleSend() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a notification title.')),
      );
      return;
    }
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter notification body text.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.send_rounded, color: AdminColors.accent, size: 22),
            const SizedBox(width: 8),
            Text('Dispatch Push Notification?', style: AdminTheme.heading(16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Target Audience: ${_getAudienceLabel(_targetAudience)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminColors.surfaceSunken,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AdminColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(body, style: const TextStyle(color: AdminColors.inkMuted, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This will immediately dispatch a high-priority push alert to all targeted merchants.',
              style: TextStyle(color: AdminColors.inkMuted, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Dispatch Now'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _sending = true);
    try {
      final notif = AdminPushNotification(
        id: '',
        title: title,
        body: body,
        targetAudience: _targetAudience,
        actionRoute: _actionRoute,
        actionUrl: _urlCtrl.text.trim().isNotEmpty ? _urlCtrl.text.trim() : null,
        sentAt: DateTime.now(),
      );

      await AdminFirestoreService.instance.sendPushNotification(notif);

      _titleCtrl.clear();
      _bodyCtrl.clear();
      _urlCtrl.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Push notification dispatched successfully!'),
            backgroundColor: AdminColors.accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to dispatch notification: $e'), backgroundColor: AdminColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _getAudienceLabel(String key) {
    switch (key) {
      case 'pro':
        return 'Pro Subscribers Only';
      case 'free':
        return 'Free Tier Merchants';
      case 'inactive':
        return 'Inactive / Drop-off Stores';
      default:
        return 'All Merchants (Broadcast)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 960;

    return Scaffold(
      backgroundColor: AdminColors.surfaceSunken,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AdminColors.accentSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.notifications_active_rounded, color: AdminColors.accent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Push Notifications Dispatcher', style: AdminTheme.heading(22)),
                      const SizedBox(height: 2),
                      const Text(
                        'Broadcast high-priority announcements and targeted alerts directly to merchants.',
                        style: TextStyle(color: AdminColors.inkMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Responsive Two-Column Layout (Composer on Left, Preview on Right)
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _buildComposerCard()),
                    const SizedBox(width: 24),
                    Expanded(flex: 2, child: _buildLivePreviewCard()),
                  ],
                )
              else
                Column(
                  children: [
                    _buildComposerCard(),
                    const SizedBox(height: 20),
                    _buildLivePreviewCard(),
                  ],
                ),

              const SizedBox(height: 32),

              // Past Dispatch History
              _buildHistorySection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposerCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminColors.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminColors.borderDark, width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AdminColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.edit_note_rounded, size: 20, color: AdminColors.accent),
              ),
              const SizedBox(width: 10),
              Text('Compose Message', style: AdminTheme.heading(16)),
            ],
          ),
          const SizedBox(height: 18),

          // Title with Emoji shortcuts
          const Text('Notification Title', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AdminColors.textWhite)),
          const SizedBox(height: 8),
          TextField(
            controller: _titleCtrl,
            style: const TextStyle(color: AdminColors.textWhite, fontSize: 14),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'e.g. ⚡ Special Update: Variant Matrix is Live!',
              fillColor: AdminColors.bgSidebar,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AdminColors.borderDark)),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: [
              for (final emoji in ['⚡', '🎉', '🔥', '📢', '💰', '👗', '🛒', '👑'])
                ActionChip(
                  backgroundColor: AdminColors.bgElevated,
                  side: const BorderSide(color: AdminColors.borderDark),
                  label: Text(emoji, style: const TextStyle(fontSize: 14)),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onPressed: () => _addEmoji(emoji),
                ),
            ],
          ),
          const SizedBox(height: 18),

          // Body
          const Text('Message Body', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AdminColors.textWhite)),
          const SizedBox(height: 8),
          TextField(
            controller: _bodyCtrl,
            maxLines: 3,
            style: const TextStyle(color: AdminColors.textWhite, fontSize: 14),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'e.g. Now easily manage sizes and colors in your clothing store without creating duplicate products.',
              fillColor: AdminColors.bgSidebar,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AdminColors.borderDark)),
            ),
          ),
          const SizedBox(height: 18),

          // Target Audience
          const Text('Target Audience', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AdminColors.textWhite)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildAudienceChip('all', 'All Merchants', Icons.public_rounded),
              _buildAudienceChip('pro', 'Pro Members', Icons.workspace_premium_rounded),
              _buildAudienceChip('free', 'Free Starter', Icons.storefront_outlined),
              _buildAudienceChip('inactive', 'Inactive Stores', Icons.timer_outlined),
            ],
          ),
          const SizedBox(height: 18),

          // Action Route
          const Text('Action Destination (On Tap)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AdminColors.textWhite)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _actionRoute,
            dropdownColor: AdminColors.bgSidebar,
            style: const TextStyle(color: AdminColors.textWhite, fontSize: 14),
            decoration: InputDecoration(
              fillColor: AdminColors.bgSidebar,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AdminColors.borderDark)),
            ),
            items: const [
              DropdownMenuItem(value: 'home', child: Text('Open App Dashboard (Home)')),
              DropdownMenuItem(value: 'billing', child: Text('Open POS Counter Billing')),
              DropdownMenuItem(value: 'products', child: Text('Open Product Catalog')),
              DropdownMenuItem(value: 'pro_upgrade', child: Text('Open Pro Membership Upgrade')),
              DropdownMenuItem(value: 'external', child: Text('Open External Web Link')),
            ],
            onChanged: (v) => setState(() => _actionRoute = v ?? 'home'),
          ),
          if (_actionRoute == 'external') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtrl,
              style: const TextStyle(color: AdminColors.textWhite, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'External URL (https://…)',
                hintText: 'https://kamaiplus.com/offer',
                fillColor: AdminColors.bgSidebar,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AdminColors.borderDark)),
              ),
              keyboardType: TextInputType.url,
            ),
          ],
          const SizedBox(height: 24),

          // Dispatch CTA
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _handleSend,
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(_sending ? 'Dispatching…' : 'Send Push Notification Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudienceChip(String key, String label, IconData icon) {
    final isSelected = _targetAudience == key;
    return ChoiceChip(
      backgroundColor: AdminColors.bgElevated,
      selectedColor: AdminColors.accent,
      side: BorderSide(color: isSelected ? AdminColors.accentBorder : AdminColors.borderDark),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: isSelected ? Colors.white : AdminColors.textMuted),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      selected: isSelected,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AdminColors.textMuted,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
        fontSize: 12,
      ),
      onSelected: (_) => setState(() => _targetAudience = key),
    );
  }

  Widget _buildLivePreviewCard() {
    final title = _titleCtrl.text.trim().isNotEmpty ? _titleCtrl.text.trim() : 'KamaiPlus POS Update';
    final body = _bodyCtrl.text.trim().isNotEmpty
        ? _bodyCtrl.text.trim()
        : 'Your live alert message will render inside the Android status-bar notification drawer in real time.';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminColors.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminColors.borderDark, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AdminColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.phone_android_rounded, size: 18, color: AdminColors.accent),
              ),
              const SizedBox(width: 10),
              Text('Live Android Device Preview', style: AdminTheme.heading(15)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Exact interactive simulator of the heads-up notification drawer.',
            style: TextStyle(color: AdminColors.textFaint, fontSize: 12),
          ),
          const SizedBox(height: 20),

          // High-Fidelity Realistic Android Phone Frame
          Center(
            child: Container(
              width: 310,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(38),
                border: Border.all(color: const Color(0xFF334155), width: 7),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 30,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF0B1120),
                        Color(0xFF020617),
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Punch Hole Camera & Speaker
                      Center(
                        child: Container(
                          width: 60,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF1E293B),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Android Status Bar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            DateFormat('hh:mm').format(DateTime.now()),
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Row(
                            children: const [
                              Icon(Icons.wifi_rounded, size: 13, color: Colors.white70),
                              SizedBox(width: 4),
                              Icon(Icons.signal_cellular_4_bar_rounded, size: 13, color: Colors.white70),
                              SizedBox(width: 4),
                              Icon(Icons.battery_5_bar_rounded, size: 14, color: AdminColors.accent),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Heads-Up Drop Notification Drawer Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AdminColors.accent.withValues(alpha: 0.35),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AdminColors.accent.withValues(alpha: 0.12),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // App Brand Header
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [AdminColors.accent, AdminColors.accentGlow],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.point_of_sale_rounded,
                                    color: Colors.white,
                                    size: 13,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'KamaiPlus POS',
                                  style: GoogleFonts.inter(
                                    color: const Color(0xFFE2E8F0),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Text(
                                  ' • now',
                                  style: TextStyle(color: Color(0xFF64748B), fontSize: 10.5),
                                ),
                                const Spacer(),
                                const Icon(Icons.notifications_active_rounded, size: 12, color: AdminColors.accent),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Notification Title & Body
                            Text(
                              title,
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              body,
                              style: GoogleFonts.inter(
                                color: const Color(0xFF94A3B8),
                                fontSize: 11.5,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Quick Action Button
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AdminColors.accentSoft,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AdminColors.accent.withValues(alpha: 0.4)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _actionRoute == 'pro_upgrade'
                                            ? 'UPGRADE TO PRO 👑'
                                            : _actionRoute == 'billing'
                                                ? 'OPEN POS BILLING 🧾'
                                                : _actionRoute == 'products'
                                                    ? 'VIEW PRODUCTS 🛒'
                                                    : 'OPEN KAMAI+ ➔',
                                        style: GoogleFonts.inter(
                                          color: AdminColors.accent,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Android Home Navigation Bar
                      Container(
                        width: 90,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white38,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AdminColors.bgElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AdminColors.borderDark),
            ),
            child: Row(
              children: [
                const Icon(Icons.flash_on_rounded, color: AdminColors.accent, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Target Audience: ${_getAudienceLabel(_targetAudience)} • High-Priority Delivery',
                    style: GoogleFonts.inter(color: AdminColors.textWhite, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminColors.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminColors.borderDark, width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AdminColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.history_rounded, size: 20, color: AdminColors.accent),
              ),
              const SizedBox(width: 10),
              Text('Dispatched Notifications History', style: AdminTheme.heading(16)),
            ],
          ),
          const SizedBox(height: 18),
          StreamBuilder<List<AdminPushNotification>>(
            stream: AdminFirestoreService.instance.watchPushNotifications(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Error loading history: ${snapshot.error}', style: const TextStyle(color: AdminColors.red));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final list = snapshot.data!;
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.notifications_none_rounded, size: 36, color: AdminColors.textFaint),
                        SizedBox(height: 8),
                        Text('No push notifications dispatched yet.', style: TextStyle(color: AdminColors.textMuted)),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1, color: AdminColors.borderDark),
                itemBuilder: (context, index) {
                  final notif = list[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    leading: CircleAvatar(
                      backgroundColor: AdminColors.bgElevated,
                      child: const Icon(Icons.notifications_active_rounded, color: AdminColors.accent, size: 20),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            notif.title,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AdminColors.textWhite),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AdminColors.bgElevated,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AdminColors.borderDark),
                          ),
                          child: Text(
                            _getAudienceLabel(notif.targetAudience),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AdminColors.accent),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(notif.body, style: const TextStyle(color: AdminColors.textMuted, fontSize: 13)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, size: 12, color: AdminColors.accent),
                            const SizedBox(width: 4),
                            Text(
                              notif.sentAt != null ? _dateFmt.format(notif.sentAt!) : 'Just now',
                              style: const TextStyle(fontSize: 11, color: AdminColors.textFaint),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

