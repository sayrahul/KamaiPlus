// Tests for the Restaurant "Scan Menu Photo" feature added 2026-09-11:
// GeminiAiService.extractMenuItemsFromImage's JSON parsing, and
// LocalDatabase.findOrCreateCategoryId, the shared helper the menu-item review
// sheet uses to avoid creating duplicate categories on repeat scans.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kamaiplus_pos/core/database/local_database.dart';
import 'package:kamaiplus_pos/services/gemini_ai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('ExtractedMenuItem.fromJson', () {
    test('reads price_paise directly when present', () {
      final item = ExtractedMenuItem.fromJson({
        'dish_name': 'Paneer Butter Masala (Full)',
        'price_paise': 22000,
        'category': 'Main Course (Curries)',
      });

      expect(item.dishName, 'Paneer Butter Masala (Full)');
      expect(item.priceInPaise, 22000);
      expect(item.category, 'Main Course (Curries)');
    });

    test('falls back to rupee "price" and converts to paise', () {
      final item = ExtractedMenuItem.fromJson({
        'dish_name': 'Cold Coffee',
        'price': 120,
      });

      expect(item.priceInPaise, 12000);
    });

    test('cleans a currency-symbol string price', () {
      final item = ExtractedMenuItem.fromJson({
        'dish_name': 'Veg Biryani',
        'price': '₹180.50',
      });

      expect(item.priceInPaise, 18050);
    });

    test('missing dish_name falls back to a safe default rather than throwing', () {
      final item = ExtractedMenuItem.fromJson({'price_paise': 5000});
      expect(item.dishName, isNotEmpty);
    });

    test('missing category defaults to General', () {
      final item = ExtractedMenuItem.fromJson({'dish_name': 'Masala Dosa', 'price_paise': 8000});
      expect(item.category, 'General');
    });
  });

  group('LocalDatabase.findOrCreateCategoryId', () {
    setUp(() async {
      await LocalDatabase.instance.switchUser('menu_scan_test_${DateTime.now().microsecondsSinceEpoch}');
    });

    tearDown(() async {
      await LocalDatabase.instance.closeDatabase();
    });

    test('creates a new category when none exists', () async {
      final id = await LocalDatabase.instance.findOrCreateCategoryId(
        name: 'Hot & Cold Beverages',
        businessId: 'biz_test',
        businessType: 'restaurant',
      );

      final cats = await LocalDatabase.instance.getAllCategories(businessType: 'restaurant');
      expect(cats.any((c) => c.id == id && c.name == 'Hot & Cold Beverages'), isTrue);
    });

    test('a second call with the same name reuses the category instead of duplicating', () async {
      final firstId = await LocalDatabase.instance.findOrCreateCategoryId(
        name: 'Starters & Snacks',
        businessId: 'biz_test',
        businessType: 'restaurant',
      );
      final secondId = await LocalDatabase.instance.findOrCreateCategoryId(
        name: 'starters & snacks', // different case, matching a repeat menu scan
        businessId: 'biz_test',
        businessType: 'restaurant',
      );

      expect(secondId, firstId, reason: 'a repeat scan must not create a duplicate category');

      final cats = await LocalDatabase.instance.getAllCategories(businessType: 'restaurant');
      final matching = cats.where((c) => c.name.toLowerCase() == 'starters & snacks').length;
      expect(matching, 1);
    });

    test('does not cross vertical boundaries (same fix as the product/category leak)', () async {
      await LocalDatabase.instance.findOrCreateCategoryId(
        name: 'Main Course (Curries)',
        businessId: 'biz_test',
        businessType: 'restaurant',
      );

      // A grocery store looking for a same-named category must not see the
      // restaurant one, and must get its own.
      final groceryId = await LocalDatabase.instance.findOrCreateCategoryId(
        name: 'Main Course (Curries)',
        businessId: 'biz_test',
        businessType: 'grocery',
      );

      final groceryCats = await LocalDatabase.instance.getAllCategories(businessType: 'grocery');
      expect(groceryCats.any((c) => c.id == groceryId && c.businessType == 'grocery'), isTrue);

      final restaurantCats = await LocalDatabase.instance.getAllCategories(businessType: 'restaurant');
      expect(restaurantCats.any((c) => c.businessType == 'grocery'), isFalse);
    });
  });
}
