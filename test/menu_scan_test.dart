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

  // The group above passed throughout the outage it was supposed to catch: it
  // only ever fed the parser the field names the parser already read. The
  // Cloud Function was sending product_name / selling_price_paise /
  // category_name, so a menu Gemini had read perfectly (the function logged
  // "17 item(s)") arrived on device as seventeen rows of "Menu Item" at ₹0.00,
  // and the sheet fell through to offline OCR junk. These tests feed it the
  // payload the server really sends.
  group('ExtractedMenuItem.fromJson — real aiExtract payload shape', () {
    test('reads the bill-shaped field names the proxy emits', () {
      final item = ExtractedMenuItem.fromJson({
        'product_name': 'Mutton Hydrabadi (4pcs)',
        'selling_price_paise': 44000,
        'purchase_price_paise': 44000,
        'mrp_paise': 44000,
        'category_name': 'Mutton',
        'is_veg': false,
      });

      expect(item.dishName, 'Mutton Hydrabadi (4pcs)');
      expect(item.priceInPaise, 44000);
      expect(item.category, 'Mutton');
    });

    test('menu keys still win when the server sends both shapes', () {
      final item = ExtractedMenuItem.fromJson({
        'dish_name': 'Kadai Mutton',
        'price_paise': 38000,
        'product_name': 'Kadai Mutton',
        'selling_price_paise': 38000,
        'category': 'Mutton',
        'category_name': 'Mutton',
      });

      expect(item.dishName, 'Kadai Mutton');
      expect(item.priceInPaise, 38000);
    });

    test('falls back to mrp_paise when no selling price came back', () {
      final item = ExtractedMenuItem.fromJson({'product_name': 'Fish Fry', 'mrp_paise': 26000});
      expect(item.priceInPaise, 26000);
    });

    test('strips the serial number the menu prints before each dish', () {
      expect(
        ExtractedMenuItem.fromJson({'dish_name': '21.Chicken Hydrabadi(5pcs)', 'price_paise': 32000}).dishName,
        'Chicken Hydrabadi(5pcs)',
      );
      expect(
        ExtractedMenuItem.fromJson({'dish_name': '1) Mutton Kasa (4pcs)', 'price_paise': 32000}).dishName,
        'Mutton Kasa (4pcs)',
      );
    });

    test('keeps a Devanagari dish name intact', () {
      final item = ExtractedMenuItem.fromJson({'dish_name': '3. मटन रेजाला', 'price_paise': 36000});
      expect(item.dishName, 'मटन रेजाला');
      expect(item.priceInPaise, 36000);
    });
  });

  // The three rows a merchant actually saw on screen: a column header, one real
  // dish, and a stray price cell. Two of the three must never reach the review
  // sheet again.
  group('ExtractedMenuItem.isRealDishName', () {
    test('rejects the column headers a menu prints', () {
      for (final junk in ['Rate', 'rate', 'Rate/-', 'Item', 'Items', 'Sr. No', 'S.NO', 'MRP', 'Price', 'Qty', 'Total']) {
        expect(ExtractedMenuItem.isRealDishName(junk), isFalse, reason: '"\$junk" is a table header, not a dish');
      }
    });

    test('rejects a stray price cell', () {
      for (final junk in ['360/-|', '360/-', '120', '---', '|', '  ', '₹340']) {
        expect(ExtractedMenuItem.isRealDishName(junk), isFalse, reason: '"\$junk" is not a dish name');
      }
    });

    test('accepts real dishes, including non-Latin scripts', () {
      for (final name in [
        'Mutton Hydrabadi(4pcs)',
        'Kadai Mutton',
        'Chicken Dilbar (5pcs)',
        'मटन कसा',
        'பன்னீர் டிக்கா',
        'ਪਨੀਰ ਟਿੱਕਾ',
        'চিকেন কারি',
      ]) {
        expect(ExtractedMenuItem.isRealDishName(name), isTrue, reason: '"\$name" is a real dish');
      }
    });

    test('a dish whose name merely contains a header word is still a dish', () {
      expect(ExtractedMenuItem.isRealDishName('Special Thali'), isTrue);
      expect(ExtractedMenuItem.isRealDishName('Full Plate Biryani'), isTrue);
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
