import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/admin_models.dart';
import '../services/admin_firestore_service.dart';
import '../theme/admin_theme.dart';

/// One editable key/value row in the Global Config editor. Each row owns its
/// own controllers so text survives rebuilds; [id] is a stable identity
/// (not the list index, which shifts on add/remove) used as a widget Key.
class _ConfigRow {
  final int id;
  final TextEditingController keyController;
  final TextEditingController valueController;

  _ConfigRow({required this.id, String key = '', String value = ''})
      : keyController = TextEditingController(text: key),
        valueController = TextEditingController(text: value);

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

String _asDisplayString(dynamic v) {
  if (v == null) return '';
  return v.toString();
}

/// Defensive timestamp parse: the `updated_at` field is written as a
/// Firestore `Timestamp` (exposes `.toDate()`) by this console, but might
/// also come back as an ISO string, a plain [DateTime], or be entirely
/// absent — never crash the screen over a metadata field.
DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  try {
    return (v as dynamic).toDate() as DateTime;
  } catch (_) {
    return null;
  }
}

final DateFormat _dateFmt = DateFormat('d MMM yyyy, h:mm a');

/// Publishes the live in-app broadcast banner and the app-wide
/// `global_config` remote-config doc. Both are read live by every
/// signed-in merchant's phone the moment they're written — every write
/// path here is gated behind an explicit confirmation dialog.
class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  late Future<void> _loadFuture;

  // Broadcast message state
  final _messageController = TextEditingController();
  final _actionUrlController = TextEditingController();
  String _broadcastType = 'info';
  bool _broadcastActive = false;
  DateTime? _broadcastUpdatedAt;
  bool _publishing = false;
  bool _clearing = false;

  // App Version Control state
  final _minVersionCodeController = TextEditingController(text: '42201');
  final _latestVersionNameController = TextEditingController(text: '4.21.0');
  final _latestVersionCodeController = TextEditingController(text: '42201');
  final _maintenanceMessageController = TextEditingController(
    text: 'KamaiPlus is undergoing scheduled server upgrades. We will be back online shortly.',
  );
  final _playStoreUrlController = TextEditingController(
    text: 'https://play.google.com/store/apps/details?id=com.kamaiplus.pos',
  );
  bool _forceUpdate = false;
  bool _maintenanceMode = false;
  DateTime? _versionUpdatedAt;
  bool _savingVersion = false;

  // Global config state
  final List<_ConfigRow> _configRows = [];
  int _rowIdCounter = 0;
  DateTime? _configUpdatedAt;
  bool _savingConfig = false;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadAll();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _actionUrlController.dispose();
    _minVersionCodeController.dispose();
    _latestVersionNameController.dispose();
    _latestVersionCodeController.dispose();
    _maintenanceMessageController.dispose();
    _playStoreUrlController.dispose();
    for (final row in _configRows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    final broadcastFuture = AdminFirestoreService.instance.getBroadcast();
    final configFuture = AdminFirestoreService.instance.getGlobalConfig();
    final versionFuture = AdminFirestoreService.instance.getAppVersionControl();

    final broadcast = await broadcastFuture;
    final config = await configFuture;
    final version = await versionFuture;

    if (!mounted) return;

    for (final row in _configRows) {
      row.dispose();
    }
    _configRows.clear();
    _configUpdatedAt = null;

    setState(() {
      _messageController.text = _asDisplayString(broadcast?['message']);
      _broadcastActive = broadcast?['active'] == true || broadcast?['enabled'] == true;
      _broadcastType = _asDisplayString(broadcast?['type']).isNotEmpty ? broadcast!['type'] : 'info';
      _actionUrlController.text = _asDisplayString(broadcast?['action_url']);
      _broadcastUpdatedAt = _asDate(broadcast?['updated_at']);

      // Version control
      _minVersionCodeController.text = version.minVersionCode.toString();
      _latestVersionNameController.text = version.latestVersionName;
      _latestVersionCodeController.text = version.latestVersionCode.toString();
      _forceUpdate = version.forceUpdate;
      _maintenanceMode = version.maintenanceMode;
      _maintenanceMessageController.text = version.maintenanceMessage;
      _playStoreUrlController.text = version.playStoreUrl;
      _versionUpdatedAt = version.updatedAt;

      if (config != null) {
        for (final entry in config.entries) {
          if (entry.key == 'updated_at') {
            _configUpdatedAt = _asDate(entry.value);
            continue;
          }
          // Filter out version keys from generic list to keep it tidy
          if (['min_version_code', 'latest_version_name', 'latest_version_code', 'force_update', 'maintenance_mode', 'maintenance_message', 'play_store_url'].contains(entry.key)) {
            continue;
          }
          _configRows.add(_ConfigRow(id: _rowIdCounter++, key: entry.key, value: _asDisplayString(entry.value)));
        }
      }
    });
  }

  void _reload() {
    setState(() {
      _loadFuture = _loadAll();
    });
  }

  // -------------------------------------------------------------------
  // Broadcast actions
  // -------------------------------------------------------------------

  Future<void> _handlePublish() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a message before publishing.')),
      );
      return;
    }
    final actionUrl = _actionUrlController.text.trim();

    final confirmed = await _confirmDialog(
      icon: Icons.campaign_rounded,
      iconColor: AdminColors.amber,
      title: 'Publish broadcast to all merchants?',
      confirmLabel: 'Publish now',
      confirmColor: AdminColors.amber,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This will appear as an in-app banner on every signed-in merchant\'s phone, immediately.',
            style: TextStyle(color: AdminColors.inkMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AdminColors.surfaceSunken,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AdminColors.border),
            ),
            child: Text(message, style: const TextStyle(color: AdminColors.ink, fontSize: 14, height: 1.4)),
          ),
          const SizedBox(height: 10),
          _statusLine('Status', _broadcastActive ? 'Active' : 'Inactive (saved but hidden)'),
          if (actionUrl.isNotEmpty) _statusLine('Action URL', actionUrl),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _publishing = true);
    try {
      await AdminFirestoreService.instance.setBroadcast(
        message: message,
        active: _broadcastActive,
        actionUrl: actionUrl.isEmpty ? null : actionUrl,
        type: _broadcastType,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Broadcast published.')));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to publish: $e')));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _handleSaveVersionControl() async {
    final minCode = int.tryParse(_minVersionCodeController.text.trim()) ?? 42201;
    final latestCode = int.tryParse(_latestVersionCodeController.text.trim()) ?? 42201;
    final latestName = _latestVersionNameController.text.trim();
    final maintMsg = _maintenanceMessageController.text.trim();
    final playUrl = _playStoreUrlController.text.trim();

    final confirmed = await _confirmDialog(
      icon: Icons.system_security_update_rounded,
      iconColor: AdminColors.accent,
      title: 'Update App Release & Version Policy?',
      confirmLabel: 'Apply Release Policy',
      confirmColor: AdminColors.accent,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This update will be pushed instantly to all merchant devices. If Force Update is enabled, users on older app builds will be blocked until updated via Google Play.',
            style: TextStyle(color: AdminColors.inkMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          _statusLine('Minimum Required Code', '$minCode'),
          _statusLine('Latest App Version', '$latestName ($latestCode)'),
          _statusLine('Force Update Required', _forceUpdate ? '🔴 YES (Non-dismissible)' : '⚪ Optional update'),
          _statusLine('Maintenance Mode', _maintenanceMode ? '🚨 ACTIVE (Downtime warning)' : '🟢 Normal operation'),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _savingVersion = true);
    try {
      final config = AdminAppVersionConfig(
        minVersionCode: minCode,
        latestVersionName: latestName.isEmpty ? '4.21.0' : latestName,
        latestVersionCode: latestCode,
        forceUpdate: _forceUpdate,
        maintenanceMode: _maintenanceMode,
        maintenanceMessage: maintMsg.isEmpty ? 'KamaiPlus is undergoing scheduled upgrades.' : maintMsg,
        playStoreUrl: playUrl.isEmpty ? 'https://play.google.com/store/apps/details?id=com.kamaiplus.pos' : playUrl,
      );
      await AdminFirestoreService.instance.setAppVersionControl(config);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App Version & Release Policy updated successfully!')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update version policy: $e')));
    } finally {
      if (mounted) setState(() => _savingVersion = false);
    }
  }

  Future<void> _handleClear() async {
    final confirmed = await _confirmDialog(
      icon: Icons.campaign_outlined,
      iconColor: AdminColors.inkMuted,
      title: 'Clear the broadcast?',
      confirmLabel: 'Clear broadcast',
      confirmColor: AdminColors.ink,
      content: const Text(
        'Sets the broadcast to inactive so merchants stop seeing the banner. The saved message text is kept, so you can re-publish it later.',
        style: TextStyle(color: AdminColors.inkMuted, fontSize: 13, height: 1.4),
      ),
    );
    if (confirmed != true) return;

    setState(() => _clearing = true);
    try {
      await AdminFirestoreService.instance.clearBroadcast();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Broadcast cleared.')));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to clear: $e')));
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  // -------------------------------------------------------------------
  // Global config actions
  // -------------------------------------------------------------------

  void _addConfigRow() {
    setState(() => _configRows.add(_ConfigRow(id: _rowIdCounter++)));
  }

  void _removeConfigRow(_ConfigRow row) {
    setState(() {
      row.dispose();
      _configRows.remove(row);
    });
  }

  Map<String, dynamic> _buildConfigData() {
    final entries = _configRows
        .map((r) => MapEntry(r.keyController.text.trim(), r.valueController.text.trim()))
        .where((e) => e.key.isNotEmpty);
    return Map<String, dynamic>.fromEntries(entries);
  }

  Future<void> _handleSaveConfig() async {
    final data = _buildConfigData();

    final confirmed = await _confirmDialog(
      icon: Icons.tune_rounded,
      iconColor: AdminColors.violet,
      title: 'Save global config for all merchants?',
      confirmLabel: 'Save config',
      confirmColor: AdminColors.violet,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This replaces the live config every merchant\'s app reads, immediately. Any key not listed below will no longer be set.',
            style: TextStyle(color: AdminColors.inkMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          if (data.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminColors.surfaceSunken,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AdminColors.border),
              ),
              child: const Text('No keys — this will save an empty config.', style: TextStyle(color: AdminColors.inkMuted, fontSize: 13)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: Container(
                decoration: BoxDecoration(
                  color: AdminColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AdminColors.border),
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: [
                    for (final e in data.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: RichText(
                          text: TextSpan(
                            style: AdminTheme.mono(12.5),
                            children: [
                              TextSpan(text: e.key, style: const TextStyle(color: AdminColors.ink)),
                              const TextSpan(text: '  =  ', style: TextStyle(color: AdminColors.inkFaint)),
                              TextSpan(text: e.value.toString(), style: const TextStyle(color: AdminColors.accent)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _savingConfig = true);
    try {
      await AdminFirestoreService.instance.setGlobalConfig(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Global config saved.')));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save config: $e')));
    } finally {
      if (mounted) setState(() => _savingConfig = false);
    }
  }

  // -------------------------------------------------------------------
  // Shared confirm dialog
  // -------------------------------------------------------------------

  Future<bool?> _confirmDialog({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget content,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: AdminTheme.heading(16))),
          ],
        ),
        // Clamped, not fixed: a 420px dialog on a 360px phone overflows and
        // clips its own buttons.
        content: SizedBox(
          width: MediaQuery.of(ctx).size.width < 460
              ? MediaQuery.of(ctx).size.width - 80
              : 420,
          child: content,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor, foregroundColor: Colors.white),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Widget _statusLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12.5, color: AdminColors.inkMuted),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(text: value, style: const TextStyle(color: AdminColors.ink, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _centerNote(
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading current broadcast & config…', style: TextStyle(color: AdminColors.inkMuted, fontSize: 13)),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return _centerNote(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: AdminColors.red, size: 32),
                const SizedBox(height: 12),
                Text('Couldn\'t load platform settings.\n${snapshot.error}', textAlign: TextAlign.center, style: const TextStyle(color: AdminColors.inkMuted, fontSize: 13)),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _reload, child: const Text('Retry')),
              ],
            ),
          );
        }
        return _buildForm();
      },
    );
  }

  Widget _centerNote({required Widget child}) {
    return Container(
      color: AdminColors.surfaceSunken,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: child,
    );
  }

  Widget _buildForm() {
    return Container(
      color: AdminColors.surfaceSunken,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Release & Platform Control', style: AdminTheme.heading(24)),
                          const SizedBox(height: 4),
                          const Text(
                            'Control app versioning, mandatory Google Play updates, and in-app broadcasts live.',
                            style: TextStyle(color: AdminColors.inkMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Reload from Firestore',
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded, color: AdminColors.inkMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildVersionControlCard(),
                const SizedBox(height: 24),
                _buildBroadcastCard(),
                const SizedBox(height: 24),
                _buildConfigCard(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVersionControlCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AdminColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AdminColors.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.system_security_update_rounded, color: AdminColors.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Force Update & App Version Controller', style: AdminTheme.heading(16)),
                      const SizedBox(height: 2),
                      Text(
                        _versionUpdatedAt != null ? 'Last applied ${_dateFmt.format(_versionUpdatedAt!)}' : 'Using default release settings',
                        style: const TextStyle(color: AdminColors.inkFaint, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _forceUpdate ? AdminColors.redSoft : AdminColors.accentSoft,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _forceUpdate ? AdminColors.redBorder : AdminColors.accentBorder),
                  ),
                  child: Text(
                    _forceUpdate ? 'FORCE UPDATE: ON' : 'PLAY STORE LIVE',
                    style: TextStyle(
                      color: _forceUpdate ? AdminColors.red : AdminColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Control mandatory app upgrades. If an installed merchant device has a version code lower than "Min Version Code", they will be prompted or strictly blocked until they update from Google Play.',
              style: TextStyle(color: AdminColors.inkMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chipInfo('Target SDK', '36 (Android 16+ Ready)', AdminColors.accent),
                _chipInfo('Installed Release', 'v4.21.0 (42201)', AdminColors.ink),
              ],
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 600;
                if (isNarrow) {
                  return Column(
                    children: [
                      TextField(
                        controller: _minVersionCodeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Min Version Code (Blocker Threshold)',
                          hintText: 'e.g. 42201',
                          helperText: 'App codes lower than this will be prompted to update',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _latestVersionNameController,
                        decoration: const InputDecoration(
                          labelText: 'Latest Version Name',
                          hintText: 'e.g. 4.21.0',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _latestVersionCodeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Latest Version Code',
                          hintText: 'e.g. 42201',
                        ),
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _minVersionCodeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Min Version Code',
                          hintText: '42201',
                          helperText: 'Older than this triggers update',
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _latestVersionNameController,
                        decoration: const InputDecoration(
                          labelText: 'Latest Version Name',
                          hintText: '4.21.0',
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _latestVersionCodeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Latest Version Code',
                          hintText: '42201',
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: AdminColors.surfaceSunken,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AdminColors.border),
              ),
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    value: _forceUpdate,
                    onChanged: (v) => setState(() => _forceUpdate = v),
                    activeThumbColor: AdminColors.red,
                    title: const Row(
                      children: [
                        Icon(Icons.lock_clock_rounded, size: 18, color: AdminColors.red),
                        SizedBox(width: 8),
                        Text('Force Immediate Update (Non-Dismissible)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AdminColors.ink)),
                      ],
                    ),
                    subtitle: const Text(
                      'When ON, merchants cannot dismiss the update popup. App access is completely blocked until they update.',
                      style: TextStyle(fontSize: 12, color: AdminColors.inkMuted),
                    ),
                  ),
                  const Divider(height: 1, color: AdminColors.border),
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    value: _maintenanceMode,
                    onChanged: (v) => setState(() => _maintenanceMode = v),
                    activeThumbColor: AdminColors.amber,
                    title: const Row(
                      children: [
                        Icon(Icons.construction_rounded, size: 18, color: AdminColors.amber),
                        SizedBox(width: 8),
                        Text('Emergency Server Maintenance Mode', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AdminColors.ink)),
                      ],
                    ),
                    subtitle: const Text(
                      'When ON, an announcement banner will warn merchants about planned database maintenance.',
                      style: TextStyle(fontSize: 12, color: AdminColors.inkMuted),
                    ),
                  ),
                ],
              ),
            ),
            if (_maintenanceMode) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _maintenanceMessageController,
                decoration: const InputDecoration(
                  labelText: 'Maintenance Warning Message',
                  hintText: 'Server upgrades in progress...',
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _playStoreUrlController,
              decoration: const InputDecoration(
                labelText: 'Google Play Store Direct URL',
                hintText: 'https://play.google.com/store/apps/details?id=com.kamaiplus.pos',
                prefixIcon: Icon(Icons.shop_two_rounded, size: 18),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _savingVersion ? null : _handleSaveVersionControl,
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              icon: _savingVersion
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cloud_upload_rounded, size: 18),
              label: const Text('Apply Version & Release Policy', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipInfo(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildBroadcastCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.campaign_rounded, color: AdminColors.amber, size: 20),
                const SizedBox(width: 10),
                Text('In-App Banner (live right now)', style: AdminTheme.heading(16)),
                const Spacer(),
                _statusBadge(active: _broadcastActive),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _broadcastUpdatedAt != null ? 'Last published ${_dateFmt.format(_broadcastUpdatedAt!)}' : 'Never published yet',
              style: const TextStyle(color: AdminColors.inkFaint, fontSize: 12),
            ),
            const SizedBox(height: 8),
            // Says plainly how this relates to the Notifications screen, which
            // can also publish a banner. Two screens writing the same document
            // with no explanation is what made this section feel duplicated.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
              ),
              child: const Text(
                'This is the banner merchants see on their Home screen. It stays up until you turn it '
                'off here. Sending a new one from Notifications replaces it. It is NOT a phone '
                'notification — nothing appears in the notification tray from this section.',
                style: TextStyle(fontSize: 11.5, height: 1.4, color: AdminColors.inkFaint),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Banner Theme / Urgency Level', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AdminColors.ink)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _typeChoiceChip('info', 'ℹ️ Info Blue', Colors.blue),
                _typeChoiceChip('festive', '✨ Festive Rose', Colors.pink),
                _typeChoiceChip('warning', '⚠️ Alert Amber', Colors.amber),
                _typeChoiceChip('success', '✅ Announcement Green', Colors.teal),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Message',
                hintText: 'Shown as an in-app banner to every merchant, e.g. "Scheduled maintenance tonight 11pm–1am."',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _broadcastActive,
              onChanged: (v) => setState(() => _broadcastActive = v),
              activeThumbColor: AdminColors.accent,
              title: const Text('Active', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AdminColors.ink)),
              subtitle: const Text('Off saves the message without showing it to merchants.', style: TextStyle(fontSize: 12, color: AdminColors.inkMuted)),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _actionUrlController,
              decoration: const InputDecoration(
                labelText: 'Action URL (optional)',
                hintText: 'https://…',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: _publishing || _clearing ? null : _handlePublish,
                  style: ElevatedButton.styleFrom(backgroundColor: AdminColors.amber, foregroundColor: Colors.white),
                  icon: _publishing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 17),
                  label: const Text('Publish Banner'),
                ),
                OutlinedButton.icon(
                  onPressed: _publishing || _clearing ? null : _handleClear,
                  icon: _clearing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.clear_rounded, size: 17),
                  label: const Text('Clear Banner'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChoiceChip(String type, String label, Color color) {
    final isSelected = _broadcastType == type;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? Colors.white : AdminColors.ink)),
      selected: isSelected,
      selectedColor: color,
      backgroundColor: AdminColors.surfaceSunken,
      onSelected: (_) => setState(() => _broadcastType = type),
    );
  }

  Widget _statusBadge({required bool active}) {
    final color = active ? AdminColors.accent : AdminColors.inkFaint;
    final bg = active ? AdminColors.accentSoft : AdminColors.surfaceSunken;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: Border.all(color: active ? AdminColors.accentBorder : AdminColors.border)),
      child: Text(active ? 'LIVE' : 'INACTIVE', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
    );
  }

  Widget _buildConfigCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune_rounded, color: AdminColors.violet, size: 20),
                const SizedBox(width: 10),
                Text('Global Config', style: AdminTheme.heading(16)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _configUpdatedAt != null ? 'Last saved ${_dateFmt.format(_configUpdatedAt!)}' : 'Never saved yet',
              style: const TextStyle(color: AdminColors.inkFaint, fontSize: 12),
            ),
            const SizedBox(height: 6),
            const Text(
              'Generic key/value pairs the app reads as app-wide feature toggles / remote config.',
              style: TextStyle(color: AdminColors.inkMuted, fontSize: 12.5),
            ),
            const SizedBox(height: 18),
            if (_configRows.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AdminColors.surfaceSunken, borderRadius: BorderRadius.circular(10), border: Border.all(color: AdminColors.border)),
                child: const Text('No config keys yet — add one below.', style: TextStyle(color: AdminColors.inkMuted, fontSize: 13)),
              )
            else
              Column(children: [for (final row in _configRows) _buildConfigRow(row)]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addConfigRow,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('Add field'),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _savingConfig ? null : _handleSaveConfig,
              style: ElevatedButton.styleFrom(backgroundColor: AdminColors.violet, foregroundColor: Colors.white),
              icon: _savingConfig
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 17),
              label: const Text('Save Config'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigRow(_ConfigRow row) {
    return Padding(
      key: ValueKey(row.id),
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: row.keyController,
              decoration: const InputDecoration(hintText: 'key', isDense: true),
              style: AdminTheme.mono(13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: TextField(
              controller: row.valueController,
              decoration: const InputDecoration(hintText: 'value', isDense: true),
              style: AdminTheme.mono(13),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: () => _removeConfigRow(row),
            icon: const Icon(Icons.close_rounded, size: 18, color: AdminColors.inkFaint),
          ),
        ],
      ),
    );
  }
}
