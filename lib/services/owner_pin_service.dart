import 'package:shared_preferences/shared_preferences.dart';

/// The one owner PIN, for every place the app asks "are you really the owner?".
///
/// There used to be two answers to that question. The eye button (margins and
/// cost prices) read a PIN the owner could change, stored under
/// `owner_cashier_pin`. The sales-return flow compared against the string
/// literals `'1234'` and `'0000'`, written inline at two call sites in
/// `sale_detail_modal.dart`. So an owner who changed their PIN changed nothing
/// about refunds: the factory default stayed valid forever, on every install,
/// and the one screen that hands money back over the counter was the screen
/// still accepting it.
///
/// Every caller goes through [verify] now, so changing the PIN in one place
/// changes it everywhere, and a hardcoded comparison cannot creep back in
/// without deleting this class.
class OwnerPinService {
  OwnerPinService._();
  static final OwnerPinService instance = OwnerPinService._();

  /// Kept as the key the eye button already used, so owners who had already
  /// set a PIN keep it — a rename here would silently reset every install back
  /// to the default.
  static const String _pinPrefKey = 'owner_cashier_pin';

  static const String defaultPin = '1234';

  /// Whether the owner has ever set their own PIN.
  ///
  /// Worth surfacing: a shop still on the factory default has no protection on
  /// refunds at all, and the UI nudges them rather than staying quiet about it.
  Future<bool> isUsingDefaultPin() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_pinPrefKey);
    return saved == null || saved.isEmpty || saved == defaultPin;
  }

  Future<String> getPin() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_pinPrefKey)?.trim() ?? '';
    return saved.isEmpty ? defaultPin : saved;
  }

  Future<void> setPin(String pin) async {
    final clean = pin.trim();
    if (clean.length != 4) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinPrefKey, clean);
  }

  /// True when [entered] matches the owner's PIN.
  ///
  /// `'0000'` is deliberately NOT accepted as a second master PIN. The return
  /// flow used to allow it alongside `'1234'`, which meant a shop that had
  /// dutifully changed their PIN still had two publicly-known codes that
  /// authorised a cash refund.
  Future<bool> verify(String entered) async {
    final clean = entered.trim();
    if (clean.length != 4) return false;
    return clean == await getPin();
  }
}
