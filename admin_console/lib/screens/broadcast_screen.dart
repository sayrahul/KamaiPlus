import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  bool _broadcastActive = false;
  DateTime? _broadcastUpdatedAt;
  bool _publishing = false;
  bool _clearing = false;

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
    for (final row in _configRows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    final broadcastFuture = AdminFirestoreService.instance.getBroadcast();
    final configFuture = AdminFirestoreService.instance.getGlobalConfig();
    final broadcast = await broadcastFuture;
    final config = await configFuture;
    if (!mounted) return;

    for (final row in _configRows) {
      row.dispose();
    }
    _configRows.clear();
    _configUpdatedAt = null;

    setState(() {
      _messageController.text = _asDisplayString(broadcast?['message']);
      _broadcastActive = broadcast?['active'] == true;
      _actionUrlController.text = _asDisplayString(broadcast?['action_url']);
      _broadcastUpdatedAt = _asDate(broadcast?['updated_at']);

      if (config != null) {
        for (final entry in config.entries) {
          if (entry.key == 'updated_at') {
            _configUpdatedAt = _asDate(entry.value);
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
        content: SizedBox(width: 420, child: content),
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
                          Text('Broadcast & Config', style: AdminTheme.heading(24)),
                          const SizedBox(height: 4),
                          const Text(
                            'Both sections write live data read by every merchant\'s app right away.',
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
                Text('Broadcast Message', style: AdminTheme.heading(16)),
                const Spacer(),
                _statusBadge(active: _broadcastActive),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _broadcastUpdatedAt != null ? 'Last published ${_dateFmt.format(_broadcastUpdatedAt!)}' : 'Never published yet',
              style: const TextStyle(color: AdminColors.inkFaint, fontSize: 12),
            ),
            const SizedBox(height: 18),
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
                  label: const Text('Publish'),
                ),
                OutlinedButton.icon(
                  onPressed: _publishing || _clearing ? null : _handleClear,
                  icon: _clearing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.clear_rounded, size: 17),
                  label: const Text('Clear Broadcast'),
                ),
              ],
            ),
          ],
        ),
      ),
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
