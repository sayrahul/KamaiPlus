import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/biometric_service.dart';
import 'in_app_notification.dart';

class OwnerPrivacyModal extends StatefulWidget {
  final VoidCallback onUnlocked;

  const OwnerPrivacyModal({super.key, required this.onUnlocked});

  static Future<void> show(BuildContext context, {required VoidCallback onUnlocked}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0xCC020617), // 80% Slate 950
      builder: (ctx) => OwnerPrivacyModal(onUnlocked: onUnlocked),
    );
  }

  @override
  State<OwnerPrivacyModal> createState() => _OwnerPrivacyModalState();
}

class _OwnerPrivacyModalState extends State<OwnerPrivacyModal> {
  String _pin = '';
  String _errorMessage = '';
  String _successMessage = '';
  bool _isChangingPin = false;
  bool _isBiometricSupported = false;

  @override
  void initState() {
    super.initState();
    _initBiometric();
  }

  Future<void> _initBiometric() async {
    final available = await BiometricService.instance.isBiometricAvailable();
    if (mounted) {
      setState(() => _isBiometricSupported = available);
      if (available) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _triggerBiometric();
        });
      }
    }
  }

  Future<void> _triggerBiometric() async {
    final success = await BiometricService.instance.authenticateOwner(
      reason: 'KamaiPlus Owner Verification: Touch fingerprint sensor to unlock',
    );
    if (success && mounted) {
      Navigator.of(context).pop();
      widget.onUnlocked();
      InAppNotification.show(
        context: context,
        message: 'Biometric verified: Margins & Reports unlocked!',
        customIcon: Icons.fingerprint_rounded,
        customColor: const Color(0xFF10B981),
      );
    }
  }

  String _currentPinInput = '';
  String _newPinInput = '';
  String _confirmPinInput = '';

  static const String _defaultPin = '1234';
  static const String _pinPrefKey = 'owner_cashier_pin';

  Future<String> _getSavedPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pinPrefKey) ?? _defaultPin;
  }

  Future<void> _saveNewPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinPrefKey, pin);
  }

  Future<void> _verifyPin() async {
    setState(() => _errorMessage = '');
    final savedPin = await _getSavedPin();

    if (_pin == savedPin) {
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onUnlocked();
      InAppNotification.show(
        context: context,
        message: 'Profit margins & cost prices unlocked!',
        customIcon: Icons.lock_open_rounded,
        customColor: const Color(0xFF10B981),
      );
    } else {
      setState(() {
        _errorMessage = 'Incorrect 4-digit PIN. (Default is 1234)';
        _pin = '';
      });
    }
  }

  Future<void> _handleChangePin() async {
    setState(() {
      _errorMessage = '';
      _successMessage = '';
    });

    final savedPin = await _getSavedPin();
    if (_currentPinInput != savedPin) {
      setState(() => _errorMessage = 'Current PIN is incorrect.');
      return;
    }

    if (_newPinInput.length != 4) {
      setState(() => _errorMessage = 'New PIN must be exactly 4 digits.');
      return;
    }

    if (_newPinInput != _confirmPinInput) {
      setState(() => _errorMessage = 'New PIN and confirmation do not match.');
      return;
    }

    await _saveNewPin(_newPinInput);
    setState(() {
      _successMessage = 'Owner PIN changed successfully!';
      _currentPinInput = '';
      _newPinInput = '';
      _confirmPinInput = '';
    });

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          _isChangingPin = false;
          _successMessage = '';
        });
      }
    });
  }

  void _onDigitPressed(String digit) {
    if (_pin.length < 4) {
      setState(() {
        _pin += digit;
        _errorMessage = '';
      });
      if (_pin.length == 4) {
        _verifyPin();
      }
    }
  }

  void _onBackspacePressed() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
        _errorMessage = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isChangingPin ? 'Change Security PIN' : 'Owner Privacy Lock',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF1F5F9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded, size: 17, color: Color(0xFF64748B)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Content Body
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: _isChangingPin ? _buildChangePinForm() : _buildVerifyPinBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerifyPinBody() {
    return Column(
      children: [
        // Lock Icon Container
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
          ),
          child: const Center(
            child: Icon(
              Icons.lock_rounded,
              size: 26,
              color: Color(0xFFD97706),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Title
        Text(
          'Unlock Profit Margins & Cost Prices',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 5),

        // Subtitle
        Text(
          'Enter your 4-digit Owner PIN to view purchase prices, profit margins, and net profits.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            color: const Color(0xFF64748B),
            height: 1.3,
          ),
        ),
        const SizedBox(height: 16),

        // Error message banner
        if (_errorMessage.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, size: 14, color: Color(0xFFDC2626)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _errorMessage,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFDC2626),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Label
        Text(
          'Enter 4-Digit Owner PIN',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 10),

        // 4 Dots Display Box
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _errorMessage.isNotEmpty ? const Color(0xFFEF4444) : const Color(0xFFE2E8F0),
              width: 1.3,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              final isFilled = index < _pin.length;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFilled ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Default PIN is 1234',
          style: GoogleFonts.robotoMono(
            fontSize: 11,
            color: const Color(0xFF94A3B8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),

        if (_isBiometricSupported) ...[
          InkWell(
            onTap: _triggerBiometric,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.fingerprint_rounded, size: 20, color: Color(0xFF2563EB)),
                  const SizedBox(width: 8),
                  Text(
                    'Touch Fingerprint to Unlock',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // Keypad Grid for Fast Mobile Entry
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _buildKeypadRow(['1', '2', '3']),
              const SizedBox(height: 8),
              _buildKeypadRow(['4', '5', '6']),
              const SizedBox(height: 8),
              _buildKeypadRow(['7', '8', '9']),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _triggerBiometric,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: const Icon(
                            Icons.fingerprint_rounded,
                            size: 22,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _buildKeypadBtn('0')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _onBackspacePressed,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.backspace_outlined,
                            size: 18,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Unlock Button
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _pin.length == 4 ? _verifyPin : null,
            borderRadius: BorderRadius.circular(13),
            child: Container(
              height: 44,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _pin.length == 4
                      ? [const Color(0xFFFBBF24), const Color(0xFFF59E0B)]
                      : [const Color(0xFFFDE68A), const Color(0xFFFBBF24)],
                ),
                borderRadius: BorderRadius.circular(13),
                boxShadow: _pin.length == 4
                    ? [
                        BoxShadow(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  'Unlock Secret Data',
                  style: GoogleFonts.outfit(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Change PIN Link
        GestureDetector(
          onTap: () {
            setState(() {
              _isChangingPin = true;
              _errorMessage = '';
            });
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.key_rounded, size: 14, color: Color(0xFFB45309)),
              const SizedBox(width: 4),
              Text(
                'Change 4-Digit PIN',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFB45309),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeypadRow(List<String> digits) {
    return Row(
      children: digits.map((digit) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _buildKeypadBtn(digit),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKeypadBtn(String digit) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onDigitPressed(digit),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Center(
            child: Text(
              digit,
              style: GoogleFonts.robotoMono(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChangePinForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_errorMessage.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Text(
              _errorMessage,
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFDC2626)),
            ),
          ),
        if (_successMessage.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Text(
              _successMessage,
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF059669)),
            ),
          ),
        _buildTextField('Current 4-Digit PIN', (val) => _currentPinInput = val),
        const SizedBox(height: 10),
        _buildTextField('New 4-Digit PIN', (val) => _newPinInput = val),
        const SizedBox(height: 10),
        _buildTextField('Confirm New PIN', (val) => _confirmPinInput = val),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _isChangingPin = false),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('Back', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: _handleChangePin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFBBF24),
                  foregroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('Save PIN', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField(String label, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
        ),
        const SizedBox(height: 4),
        TextField(
          obscureText: true,
          maxLength: 4,
          keyboardType: TextInputType.number,
          onChanged: onChanged,
          textAlign: TextAlign.center,
          style: GoogleFonts.robotoMono(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 8),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
