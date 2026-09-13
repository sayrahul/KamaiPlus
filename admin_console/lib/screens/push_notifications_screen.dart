import 'package:flutter/material.dart';
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
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note_rounded, size: 20, color: AdminColors.accent),
              const SizedBox(width: 8),
              Text('Compose Message', style: AdminTheme.heading(16)),
            ],
          ),
          const SizedBox(height: 18),

          // Title with Emoji shortcuts
          const Text('Notification Title', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _titleCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'e.g. ⚡ Special Update: Variant Matrix is Live!',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (final emoji in ['⚡', '🎉', '🔥', '📢', '💰', '👗', '🛒', '👑'])
                ActionChip(
                  label: Text(emoji, style: const TextStyle(fontSize: 14)),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onPressed: () => _addEmoji(emoji),
                ),
            ],
          ),
          const SizedBox(height: 18),

          // Body
          const Text('Message Body', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _bodyCtrl,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'e.g. Now easily manage sizes and colors in your clothing store without creating duplicate products.',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 18),

          // Target Audience
          const Text('Target Audience', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
          const Text('Action Destination (On Tap)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _actionRoute,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              decoration: InputDecoration(
                labelText: 'External URL (https://…)',
                hintText: 'https://kamaiplus.com/offer',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              keyboardType: TextInputType.url,
            ),
          ],
          const SizedBox(height: 24),

          // Dispatch CTA
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _handleSend,
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(_sending ? 'Dispatching…' : 'Send Push Notification Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: isSelected ? Colors.white : AdminColors.inkMuted),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      selected: isSelected,
      selectedColor: AdminColors.accent,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AdminColors.ink,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        fontSize: 12,
      ),
      onSelected: (_) => setState(() => _targetAudience = key),
    );
  }

  Widget _buildLivePreviewCard() {
    final title = _titleCtrl.text.trim().isNotEmpty ? _titleCtrl.text.trim() : 'KamaiPlus POS Update';
    final body = _bodyCtrl.text.trim().isNotEmpty
        ? _bodyCtrl.text.trim()
        : 'Your notification preview will appear here in real-time as you type.';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.phone_android_rounded, size: 18, color: AdminColors.accent),
              const SizedBox(width: 8),
              Text('Live Mobile Phone Preview', style: AdminTheme.heading(15)),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Exact mock-up of how cashiers will see this on their device status bar.',
            style: TextStyle(color: AdminColors.inkMuted, fontSize: 12),
          ),
          const SizedBox(height: 20),

          // Android Notification Shade Mockup
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B), // Dark Android shade
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top App Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AdminColors.accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 14),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'KamaiPlus POS',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const Text(
                      ' • now',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    ),
                    const Spacer(),
                    const Icon(Icons.expand_more_rounded, color: Color(0xFF94A3B8), size: 16),
                  ],
                ),
                const SizedBox(height: 10),

                // Notification Content
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),

                // Action Bar
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _actionRoute == 'pro_upgrade'
                                ? 'UPGRADE TO PRO 👑'
                                : _actionRoute == 'billing'
                                    ? 'OPEN POS 🧾'
                                    : 'OPEN APP ➔',
                            style: const TextStyle(color: AdminColors.accentSoft, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AdminColors.accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_rounded, color: AdminColors.accent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Target: ${_getAudienceLabel(_targetAudience)} • Reaches devices instantly.',
                    style: const TextStyle(color: AdminColors.accent, fontSize: 12, fontWeight: FontWeight.w600),
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
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, size: 20, color: AdminColors.accent),
              const SizedBox(width: 8),
              Text('Dispatched Notifications History', style: AdminTheme.heading(16)),
            ],
          ),
          const SizedBox(height: 16),
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
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.notifications_none_rounded, size: 36, color: AdminColors.inkFaint),
                        SizedBox(height: 8),
                        Text('No push notifications dispatched yet.', style: TextStyle(color: AdminColors.inkMuted)),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1, color: AdminColors.border),
                itemBuilder: (context, index) {
                  final notif = list[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    leading: CircleAvatar(
                      backgroundColor: AdminColors.accentSoft,
                      child: const Icon(Icons.notifications_active_rounded, color: AdminColors.accent, size: 20),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(notif.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AdminColors.surfaceSunken,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AdminColors.border),
                          ),
                          child: Text(
                            _getAudienceLabel(notif.targetAudience),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AdminColors.inkMuted),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(notif.body, style: const TextStyle(color: AdminColors.inkMuted, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          notif.sentAt != null ? _dateFmt.format(notif.sentAt!) : 'Just now',
                          style: const TextStyle(fontSize: 11, color: AdminColors.inkFaint),
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
