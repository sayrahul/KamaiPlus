import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A saved cash count: what was in the drawer, what the app expected, and when.
class CashTallyDraft {
  /// Note/coin face value in rupees → how many of them were counted.
  final Map<int, int> denominations;

  /// What the denominations add up to.
  final int countedPaise;

  /// What the register expected to be in the drawer at the moment of counting.
  /// Kept with the draft rather than recomputed: the expected figure moves with
  /// every sale, so a variance recomputed an hour later would be comparing the
  /// old count against a new expectation and reporting a discrepancy that never
  /// happened.
  final int expectedPaise;

  final DateTime savedAt;

  const CashTallyDraft({
    required this.denominations,
    required this.countedPaise,
    required this.expectedPaise,
    required this.savedAt,
  });

  /// Positive = more cash in the drawer than expected, negative = short.
  int get variancePaise => countedPaise - expectedPaise;

  bool get isMatched => variancePaise == 0;

  Map<String, dynamic> toJson() => {
        'denominations': denominations.map((k, v) => MapEntry(k.toString(), v)),
        'counted_paise': countedPaise,
        'expected_paise': expectedPaise,
        'saved_at': savedAt.toIso8601String(),
      };

  static CashTallyDraft? fromJson(Map<String, dynamic> json) {
    try {
      final raw = json['denominations'];
      if (raw is! Map) return null;
      final denoms = <int, int>{};
      raw.forEach((k, v) {
        final denom = int.tryParse(k.toString());
        final count = (v as num?)?.toInt();
        if (denom != null && count != null) denoms[denom] = count;
      });
      final savedAt = DateTime.tryParse(json['saved_at']?.toString() ?? '');
      if (savedAt == null) return null;
      return CashTallyDraft(
        denominations: denoms,
        countedPaise: (json['counted_paise'] as num?)?.toInt() ?? 0,
        expectedPaise: (json['expected_paise'] as num?)?.toInt() ?? 0,
        savedAt: savedAt,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Persists the Note & Tally cash count across app restarts.
///
/// The counter used to hold its denominations in a `setState` field on
/// `CashRegisterScreen`, and the Home tab's entry point passed neither an
/// initial value nor an `onSaved` callback at all. So a shopkeeper who counted
/// a full drawer — nine denominations, the slowest careful thing they do all
/// day — lost the whole count the moment they left the screen, and reopening
/// showed zeros. Confirming the count appeared to save it and saved nothing.
///
/// Scoped to the IST day on purpose. A cash count is a statement about the
/// drawer at a moment in time; showing yesterday's count as today's opening
/// figure would be worse than showing nothing, because it looks authoritative.
/// The day rolls at IST midnight rather than UTC, so an evening count does not
/// disappear at 5:30 AM the next morning mid-way through opening up.
class CashTallyDraftService {
  CashTallyDraftService._();
  static final CashTallyDraftService instance = CashTallyDraftService._();

  static const String _prefKeyPrefix = 'cash_tally_draft_';

  static String _dayKey(DateTime now) {
    final ist = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    return '${ist.year.toString().padLeft(4, '0')}-'
        '${ist.month.toString().padLeft(2, '0')}-'
        '${ist.day.toString().padLeft(2, '0')}';
  }

  static String _key(DateTime now) => '$_prefKeyPrefix${_dayKey(now)}';

  /// Saves the confirmed count for today.
  Future<void> save({
    required Map<int, int> denominations,
    required int countedPaise,
    required int expectedPaise,
  }) async {
    try {
      final now = DateTime.now();
      final draft = CashTallyDraft(
        denominations: Map<int, int>.from(denominations),
        countedPaise: countedPaise,
        expectedPaise: expectedPaise,
        savedAt: now,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(now), jsonEncode(draft.toJson()));
      await _pruneOldDrafts(prefs, keep: _key(now));
    } catch (_) {
      // A failed save must never take the counter down with it — the merchant
      // still has their count on screen.
    }
  }

  /// Today's saved count, or null if nothing has been counted today.
  Future<CashTallyDraft?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(DateTime.now()));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return CashTallyDraft.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(DateTime.now()));
    } catch (_) {}
  }

  /// Drops drafts from previous days so the preference store does not grow a
  /// new key every day for the life of the install.
  Future<void> _pruneOldDrafts(SharedPreferences prefs, {required String keep}) async {
    try {
      final stale = prefs
          .getKeys()
          .where((k) => k.startsWith(_prefKeyPrefix) && k != keep)
          .toList();
      for (final k in stale) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}
