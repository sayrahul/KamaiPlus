import 'package:flutter/services.dart';

/// Zero-Permission Android Contacts Picker Service
/// Delegates to Android OS contact picker (ContactsContract)
/// Does NOT require READ_CONTACTS permission in AndroidManifest.xml
class ContactsService {
  ContactsService._();
  static final ContactsService instance = ContactsService._();

  static const MethodChannel _channel = MethodChannel('com.kamaiplus.pos/contacts');

  /// Opens the native Android contact picker.
  /// Returns a Map with 'name' and 'phone' (cleaned to 10 digits if Indian format),
  /// or null if the user canceled.
  Future<Map<String, String>?> pickContact() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('pickContact');
      if (result == null) return null;

      final rawName = result['name']?.toString().trim() ?? '';
      final rawPhone = result['phone']?.toString().trim() ?? '';

      // Normalize phone number (remove spaces, hyphens, parenthesis)
      String cleanPhone = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
      
      // If starts with +91 or 91 with 12 digits, extract the 10 digits
      if (cleanPhone.startsWith('+91') && cleanPhone.length == 13) {
        cleanPhone = cleanPhone.substring(3);
      } else if (cleanPhone.startsWith('91') && cleanPhone.length == 12) {
        cleanPhone = cleanPhone.substring(2);
      } else if (cleanPhone.startsWith('0') && cleanPhone.length == 11) {
        cleanPhone = cleanPhone.substring(1);
      }

      return {
        'name': rawName,
        'phone': cleanPhone,
      };
    } on PlatformException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }
}
