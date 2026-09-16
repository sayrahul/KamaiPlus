import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/admin_firestore_service.dart';
import '../theme/admin_theme.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _service = AdminFirestoreService.instance;
  final _keyController = TextEditingController();
  
  String _selectedModel = 'gemini-3.6-flash';
  bool _obscureCurrentKey = true;
  bool _testingKey = false;
  bool _savingKey = false;
  Map<String, dynamic>? _testResult;

  final DateFormat _dateFmt = DateFormat('d MMM yyyy, h:mm a');

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  String _maskKey(String key) {
    if (key.length <= 10) return '••••••••••••';
    return '${key.substring(0, 8)}••••••••••••${key.substring(key.length - 4)}';
  }

  Future<void> _handleTestKey([String? customKey]) async {
    final keyToTest = customKey ?? _keyController.text.trim();
    if (keyToTest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an API key to test.'),
          backgroundColor: AdminColors.amber,
        ),
      );
      return;
    }

    setState(() {
      _testingKey = true;
      _testResult = null;
    });

    final res = await _service.testGeminiApiKey(keyToTest, model: _selectedModel);

    if (!mounted) return;
    setState(() {
      _testingKey = false;
      _testResult = res;
    });

    final isSuccess = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res['message']?.toString() ?? (isSuccess ? 'Key verified!' : 'Test failed')),
        backgroundColor: isSuccess ? AdminColors.accent : AdminColors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleSaveKey(String? currentKey) async {
    final newKey = _keyController.text.trim();
    final keyToSave = newKey.isNotEmpty ? newKey : (currentKey ?? '');

    if (keyToSave.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot save empty API key.'),
          backgroundColor: AdminColors.red,
        ),
      );
      return;
    }

    setState(() => _savingKey = true);

    try {
      await _service.saveAiConfig(
        apiKey: keyToSave,
        activeModel: _selectedModel,
        status: 'healthy',
      );

      if (!mounted) return;
      _keyController.clear();
      setState(() {
        _savingKey = false;
        _testResult = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ AI Key successfully saved & activated on live servers!'),
          backgroundColor: AdminColors.accent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingKey = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save key: $e'),
          backgroundColor: AdminColors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _service.watchAiConfig(),
      builder: (context, snapshot) {
        final config = snapshot.data;
        final rawKey = (config?['api_key'] as String?)?.trim() ?? '';
        final model = (config?['active_model'] as String?)?.trim() ?? _selectedModel;
        final status = (config?['status'] as String?)?.toLowerCase() ?? 'healthy';
        final lastError = config?['last_error'] as String?;
        final lastSuccess = config?['last_success_at'] != null 
            ? DateTime.tryParse(config!['last_success_at'].toString()) 
            : null;

        final isHealthy = status == 'healthy' && lastError == null;

        return Scaffold(
          backgroundColor: AdminColors.bgDark,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildHealthHero(isHealthy, status, lastError, model, lastSuccess, rawKey),
                const SizedBox(height: 24),
                _buildMetricsRow(),
                const SizedBox(height: 24),
                _buildKeyManagementCard(rawKey, model),
                const SizedBox(height: 24),
                _buildTroubleshootingCard(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AdminColors.accentSoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AdminColors.accentBorder.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: AdminColors.accent, size: 28),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI & Vision Engine Settings',
              style: TextStyle(
                color: AdminColors.textWhite,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Manage Google Gemini API keys, monitor live quota & view health telemetry',
              style: TextStyle(color: AdminColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHealthHero(
    bool isHealthy,
    String status,
    String? lastError,
    String activeModel,
    DateTime? lastSuccess,
    String rawKey,
  ) {
    final statusColor = isHealthy ? AdminColors.accent : AdminColors.red;
    final statusBg = isHealthy ? AdminColors.accentSoft : AdminColors.redSoft;
    final statusBorder = isHealthy ? AdminColors.accentBorder : AdminColors.redBorder;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusBorder.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusBorder.withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isHealthy ? 'LIVE ENGINE HEALTHY' : 'ATTENTION REQUIRED: $status'.toUpperCase(),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AdminColors.bgElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AdminColors.borderDark),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.memory_rounded, color: AdminColors.blue, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Model: $activeModel',
                      style: const TextStyle(color: AdminColors.textWhite, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!isHealthy && lastError != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminColors.redSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AdminColors.redBorder.withValues(alpha: 0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AdminColors.red, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Last API Error Report:',
                          style: TextStyle(color: AdminColors.textWhite, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lastError,
                          style: const TextStyle(color: AdminColors.redBorder, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Tip: Generate a fresh 100% Free Tier key at aistudio.google.com in a new project and update below.',
                          style: TextStyle(color: AdminColors.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _buildInfoItem(
                'Current Key Status',
                rawKey.isNotEmpty ? 'Configured (${rawKey.length} chars)' : 'Using Fallback Secret',
              ),
              _buildInfoItem(
                'Last Successful Scan',
                lastSuccess != null ? _dateFmt.format(lastSuccess) : 'Ready & Idle',
              ),
              _buildInfoItem(
                'Zero-Downtime Hot Reload',
                'Active (No App Update Needed)',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AdminColors.textMuted, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: AdminColors.textWhite, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildMetricsRow() {
    return StreamBuilder<int>(
      stream: _service.watchTotalAiScansThisMonth(),
      builder: (context, snapshot) {
        final totalScans = snapshot.data ?? 0;

        return LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 700;
            return isNarrow
                ? Column(
                    children: [
                      _buildMetricCard(
                        'Total Scans (This Month)',
                        totalScans.toString(),
                        'Across all active stores',
                        Icons.qr_code_scanner_rounded,
                        AdminColors.accent,
                      ),
                      const SizedBox(height: 12),
                      _buildMetricCard(
                        'Google Free Quota',
                        '1,500 / Day',
                        '15 requests/min limit',
                        Icons.speed_rounded,
                        AdminColors.blue,
                      ),
                      const SizedBox(height: 12),
                      _buildMetricCard(
                        'Merchant Limit',
                        '10 Free / Mo',
                        'Pro is Unlimited',
                        Icons.storefront_rounded,
                        AdminColors.amber,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          'Total Scans (This Month)',
                          totalScans.toString(),
                          'Across all active stores',
                          Icons.qr_code_scanner_rounded,
                          AdminColors.accent,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildMetricCard(
                          'Google Free Quota',
                          '1,500 / Day',
                          '15 requests/min limit',
                          Icons.speed_rounded,
                          AdminColors.blue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildMetricCard(
                          'Merchant Limit',
                          '10 Free / Mo',
                          'Pro is Unlimited',
                          Icons.storefront_rounded,
                          AdminColors.amber,
                        ),
                      ),
                    ],
                  );
          },
        );
      },
    );
  }

  Widget _buildMetricCard(String title, String value, String sub, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminColors.borderDark),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: AdminColors.textMuted, fontSize: 11)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(color: AdminColors.textWhite, fontSize: 18, fontWeight: FontWeight.bold)),
              Text(sub, style: TextStyle(color: AdminColors.textFaint, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeyManagementCard(String currentKey, String activeModel) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.vpn_key_rounded, color: AdminColors.amber, size: 20),
              const SizedBox(width: 10),
              const Text(
                'Live Gemini API Key Rotation',
                style: TextStyle(
                  color: AdminColors.textWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Paste your Gemini API key below. Updating here takes effect instantly across all Android devices without code deployment or Google Play updates.',
            style: TextStyle(color: AdminColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 20),

          // Current active key display
          if (currentKey.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AdminColors.bgElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AdminColors.borderDark),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded, color: AdminColors.accent, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Active Database Key:',
                          style: TextStyle(color: AdminColors.textMuted, fontSize: 11),
                        ),
                        Text(
                          _obscureCurrentKey ? _maskKey(currentKey) : currentKey,
                          style: const TextStyle(
                            color: AdminColors.textWhite,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _obscureCurrentKey ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: AdminColors.textMuted,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscureCurrentKey = !_obscureCurrentKey),
                    tooltip: 'Toggle visibility',
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, color: AdminColors.textMuted, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: currentKey));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('API Key copied to clipboard!')),
                      );
                    },
                    tooltip: 'Copy Key',
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminColors.accent,
                      side: const BorderSide(color: AdminColors.accent),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    icon: _testingKey
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AdminColors.accent),
                          )
                        : const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text('Test Live Key'),
                    onPressed: _testingKey ? null : () => _handleTestKey(currentKey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // New key input field
          const Text(
            'Enter New Key to Rotate / Update:',
            style: TextStyle(color: AdminColors.textWhite, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _keyController,
            style: const TextStyle(color: AdminColors.textWhite, fontSize: 13, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: 'Paste Gemini API Key (e.g. AQ.Ab8RN6...)',
              prefixIcon: const Icon(Icons.key_rounded, color: AdminColors.textMuted, size: 20),
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste_rounded, color: AdminColors.accent, size: 18),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) {
                    _keyController.text = data!.text!.trim();
                  }
                },
                tooltip: 'Paste from clipboard',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Target Gemini Model Engine:',
                      style: TextStyle(color: AdminColors.textWhite, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: AdminColors.bgElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AdminColors.borderDark),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedModel,
                          dropdownColor: AdminColors.bgElevated,
                          style: const TextStyle(color: AdminColors.textWhite, fontSize: 13),
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'gemini-3.6-flash',
                              child: Text('gemini-3.6-flash (Recommended: Ultra-fast, 100% Free Tier Quota)'),
                            ),
                            DropdownMenuItem(
                              value: 'gemini-2.5-flash',
                              child: Text('gemini-2.5-flash (Standard Flash Model)'),
                            ),
                            DropdownMenuItem(
                              value: 'gemini-flash-latest',
                              child: Text('gemini-flash-latest (Auto Dynamic Latest)'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedModel = val);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Action buttons & Test result preview
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: _savingKey
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_rounded, size: 18),
                label: const Text('Save & Activate Live Key'),
                onPressed: _savingKey ? null : () => _handleSaveKey(currentKey),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminColors.blue,
                  side: const BorderSide(color: AdminColors.blue),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: _testingKey
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AdminColors.blue),
                      )
                    : const Icon(Icons.speed_rounded, size: 18),
                label: const Text('Test Entered Key'),
                onPressed: _testingKey ? null : () => _handleTestKey(),
              ),
            ],
          ),

          if (_testResult != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _testResult!['success'] == true ? AdminColors.accentSoft : AdminColors.redSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _testResult!['success'] == true ? AdminColors.accentBorder : AdminColors.redBorder,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _testResult!['success'] == true ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: _testResult!['success'] == true ? AdminColors.accent : AdminColors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _testResult!['message']?.toString() ?? '',
                      style: const TextStyle(color: AdminColors.textWhite, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTroubleshootingCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.help_outline_rounded, color: AdminColors.blue, size: 20),
              const SizedBox(width: 10),
              const Text(
                'How to get 100% Free Gemini API Keys (Zero Cost Guide)',
                style: TextStyle(
                  color: AdminColors.textWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildGuideStep('1', 'Open aistudio.google.com in your browser with any Google Account.'),
          _buildGuideStep('2', 'Click "Create API Key" and choose "Create in NEW project" (DO NOT choose a project with billing/credit card linked).'),
          _buildGuideStep('3', 'Copy the generated key (starts with "AQ...").'),
          _buildGuideStep('4', 'Paste the key above and click "Save & Activate Live Key". The whole app will switch to it in 1 second!'),
        ],
      ),
    );
  }

  Widget _buildGuideStep(String step, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AdminColors.bgElevated,
              shape: BoxShape.circle,
              border: Border.all(color: AdminColors.borderDark),
            ),
            child: Text(step, style: const TextStyle(color: AdminColors.accent, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: AdminColors.textMuted, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
