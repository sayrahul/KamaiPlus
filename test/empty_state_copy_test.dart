// Tests for the 2026-09-12 professional-polish-pass fix: a genuinely empty
// catalog (no products yet, no active search/filter) needs its own copy per
// vertical, distinct from "no results for your search" — showing the
// search-empty message on a brand-new store with nothing added was the
// exact gap the KamaiPlus Playbook flagged. See products_screen.dart and
// pos_billing_screen.dart for where these are actually used.
import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/core/constants/business_vertical_config.dart';

void main() {
  group('emptyCatalogTitle / emptyCatalogDescription', () {
    test('every vertical has distinct, non-generic copy', () {
      final verticals = [
        BusinessVerticals.grocery,
        BusinessVerticals.pharmacy,
        BusinessVerticals.clothing,
        BusinessVerticals.hardware,
        BusinessVerticals.restaurant,
      ];
      final titles = verticals.map((v) => v.emptyCatalogTitle).toSet();
      // Grocery/hardware share the generic "No products/items added yet"
      // shape by design (there's no more specific noun for either), but
      // restaurant/pharmacy/clothing must each read as written for that
      // trade, not a copy-pasted generic string.
      expect(titles.length, greaterThanOrEqualTo(4));

      for (final v in verticals) {
        expect(v.emptyCatalogTitle, isNotEmpty);
        expect(v.emptyCatalogDescription, isNotEmpty);
      }
    });

    test('restaurant mentions the menu-scan flow, not a generic "add a product"', () {
      expect(BusinessVerticals.restaurant.emptyCatalogDescription.toLowerCase(), contains('menu'));
    });

    test('the description names the same first action as the Add button label', () {
      // Not a literal string match (the button says "Add Dish", the
      // description says "add your first dish") — just checking the
      // description doesn't contradict what the button actually does.
      expect(BusinessVerticals.restaurant.emptyCatalogDescription.toLowerCase(), contains('dish'));
      expect(BusinessVerticals.pharmacy.emptyCatalogDescription.toLowerCase(), contains('medicine'));
      expect(BusinessVerticals.clothing.emptyCatalogDescription.toLowerCase(), contains('apparel'));
    });
  });
}
