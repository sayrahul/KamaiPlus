import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Sacred Financial Invariant: Zero-Drift Integer Paise Math Engine
/// All money is stored, computed, and passed in integer paise (1 INR = 100 paise).
class MoneyFormatter {
  /// FontFeatures for aligned financial columns in ledgers, cart, and invoices
  static const List<FontFeature> tabularFeatures = [
    FontFeature.tabularFigures(),
  ];

  /// Convenient helper to create tabular figures text style
  static TextStyle tabularStyle({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    TextDecoration? decoration,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      decoration: decoration,
      fontFeatures: tabularFeatures,
    );
  }

  static final NumberFormat _inrFormatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static final NumberFormat _inrCompactFormatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  /// Formats integer paise into Indian currency string: 49900 -> "₹499.00"
  static String formatPaise(int paise, {bool hideZeroDecimals = false}) => formatINR(paise, hideZeroDecimals: hideZeroDecimals);

  static String formatINR(int paise, {bool hideZeroDecimals = false}) {
    final double rupees = paise / 100.0;
    if (hideZeroDecimals && paise % 100 == 0) {
      return _inrCompactFormatter.format(rupees);
    }
    return _inrFormatter.format(rupees);
  }

  /// Parses user string input like "499.50" into 49950 paise safely with 0 floating point drift
  static int parseRupeesToPaise(String input) {
    if (input.trim().isEmpty) return 0;
    final cleaned = input.replaceAll('₹', '').replaceAll(',', '').trim();
    if (cleaned.isEmpty) return 0;

    final bool isNegative = cleaned.startsWith('-');
    final absCleaned = isNegative ? cleaned.substring(1) : cleaned;

    final parts = absCleaned.split('.');
    final int rupees = int.tryParse(parts[0]) ?? 0;
    int paise = 0;

    if (parts.length > 1) {
      final dec = parts[1];
      if (dec.length == 1) {
        paise = (int.tryParse(dec) ?? 0) * 10;
      } else if (dec.length == 2) {
        paise = int.tryParse(dec) ?? 0;
      } else if (dec.length > 2) {
        // Round to nearest paisa based on 3rd decimal digit
        final firstTwo = int.tryParse(dec.substring(0, 2)) ?? 0;
        final thirdDigit = int.tryParse(dec[2]) ?? 0;
        paise = thirdDigit >= 5 ? firstTwo + 1 : firstTwo;
      }
    }

    final total = rupees * 100 + paise;
    return isNegative ? -total : total;
  }

  /// GST Tax Calculation (Inclusive vs Exclusive)
  /// Returns {taxableAmount, cgst, sgst, totalGst, grossTotal} in integer paise.
  static Map<String, int> calculateGst({
    required int grossOrBasePaise,
    required double taxRatePercent,
    required bool isInclusive,
  }) {
    if (taxRatePercent <= 0) {
      return {
        'taxableAmount': grossOrBasePaise,
        'cgst': 0,
        'sgst': 0,
        'totalGst': 0,
        'grossTotal': grossOrBasePaise,
      };
    }

    final int rateBps = (taxRatePercent * 100).round();

    if (isInclusive) {
      // Taxable = round(Gross * 10000 / (10000 + RateBps))
      final int taxable = ((grossOrBasePaise * 10000) / (10000 + rateBps)).round();
      final int totalGst = grossOrBasePaise - taxable;
      final int cgst = (totalGst / 2).round();
      final int sgst = totalGst - cgst;

      return {
        'taxableAmount': taxable,
        'cgst': cgst,
        'sgst': sgst,
        'totalGst': totalGst,
        'grossTotal': grossOrBasePaise,
      };
    } else {
      // Exclusive: Gross = Taxable + round(Taxable * RateBps / 10000)
      final int totalGst = ((grossOrBasePaise * rateBps) / 10000).round();
      final int cgst = (totalGst / 2).round();
      final int sgst = totalGst - cgst;
      final int gross = grossOrBasePaise + totalGst;

      return {
        'taxableAmount': grossOrBasePaise,
        'cgst': cgst,
        'sgst': sgst,
        'totalGst': totalGst,
        'grossTotal': gross,
      };
    }
  }
}
