// Regression test for a bug found and fixed while adding the loose-item
// quantity fix (2026-09-11): quick_stock_update_modal.dart's _saveInward and
// _saveAdjustment used to reconstruct a fresh ProductModel(...) field-by-field
// instead of calling product.copyWith(...). That silently dropped every field
// the reconstruction forgot to list — most seriously businessType, which
// defaults to 'grocery' — meaning a single stock update on a pharmacy
// medicine or a hardware item would silently reclassify it as grocery and
// make it vanish from (or wrongly appear in) other verticals' catalogs. Both
// call sites now use copyWith, which is what this test locks in: any field
// not explicitly overridden must survive, forever, without each new field
// needing its own opt-in at every call site that touches a product.
import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/models/models.dart';

void main() {
  group('ProductModel.copyWith preserves fields not explicitly overridden', () {
    final original = ProductModel(
      id: 'p1',
      businessId: 'biz1',
      name: 'Crocin Advance',
      barcode: '8901030123456',
      categoryId: 'cat_pharmacy_meds',
      sellingPricePaise: 3500,
      mrpPaise: 4000,
      purchasePricePaise: 2800,
      stockQuantity: 12,
      taxRate: 12.0,
      unit: 'strip',
      businessType: 'pharmacy',
      subUnitsPerPack: 15,
      isFavorite: true,
      hsnCode: '3004',
    );

    test('a stock-only update (the "pencil" inward flow) keeps businessType', () {
      final updated = original.copyWith(stockQuantity: 20, syncStatus: 'pending');

      expect(updated.businessType, 'pharmacy', reason: 'this is the exact bug: a stock update must never silently reset the vertical');
      expect(updated.stockQuantity, 20);
    });

    test('a stock-only update keeps the new tablets-per-strip field', () {
      final updated = original.copyWith(stockQuantity: 5, syncStatus: 'pending');
      expect(updated.subUnitsPerPack, 15);
    });

    test('a price-only update (inward with a price change) keeps everything else', () {
      final updated = original.copyWith(sellingPricePaise: 3800, stockQuantity: 20, syncStatus: 'pending');

      expect(updated.businessType, 'pharmacy');
      expect(updated.subUnitsPerPack, 15);
      expect(updated.hsnCode, '3004');
      expect(updated.isFavorite, true);
      expect(updated.barcode, '8901030123456');
      expect(updated.unit, 'strip');
      expect(updated.sellingPricePaise, 3800, reason: 'the field that was actually meant to change');
    });

    test('round-tripping through toMap/fromMap also preserves subUnitsPerPack', () {
      final restored = ProductModel.fromMap(original.toMap());
      expect(restored.subUnitsPerPack, 15);
      expect(restored.businessType, 'pharmacy');
    });

    test('a product with no known pack size round-trips subUnitsPerPack as null, not 0', () {
      final noPack = original.copyWith();
      final withoutPack = ProductModel(
        id: noPack.id,
        businessId: noPack.businessId,
        name: noPack.name,
        sellingPricePaise: noPack.sellingPricePaise,
        mrpPaise: noPack.mrpPaise,
        stockQuantity: noPack.stockQuantity,
        unit: noPack.unit,
      );
      final restored = ProductModel.fromMap(withoutPack.toMap());
      expect(restored.subUnitsPerPack, isNull);
    });
  });
}
