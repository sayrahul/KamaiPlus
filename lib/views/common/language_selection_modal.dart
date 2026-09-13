import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/localization/app_language_service.dart';
import '../../core/localization/app_strings.dart';
import 'in_app_notification.dart';

class LanguageSelectionModal extends StatelessWidget {
  const LanguageSelectionModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => const LanguageSelectionModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentCode = AppLanguageService.instance.currentLanguage;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.language_rounded, color: Color(0xFF2563EB), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'select_language'.tr,
                      style: GoogleFonts.outfit(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Regional languages for faster billing',
                      style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < AppStrings.supportedLanguages.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _buildLanguageTile(context, AppStrings.supportedLanguages[i], currentCode),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}

  Widget _buildLanguageTile(BuildContext context, AppLanguage lang, String currentCode) {
    final isSelected = lang.code == currentCode;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        HapticFeedback.selectionClick();
        await AppLanguageService.instance.setLanguage(lang.code);
        if (context.mounted) {
          Navigator.of(context).pop();
          InAppNotification.success(
            'Language set to ${lang.nativeName} (${lang.name})',
            context: context,
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Text(lang.flag, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lang.nativeName,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    lang.name,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFF2563EB),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
              ),
          ],
        ),
      ),
    );
  }
}
