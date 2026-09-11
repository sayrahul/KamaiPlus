import 'package:intl/intl.dart';

/// English Relative Time Formatter for retail transactions, ledgers, and credit reminders.
class DateTimeUtils {
  /// Converts a [DateTime] into a clean, human-readable English relative string.
  /// Examples:
  /// - Just now (< 1 min)
  /// - 15 mins ago
  /// - Today, 4:15 PM
  /// - Yesterday, 11:30 AM
  /// - 3 days ago
  /// - 18 days ago • Overdue (if isCredit == true and days >= 15)
  /// - 12 Aug 2026 (> 30 days)
  static String formatRelativeTime(
    DateTime dateTime, {
    bool isCredit = false,
    bool includeTime = false,
  }) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    // If in future (clock skew)
    if (difference.isNegative) {
      return DateFormat('d MMM yyyy').format(dateTime);
    }

    final int inMinutes = difference.inMinutes;
    final int inDays = difference.inDays;

    final timeStr = DateFormat('h:mm a').format(dateTime);

    if (inMinutes < 2) {
      return 'Just now';
    }

    if (inMinutes < 60) {
      return '$inMinutes mins ago';
    }

    // Check if same calendar day
    final isToday = now.year == dateTime.year &&
        now.month == dateTime.month &&
        now.day == dateTime.day;
    if (isToday) {
      return 'Today, $timeStr';
    }

    // Check if yesterday
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = yesterday.year == dateTime.year &&
        yesterday.month == dateTime.month &&
        yesterday.day == dateTime.day;
    if (isYesterday) {
      return includeTime ? 'Yesterday, $timeStr' : 'Yesterday';
    }

    // 2 to 29 days
    if (inDays < 30) {
      final daysCount = inDays <= 1 ? 2 : inDays;
      if (isCredit && daysCount >= 15) {
        return '$daysCount days ago • Overdue';
      }
      return '$daysCount days ago';
    }

    // 30+ days: Show Month & Day (or year if different)
    if (now.year == dateTime.year) {
      return DateFormat('d MMM').format(dateTime);
    } else {
      return DateFormat('d MMM yyyy').format(dateTime);
    }
  }

  /// Compact relative time for lists & badges: e.g. "Today", "Yesterday", "4d ago", "3w ago"
  static String formatCompact(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.isNegative) return 'Now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (now.day == dateTime.day && now.month == dateTime.month && now.year == dateTime.year) {
      return 'Today';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (yesterday.day == dateTime.day && yesterday.month == dateTime.month && yesterday.year == dateTime.year) {
      return 'Yesterday';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return '${weeks}w ago';
    }
    return DateFormat('d MMM').format(dateTime);
  }
}
