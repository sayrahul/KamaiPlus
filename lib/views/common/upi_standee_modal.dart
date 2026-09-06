import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/database/local_database.dart';
import '../../models/models.dart';

class UpiStandeeModal extends StatefulWidget {
  const UpiStandeeModal({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0xCC020617), // 80% Slate 950
      builder: (ctx) => const UpiStandeeModal(),
    );
  }

  @override
  State<UpiStandeeModal> createState() => _UpiStandeeModalState();
}

class _UpiStandeeModalState extends State<UpiStandeeModal> {
  StoreProfileModel _profile = StoreProfileModel();
  bool _audioVoiceAlert = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final p = await LocalDatabase.instance.getStoreProfile();
      if (mounted) setState(() => _profile = p);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final storeName = _profile.storeName.isNotEmpty
        ? _profile.storeName
        : (_profile.ownerName.isNotEmpty ? _profile.ownerName : 'Rahul Shramas');

    final upiId = _profile.upiVpa.isNotEmpty ? _profile.upiVpa : 'rahuljadhav44@yb1';
    final qrData = 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(storeName)}&cu=INR';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. TOP TITLE BAR
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.storefront_rounded,
                            size: 16,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'OFFICIAL COUNTER UPI STANDEE',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF1F5F9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. SCROLLABLE STANDEE CONTENT
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                  child: Column(
                    children: [
                      // Store Icon & Name
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.local_convenience_store_rounded,
                          size: 22,
                          color: Color(0xFFFBBF24),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        storeName,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Divider(color: Color(0xFFE2E8F0), thickness: 1.2, height: 1),
                      const SizedBox(height: 12),

                      // Scan & Pay Header
                      Text(
                        'SCAN & PAY WITH ANY UPI APP',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                          color: const Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Standee Frame with QR Code
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFF0F172A), width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            QrImageView(
                              data: qrData,
                              version: QrVersions.auto,
                              size: 190,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: Color(0xFF0F172A),
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // UPI ID pill
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Text(
                                upiId,
                                style: GoogleFonts.robotoMono(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Supported UPI Brands
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildBrandBadge('BHIM UPI', const Color(0xFFD97706), const Color(0xFFFFFBEB)),
                          const SizedBox(width: 6),
                          _buildBrandBadge('Google Pay', const Color(0xFF2563EB), const Color(0xFFEFF6FF)),
                          const SizedBox(width: 6),
                          _buildBrandBadge('PhonePe', const Color(0xFF7C3AED), const Color(0xFFF5F3FF)),
                          const SizedBox(width: 6),
                          _buildBrandBadge('Paytm', const Color(0xFF0284C7), const Color(0xFFF0F9FF)),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Soundbox Trust Notice
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.verified_user_rounded, size: 13, color: Color(0xFF059669)),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'Instant Soundbox Voice Alert & 100% Direct Bank Settlement',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF059669),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Audio Voice Alert Toggle Setting
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.volume_up_rounded, size: 16, color: Color(0xFF059669)),
                                const SizedBox(width: 8),
                                Text(
                                  'Audio Voice Alert on Payment',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() => _audioVoiceAlert = !_audioVoiceAlert);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(_audioVoiceAlert
                                        ? '🔊 Soundbox audio alert enabled'
                                        : '🔇 Soundbox audio alert disabled'),
                                    duration: const Duration(seconds: 1),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                decoration: BoxDecoration(
                                  color: _audioVoiceAlert ? const Color(0xFF059669) : const Color(0xFF94A3B8),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _audioVoiceAlert ? 'ON' : 'OFF',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Actions Row (Share, Print, PDF)
                      Row(
                        children: [
                          Expanded(
                            child: _buildActionBtn(
                              icon: Icons.share_outlined,
                              label: 'Share',
                              bgColor: Colors.white,
                              textColor: const Color(0xFF0F172A),
                              borderColor: const Color(0xFFCBD5E1),
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('UPI QR Standee link copied & ready to share!'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildActionBtn(
                              icon: Icons.print_outlined,
                              label: 'Print',
                              bgColor: Colors.white,
                              textColor: const Color(0xFF0F172A),
                              borderColor: const Color(0xFFCBD5E1),
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Sending UPI Standee to Thermal / A4 Printer...'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildActionBtn(
                              icon: Icons.file_download_outlined,
                              label: 'PDF',
                              bgColor: const Color(0xFF0F172A),
                              textColor: Colors.white,
                              iconColor: const Color(0xFFFBBF24),
                              borderColor: const Color(0xFF0F172A),
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Official UPI Standee PDF downloaded!'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrandBadge(String label, Color color, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color textColor,
    Color? iconColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: iconColor ?? textColor),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
