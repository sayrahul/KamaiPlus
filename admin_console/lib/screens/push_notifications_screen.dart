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
  int _activeTab = 0; // 0: Campaign Dispatch, 1: FCM & Engine Settings, 2: History

  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();

  String _targetAudience = 'all'; // 'all', 'pro', 'free', 'inactive'
  String _actionRoute = 'home'; // 'home', 'billing', 'products', 'pro_upgrade', 'external'
  bool _sending = false;

  // Which channel(s) this message goes out on. Both used to fire on every
  // send, silently, which is why one "Send" landed as three notifications on
  // the merchant's phone — two in the tray and one banner inside the app.
  bool _sendPhoneAlert = true;
  bool _showInAppBanner = false;

  // FCM Settings State
  final _channelNameCtrl = TextEditingController(text: 'KamaiPlus POS Alerts & Invoices');
  final _defaultTopicCtrl = TextEditingController(text: 'all_merchants');
  final _geminiKeyCtrl = TextEditingController();
  bool _fcmEnabled = true;
  bool _pushNotificationsEnabled = true;
  bool _inAppBannerEnabled = true;
  bool _highPriority = true;
  bool _soundEnabled = true;
  bool _vibrateEnabled = true;
  bool _mirrorInAppBanner = true;
  bool _autoClosingReminder = true;
  bool _autoInactiveNudge = true;
  bool _autoLowStockAlert = true;

  bool _loadingSettings = true;
  bool _savingSettings = false;
  bool _sendingTestPing = false;

  final DateFormat _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  void initState() {
    super.initState();
    _loadFcmSettings();
  }

  Future<void> _loadFcmSettings() async {
    try {
      final config = await AdminFirestoreService.instance.getFcmConfig();
      final globalConfig = await AdminFirestoreService.instance.getGlobalConfig();
      if (mounted) {
        setState(() {
          _fcmEnabled = config['fcm_enabled'] ?? true;
          _pushNotificationsEnabled = config['push_notifications_enabled'] ?? true;
          _inAppBannerEnabled = config['in_app_banner_enabled'] ?? true;
          _geminiKeyCtrl.text = globalConfig?['gemini_api_key']?.toString() ?? '';
          _channelNameCtrl.text = config['channel_name'] ?? 'KamaiPlus POS Alerts & Invoices';
          _defaultTopicCtrl.text = config['default_topic'] ?? 'all_merchants';
          _highPriority = config['high_priority'] ?? true;
          _soundEnabled = config['sound_enabled'] ?? true;
          _vibrateEnabled = config['vibration_enabled'] ?? true;
          _mirrorInAppBanner = config['mirror_in_app_banner'] ?? true;
          _autoClosingReminder = config['auto_closing_reminder'] ?? true;
          _autoInactiveNudge = config['auto_inactive_nudge'] ?? true;
          _autoLowStockAlert = config['auto_low_stock_alert'] ?? true;
          _loadingSettings = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSettings = false);
    }
  }

  Future<void> _saveFcmSettings() async {
    setState(() => _savingSettings = true);
    try {
      await AdminFirestoreService.instance.saveFcmConfig({
        'fcm_enabled': _fcmEnabled,
        'push_notifications_enabled': _pushNotificationsEnabled,
        'in_app_banner_enabled': _inAppBannerEnabled,
        'channel_name': _channelNameCtrl.text.trim(),
        'default_topic': _defaultTopicCtrl.text.trim(),
        'high_priority': _highPriority,
        'sound_enabled': _soundEnabled,
        'vibration_enabled': _vibrateEnabled,
        'mirror_in_app_banner': _mirrorInAppBanner,
        'auto_closing_reminder': _autoClosingReminder,
        'auto_inactive_nudge': _autoInactiveNudge,
        'auto_low_stock_alert': _autoLowStockAlert,
      });

      // Save Gemini key to global_config
      final currentGlobal = await AdminFirestoreService.instance.getGlobalConfig() ?? {};
      currentGlobal['gemini_api_key'] = _geminiKeyCtrl.text.trim();
      await AdminFirestoreService.instance.setGlobalConfig(currentGlobal);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ FCM Settings, Master Switches & AI Key saved successfully!'),
            backgroundColor: AdminColors.accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save settings: $e'), backgroundColor: AdminColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  Future<void> _sendTestPing() async {
    setState(() => _sendingTestPing = true);
    try {
      final notif = AdminPushNotification(
        id: '',
        title: '🔔 KamaiPlus FCM Live Test Alert',
        body: 'Admin Panel se push notification test bilkul safal raha! Sound, vibration & status bar drop working perfectly.',
        targetAudience: 'all',
        actionRoute: 'home',
        sentAt: DateTime.now(),
      );
      await AdminFirestoreService.instance.sendPushNotification(
        notif,
        sendPhoneAlert: true,
        // A connectivity test must never leave a standing banner in every
        // merchant's app.
        showInAppBanner: false,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test alert sent to all phones. Check your notification tray.'),
            backgroundColor: AdminColors.accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test ping failed: $e'), backgroundColor: AdminColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingTestPing = false);
    }
  }

  void _applyTemplate(String title, String body, String route, String audience) {
    _titleCtrl.text = title;
    _bodyCtrl.text = body;
    _actionRoute = route;
    _targetAudience = audience;
    setState(() => _activeTab = 0);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loaded template: "$title"'),
        backgroundColor: AdminColors.accent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _urlCtrl.dispose();
    _channelNameCtrl.dispose();
    _defaultTopicCtrl.dispose();
    _geminiKeyCtrl.dispose();
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
        backgroundColor: AdminColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AdminColors.borderDark)),
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
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.textWhite),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminColors.bgSidebar,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AdminColors.borderDark),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AdminColors.textWhite)),
                  const SizedBox(height: 4),
                  Text(body, style: const TextStyle(color: AdminColors.textMuted, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This will immediately trigger the Cloud Function and drop an FCM status bar alert on all targeted merchant phones.',
              style: TextStyle(color: AdminColors.inkMuted, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: AdminColors.textMuted))),
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

      await AdminFirestoreService.instance.sendPushNotification(
        notif,
        sendPhoneAlert: _sendPhoneAlert,
        showInAppBanner: _showInAppBanner,
      );

      _titleCtrl.clear();
      _bodyCtrl.clear();
      _urlCtrl.clear();

      if (mounted) {
        final sentVia = [
          if (_sendPhoneAlert) 'phone notification',
          if (_showInAppBanner) 'in-app banner',
        ].join(' + ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sent as $sentVia.'),
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
          padding: EdgeInsets.all(MediaQuery.of(context).size.width < 600 ? 14 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header & Quick Action Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
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
                          Text('Push Notifications & FCM Manager', style: AdminTheme.heading(22)),
                          const SizedBox(height: 2),
                          const Text(
                            'Broadcast alerts, manage FCM settings, and automate retention triggers.',
                            style: TextStyle(color: AdminColors.inkMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (isWide)
                    OutlinedButton.icon(
                      onPressed: _sendingTestPing ? null : _sendTestPing,
                      icon: _sendingTestPing
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AdminColors.accent))
                          : const Icon(Icons.bolt_rounded, size: 18, color: AdminColors.accent),
                      label: const Text('Send Instant FCM Ping Test', style: TextStyle(color: AdminColors.accent, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AdminColors.accent),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),

              // Segmented Tabs Switcher
              // Three pills in a fixed Row overflowed the screen on a phone,
              // which is most of what made this page feel broken on mobile.
              // Horizontal scroll keeps every tab reachable at any width.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AdminColors.bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AdminColors.borderDark),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTabPill(0, 'Send', Icons.send_rounded),
                      const SizedBox(width: 4),
                      _buildTabPill(1, 'Settings', Icons.settings_suggest_rounded),
                      const SizedBox(width: 4),
                      _buildTabPill(2, 'History', Icons.history_rounded),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Main Tab Content
              if (_activeTab == 0) ...[
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
                _buildHistorySection(),
              ] else if (_activeTab == 1) ...[
                _buildSettingsSection(),
              ] else ...[
                _buildHistorySection(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabPill(int index, String label, IconData icon) {
    final active = _activeTab == index;
    return InkWell(
      onTap: () => setState(() => _activeTab = index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AdminColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: active ? Colors.white : AdminColors.textMuted),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : AdminColors.textMuted,
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // FCM & Engine Settings Tab
  // =========================================================================
  Widget _buildSettingsSection() {
    if (_loadingSettings) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final isWide = MediaQuery.of(context).size.width >= 960;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Health & Diagnostic Banner
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AdminColors.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AdminColors.accent.withValues(alpha: 0.3), width: 1.2),
            boxShadow: [
              BoxShadow(color: AdminColors.accent.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AdminColors.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_done_rounded, color: AdminColors.accent, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Cloud Function FCM Engine: ',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AdminColors.textWhite),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AdminColors.accent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AdminColors.accent),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.circle, color: AdminColors.accent, size: 8),
                              SizedBox(width: 6),
                              Text('LIVE & OPERATIONAL', style: TextStyle(color: AdminColors.accent, fontWeight: FontWeight.bold, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Trigger: onAdminPushCreated (us-central1, Cloud Functions v2) listening to Firestore admin_push_notifications',
                      style: TextStyle(color: AdminColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _sendingTestPing ? null : _sendTestPing,
                icon: _sendingTestPing
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.bolt_rounded, size: 18),
                label: const Text('1-Tap Test Ping'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildDeliverySettingsCard()),
              const SizedBox(width: 24),
              Expanded(flex: 2, child: _buildTemplateQuickLibrary()),
            ],
          )
        else
          Column(
            children: [
              _buildDeliverySettingsCard(),
              const SizedBox(height: 20),
              _buildTemplateQuickLibrary(),
            ],
          ),
      ],
    );
  }

  Widget _buildDeliverySettingsCard() {
    return Container(
      padding: EdgeInsets.all(MediaQuery.of(context).size.width < 600 ? 14 : 24),
      decoration: BoxDecoration(
        color: AdminColors.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminColors.borderDark, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, color: AdminColors.accent, size: 20),
              const SizedBox(width: 10),
              Text('FCM Delivery & Channel Preferences', style: AdminTheme.heading(16)),
            ],
          ),
          const SizedBox(height: 20),

          // Master Switches Block
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminColors.bgSidebar,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminColors.accent.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.power_settings_new_rounded, color: AdminColors.accent, size: 18),
                    SizedBox(width: 8),
                    Text('System Master On / Off Controls', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.textWhite)),
                  ],
                ),
                const SizedBox(height: 12),
                _buildToggleRow(
                  title: 'Master FCM Notification Engine',
                  subtitle: 'Globally enable or disable all background FCM push broadcasts to devices.',
                  value: _fcmEnabled,
                  icon: Icons.cell_tower_rounded,
                  onChanged: (v) => setState(() => _fcmEnabled = v),
                ),
                _buildToggleRow(
                  title: 'Mobile Status Bar Push Alerts',
                  subtitle: 'Show heads-up status bar and notification tray alerts on cashier phones.',
                  value: _pushNotificationsEnabled,
                  icon: Icons.notifications_active_rounded,
                  onChanged: (v) => setState(() => _pushNotificationsEnabled = v),
                ),
                _buildToggleRow(
                  title: 'In-App Announcement Banners',
                  subtitle: 'Show real-time floating broadcast banners inside the POS dashboard.',
                  value: _inAppBannerEnabled,
                  icon: Icons.campaign_rounded,
                  onChanged: (v) => setState(() => _inAppBannerEnabled = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Google AI Studio / Gemini Vision OCR Key
          const Text('Google AI Studio / Gemini Vision OCR API Key', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AdminColors.textWhite)),
          const SizedBox(height: 4),
          const Text('Used automatically by all retail merchants for Mandi Parcha & Restaurant Menu photo OCR. Users are never asked for their own key.', style: TextStyle(color: AdminColors.textMuted, fontSize: 11.5)),
          const SizedBox(height: 8),
          TextField(
            controller: _geminiKeyCtrl,
            obscureText: true,
            style: const TextStyle(color: AdminColors.textWhite, fontSize: 13, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: 'Enter AIzaSy... Google AI Studio key',
              hintStyle: const TextStyle(color: AdminColors.inkMuted, fontSize: 12),
              fillColor: AdminColors.bgSidebar,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AdminColors.borderDark)),
              prefixIcon: const Icon(Icons.key_rounded, color: AdminColors.accent, size: 18),
            ),
          ),
          const SizedBox(height: 20),

          // Channel Name
          const Text('Android Notification Channel Name', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AdminColors.textWhite)),
          const SizedBox(height: 6),
          TextField(
            controller: _channelNameCtrl,
            style: const TextStyle(color: AdminColors.textWhite, fontSize: 14),
            decoration: InputDecoration(
              fillColor: AdminColors.bgSidebar,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AdminColors.borderDark)),
            ),
          ),
          const SizedBox(height: 16),

          // Default Target Topic
          const Text('Default Broadcast Topic (FCM)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AdminColors.textWhite)),
          const SizedBox(height: 6),
          TextField(
            controller: _defaultTopicCtrl,
            style: const TextStyle(color: AdminColors.textWhite, fontSize: 14),
            decoration: InputDecoration(
              fillColor: AdminColors.bgSidebar,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AdminColors.borderDark)),
            ),
          ),
          const SizedBox(height: 20),

          const Divider(color: AdminColors.borderDark),
          const SizedBox(height: 12),
          const Text('Delivery Behavior & Flags', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AdminColors.accent)),
          const SizedBox(height: 8),

          _buildToggleRow(
            title: 'High Priority (Drop-down / Heads-up Banner)',
            subtitle: 'Forces device system tray to drop down alert over active screen with vibration and ringtone.',
            value: _highPriority,
            icon: Icons.priority_high_rounded,
            onChanged: (v) => setState(() => _highPriority = v),
          ),
          _buildToggleRow(
            title: 'Alert Sound on Arrival',
            subtitle: 'Plays default Android POS chime when notification arrives on merchant phone.',
            value: _soundEnabled,
            icon: Icons.volume_up_rounded,
            onChanged: (v) => setState(() => _soundEnabled = v),
          ),
          _buildToggleRow(
            title: 'Haptic Vibration on Arrival',
            subtitle: 'Vibrates device when alert drops down.',
            value: _vibrateEnabled,
            icon: Icons.vibration_rounded,
            onChanged: (v) => setState(() => _vibrateEnabled = v),
          ),
          _buildToggleRow(
            title: 'Dual-Sync to In-App Announcement Banner',
            subtitle: 'Also displays announcement banner inside mobile POS billing screen in realtime.',
            value: _mirrorInAppBanner,
            icon: Icons.view_carousel_rounded,
            onChanged: (v) => setState(() => _mirrorInAppBanner = v),
          ),

          const SizedBox(height: 20),
          const Divider(color: AdminColors.borderDark),
          const SizedBox(height: 12),
          const Text('Automated Merchant Engagement Rules', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AdminColors.accent)),
          const SizedBox(height: 8),

          _buildToggleRow(
            title: 'Daily 9:00 PM Counter Closing Reminder',
            subtitle: 'Automated nudge reminding merchants to tally cash register & print daily sales ledger.',
            value: _autoClosingReminder,
            icon: Icons.nights_stay_rounded,
            onChanged: (v) => setState(() => _autoClosingReminder = v),
          ),
          _buildToggleRow(
            title: '7-Day Inactive Store Retention Nudge',
            subtitle: 'Automated friendly ping to stores with 0 sales for 7 consecutive days.',
            value: _autoInactiveNudge,
            icon: Icons.radar_rounded,
            onChanged: (v) => setState(() => _autoInactiveNudge = v),
          ),
          _buildToggleRow(
            title: 'Low Stock Radar Push Alert',
            subtitle: 'Notifies store owner when fast-selling catalog products reach zero inventory.',
            value: _autoLowStockAlert,
            icon: Icons.inventory_2_rounded,
            onChanged: (v) => setState(() => _autoLowStockAlert = v),
          ),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _savingSettings ? null : _saveFcmSettings,
              icon: _savingSettings
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: const Text('Save FCM Preferences & Automation Policies', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateQuickLibrary() {
    final templates = [
      {
        'title': '⚡ Weekend Kirana Rush: Stock Tayyar Hai?',
        'body': 'Weekend par grahako ki bheed ke liye inventory check karein aur barcode scan se 5 second me bill banayein!',
        'route': 'billing',
        'audience': 'all',
        'icon': '🛒',
      },
      {
        'title': '🚀 KamaiPlus Naya Update: Version 4.21 Live!',
        'body': 'Play Store par naya version update karein. Fast barcode inwarding aur naye tax invoice features unlock karein.',
        'route': 'home',
        'audience': 'all',
        'icon': '⚡',
      },
      {
        'title': '💰 Aaj Ka Udhar & Khata Tally Karein',
        'body': 'Counter band karne se pehle pending khata customers ko 1-tap WhatsApp reminder bhejein aur payment collect karein.',
        'route': 'home',
        'audience': 'all',
        'icon': '📖',
      },
      {
        'title': '🌙 Counter Closing Time: Daily Cash Tally',
        'body': 'Aaj ki counter shift close karein aur apna daily profit-loss summary print karein.',
        'route': 'billing',
        'audience': 'all',
        'icon': '🌙',
      },
    ];

    return Container(
      padding: EdgeInsets.all(MediaQuery.of(context).size.width < 600 ? 14 : 24),
      decoration: BoxDecoration(
        color: AdminColors.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminColors.borderDark, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.collections_bookmark_rounded, color: AdminColors.accent, size: 20),
              SizedBox(width: 10),
              Text('Fast Campaign Templates', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AdminColors.textWhite)),
            ],
          ),
          const SizedBox(height: 6),
          const Text('1-tap pre-written high-conversion retail push alerts.', style: TextStyle(color: AdminColors.textMuted, fontSize: 12)),
          const SizedBox(height: 16),

          for (final t in templates)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AdminColors.bgSidebar,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AdminColors.borderDark),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(t['icon']!, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t['title']!,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.textWhite),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(t['body']!, style: const TextStyle(color: AdminColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _applyTemplate(t['title']!, t['body']!, t['route']!, t['audience']!),
                      icon: const Icon(Icons.bolt_rounded, size: 15, color: AdminColors.accent),
                      label: const Text('Use Template', style: TextStyle(fontSize: 12, color: AdminColors.accent, fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AdminColors.bgElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AdminColors.borderDark),
              ),
              child: Icon(icon, size: 18, color: AdminColors.accent),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AdminColors.textWhite, fontWeight: FontWeight.w600, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: AdminColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AdminColors.accent,
            activeTrackColor: AdminColors.accent.withValues(alpha: 0.4),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // Campaign Composer & Preview
  // =========================================================================

  /// Where the message goes. Two channels, named for what the merchant sees.
  ///
  /// Both used to fire on every send with no way to choose, so one "Send"
  /// arrived as three notifications: an FCM tray alert, a second tray alert
  /// raised by the app's broadcast listener, and the in-app banner. Naming the
  /// channels after the merchant's experience — "phone notification" vs "banner
  /// inside the app" — is what makes the difference obvious without knowing
  /// what FCM is.
  Widget _buildChannelPicker() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminColors.bgSidebar,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Where should this go?',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AdminColors.textWhite),
          ),
          const SizedBox(height: 10),
          _buildChannelTile(
            value: _sendPhoneAlert,
            onChanged: (v) => setState(() => _sendPhoneAlert = v),
            icon: Icons.notifications_active_rounded,
            title: 'Phone notification',
            subtitle: 'Appears in the notification tray, even when the app is closed.',
          ),
          const SizedBox(height: 8),
          _buildChannelTile(
            value: _showInAppBanner,
            onChanged: (v) => setState(() => _showInAppBanner = v),
            icon: Icons.campaign_rounded,
            title: 'Banner inside the app',
            subtitle: 'A coloured strip on the Home screen. Stays until you turn it off.',
          ),
          if (!_sendPhoneAlert && !_showInAppBanner) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.error_outline_rounded, size: 15, color: AdminColors.red),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Pick at least one — nothing will be sent.',
                    style: TextStyle(fontSize: 11.5, color: AdminColors.red, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChannelTile({
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: value ? AdminColors.accent.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: value ? AdminColors.accent.withValues(alpha: 0.55) : AdminColors.borderDark,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: AdminColors.accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Icon(icon, size: 17, color: value ? AdminColors.accent : AdminColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: value ? AdminColors.textWhite : AdminColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, height: 1.35, color: AdminColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposerCard() {
    return Container(
      padding: EdgeInsets.all(MediaQuery.of(context).size.width < 600 ? 14 : 24),
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
              hintText: 'e.g. ⚡ Special Update: Fast Barcode Inwarding is Live!',
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

          _buildChannelPicker(),
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
            onChanged: (v) {
              if (v != null) setState(() => _actionRoute = v);
            },
          ),
          if (_actionRoute == 'external') ...[
            const SizedBox(height: 14),
            TextField(
              controller: _urlCtrl,
              style: const TextStyle(color: AdminColors.textWhite, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'https://example.com/festive-offer',
                prefixIcon: const Icon(Icons.link_rounded, color: AdminColors.accent),
                fillColor: AdminColors.bgSidebar,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AdminColors.borderDark)),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Send Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _handleSend,
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(_sending ? 'Broadcasting...' : 'Dispatch Push Campaign', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudienceChip(String id, String label, IconData icon) {
    final isSelected = _targetAudience == id;
    return ChoiceChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: isSelected ? Colors.white : AdminColors.textMuted),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: isSelected ? Colors.white : AdminColors.textWhite, fontSize: 13)),
        ],
      ),
      selectedColor: AdminColors.accent,
      backgroundColor: AdminColors.bgElevated,
      side: BorderSide(color: isSelected ? AdminColors.accent : AdminColors.borderDark),
      onSelected: (_) => setState(() => _targetAudience = id),
    );
  }

  // =========================================================================
  // Realistic Android Phone Mockup (Top Shade Notification Dropdown)
  // =========================================================================
  Widget _buildLivePreviewCard() {
    final title = _titleCtrl.text.trim().isEmpty ? 'KamaiPlus POS Alert' : _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim().isEmpty ? 'Your alert message will appear here on merchant phones in realtime.' : _bodyCtrl.text.trim();

    return Center(
      child: Container(
        width: 320,
        height: 560,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: const Color(0xFF334155), width: 3.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
            BoxShadow(
              color: AdminColors.accent.withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: Stack(
            children: [
              // Phone Screen Wallpaper Background
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF020617), Color(0xFF0F172A), Color(0xFF1E293B)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),

              // Camera Punch Hole / Speaker Notch
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    width: 70,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),

              // Phone UI Content
              Column(
                children: [
                  // Android Status Bar
                  Padding(
                    padding: const EdgeInsets.only(left: 24, right: 24, top: 12, bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat('hh:mm').format(DateTime.now()),
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        const Row(
                          children: [
                            Icon(Icons.wifi, size: 12, color: Colors.white),
                            SizedBox(width: 4),
                            Icon(Icons.signal_cellular_4_bar, size: 12, color: Colors.white),
                            SizedBox(width: 4),
                            Icon(Icons.battery_full, size: 12, color: Colors.white),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Pulled Down System Notification Card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B).withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // App Branding Header in Notification
                          Row(
                            children: [
                              Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: AdminColors.accent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Center(
                                  child: Icon(Icons.point_of_sale_rounded, size: 12, color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'KAMAI+ POS',
                                style: GoogleFonts.inter(
                                  color: AdminColors.accent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'now',
                                style: GoogleFonts.inter(color: Colors.white54, fontSize: 10),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Notification Title
                          Text(
                            title,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),

                          // Notification Body
                          Text(
                            body,
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12,
                              height: 1.3,
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),

                          const SizedBox(height: 10),

                          // Action pill indicator
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.touch_app_rounded, size: 11, color: AdminColors.accent),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Opens ${_actionRoute.replaceAll('_', ' ').toUpperCase()}',
                                      style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.notifications_active_rounded, size: 14, color: AdminColors.accent),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Bottom Android Navigation Bar Pill
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      width: 100,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistorySection() {
    return Container(
      padding: EdgeInsets.all(MediaQuery.of(context).size.width < 600 ? 14 : 24),
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
