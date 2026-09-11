import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/gemini_ai_service.dart';

/// Lets a merchant enter/test their Gemini API key for any AI Vision feature
/// (wholesale bill OCR, menu-photo scan). Extracted out of `ai_inward_sheet.dart`
/// (its original, single-caller home) so `menu_scan_sheet.dart` can show the
/// same, already-working dialog instead of leaving the restaurant menu-scan
/// flow with no way to act on its own "Tap Settings" error message.
class GeminiApiKeyDialog {
  static Future<void> show(BuildContext context) async {
    final currentKey = await GeminiAiService.getEffectiveApiKey();
    final ctrl = TextEditingController(text: currentKey);

    if (!context.mounted) return;

    bool isTesting = false;
    String? testStatus;

    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.key_rounded, color: Color(0xFF059669), size: 20),
                ),
                const SizedBox(width: 8),
                Text('Gemini AI Vision Key', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter your Google AI Studio Gemini API Key for OCR scanning of bills, mandi parchas, and menu photos.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    labelText: 'Gemini API Key (AIzaSy...)',
                    labelStyle: GoogleFonts.plusJakartaSans(fontSize: 11),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                  style: GoogleFonts.jetBrainsMono(fontSize: 12),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => launchUrl(Uri.parse('https://aistudio.google.com/app/apikey'), mode: LaunchMode.externalApplication),
                  child: Text(
                    '🔗 Get a 100% Free Gemini API Key from Google AI Studio',
                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF0284C7), fontWeight: FontWeight.w700),
                  ),
                ),
                if (testStatus != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    testStatus!,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: testStatus!.contains('✅') ? const Color(0xFF059669) : const Color(0xFFDC2626),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B))),
              ),
              TextButton(
                onPressed: isTesting
                    ? null
                    : () async {
                        setDlgState(() {
                          isTesting = true;
                          testStatus = 'Testing API Key...';
                        });
                        final ok = await GeminiAiService.testApiKey(ctrl.text.trim());
                        setDlgState(() {
                          isTesting = false;
                          testStatus = ok ? '✅ API Key is Valid & Active!' : '❌ Invalid API Key. Please verify.';
                        });
                      },
                child: Text('Test Key', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
              ),
              ElevatedButton(
                onPressed: () async {
                  await GeminiAiService.setCustomApiKey(ctrl.text.trim());
                  if (ctx.mounted) Navigator.pop(dlgCtx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✅ Gemini API Key saved successfully!'), backgroundColor: Color(0xFF059669)),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('Save Key', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      ),
    );
  }
}
