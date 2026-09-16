import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/business_vertical_config.dart';
import '../core/database/local_database.dart';
import '../models/models.dart';
import 'firestore_sync_service.dart';

/// One line of a delivery being taken into stock.
///
/// Intentionally source-agnostic: an AI-scanned bill, a CSV import, a manual
/// purchase order and a barcode inward all describe the same thing, and all of
/// them must reach the database through [InventoryInwardService.applyInward].
class InwardLine {
  final String name;
  final double quantity;
  final String unit;
  final int purchasePricePaise;
  final int sellingPricePaise;
  final int mrpPaise;
  final String categoryName;

  /// Existing store SKU this line was matched to, when the caller already
  /// resolved one. Null means "create a new product".
  final ProductModel? matchedProduct;

  /// Master-catalog hit used to enrich a NEW product with a real barcode, tax
  /// rate and category. Ignored when [matchedProduct] is set.
  final MasterProductModel? matchedMasterProduct;

  /// Optional batch/expiry for verticals that track them (pharmacy).
  final String? batchNumber;
  final String? expiryDate;

  /// Barcode supplied by the SOURCE (a distributor's Excel/CSV column, or one
  /// read off a scanned invoice) rather than resolved from the master catalog.
  ///
  /// Kept separate from [matchedMasterProduct] because bulk import is the case
  /// the master catalog cannot serve: a merchant loading 1000 SKUs from their
  /// own supplier sheet has barcodes for items the catalog has never heard of,
  /// and without carrying them through, none of those products can be scanned
  /// at the counter afterwards — which is the entire reason to bulk import.
  final String? barcode;

  const InwardLine({
    required this.name,
    required this.quantity,
    this.unit = 'pcs',
    this.purchasePricePaise = 0,
    this.sellingPricePaise = 0,
    this.mrpPaise = 0,
    this.categoryName = 'General',
    this.matchedProduct,
    this.matchedMasterProduct,
    this.batchNumber,
    this.expiryDate,
    this.barcode,
  });
}

class InwardResult {
  final int createdCount;
  final int updatedCount;
  final int skippedCount;

  const InwardResult({
    this.createdCount = 0,
    this.updatedCount = 0,
    this.skippedCount = 0,
  });

  int get touchedCount => createdCount + updatedCount;
}

/// The ONE path by which a delivery becomes stock.
///
/// Before this existed, every inward screen carried its own copy of "look up the
/// product, add the quantity, write the row back, log a movement, push to the
/// cloud". Those copies drifted, and the drift was the bug:
///
///  * bill_scan_review_sheet.dart built new products with a raw
///    `ProductModel(...)` and never passed businessType, so every product a
///    non-grocery store created by scanning a bill was tagged 'grocery' — the
///    constructor default — and therefore invisible to that store, because
///    Products, Inventory and POS all read getAllProducts(businessType:). The
///    merchant saw stock they had just inwarded simply not appear.
///  * purchases_screen.dart wrote nothing at all: "Mark Inward Received" set a
///    field on an in-memory Map and showed a success toast.
///  * every copy did `old.stockQuantity + qty` against a ProductModel captured
///    when the screen opened, then a full-row REPLACE — so a sale rung up while
///    the sheet was open was silently reverted.
///
/// Centralising fixes all three at once and means the markup rule, the vertical
/// tag and the relative stock write can only ever be changed in one place.
class InventoryInwardService {
  InventoryInwardService._();

  static const _uuid = Uuid();

  /// Default retail markup over wholesale cost, applied only when a line gives
  /// no explicit selling price or MRP. These two numbers used to be duplicated
  /// verbatim in mlkit_ocr_service.dart, gemini_ai_service.dart and
  /// bill_scan_review_sheet.dart.
  static const double sellingMarkup = 1.15;
  static const double mrpMarkup = 1.20;

  static int defaultSellingPricePaise(int costPaise) =>
      costPaise > 0 ? (costPaise * sellingMarkup).round() : 0;

  static int defaultMrpPaise(int costPaise) =>
      costPaise > 0 ? (costPaise * mrpMarkup).round() : 0;

  /// Takes [lines] into stock, creating products that don't exist yet and
  /// incrementing the ones that do.
  ///
  /// [referenceId] is written onto each InventoryMovementModel so the Inventory
  /// audit trail can point back at the bill or purchase order.
  static Future<InwardResult> applyInward({
    required List<InwardLine> lines,
    String? supplierName,
    String? referenceId,
  }) async {
    final db = LocalDatabase.instance;
    final businessId = FirestoreSyncService.instance.activeBusinessId;

    // The store's own permanently-locked vertical. Every product created here
    // must carry it; omitting it is exactly the bug described above.
    final businessType = BusinessVerticals.activeBusinessTypeNotifier.value;

    final reference = (referenceId != null && referenceId.trim().isNotEmpty)
        ? referenceId.trim()
        : 'INWARD';

    var created = 0;
    var updated = 0;
    var skipped = 0;

    for (final line in lines) {
      final name = line.name.trim();
      if (name.isEmpty || line.quantity <= 0) {
        skipped++;
        continue;
      }

      try {
        if (line.matchedProduct != null) {
          final applied = await db.applyStockDelta(
            line.matchedProduct!.id,
            line.quantity,
            purchasePricePaise: line.purchasePricePaise,
            sellingPricePaise: line.sellingPricePaise,
            mrpPaise: line.mrpPaise,
          );

          // The product was deleted underneath us (cloud removal while this
          // sheet was open). Don't resurrect it from a stale in-memory copy.
          if (!applied.found) {
            skipped++;
            continue;
          }

          await db.recordInventoryMovement(InventoryMovementModel(
            id: _uuid.v4(),
            businessId: businessId,
            productId: line.matchedProduct!.id,
            productName: line.matchedProduct!.name,
            movementType: 'PURCHASE',
            quantity: line.quantity,
            previousStock: applied.previousStock,
            newStock: applied.newStock,
            referenceId: reference,
            createdAt: DateTime.now(),
          ));

          await _recordBatchIfTracked(line, line.matchedProduct!.id, businessId);

          // Push the row as it now stands in the database, never the stale
          // pre-inward copy the caller handed us.
          final fresh = await _reloadProduct(line.matchedProduct!.id);
          if (fresh != null) {
            unawaited(FirestoreSyncService.instance
                .pushProductToCloud(fresh)
                .catchError((_) {}));
          }
          updated++;
        } else {
          final master = line.matchedMasterProduct;
          final cost = line.purchasePricePaise;
          final newId = _uuid.v4();

          final newProduct = ProductModel(
            id: newId,
            businessId: businessId,
            name: name,
            // The source's own barcode wins over the master catalog's: it came
            // off this merchant's actual supplier sheet or invoice, so it is
            // the pack they will physically scan.
            barcode: (line.barcode?.trim().isNotEmpty ?? false)
                ? line.barcode!.trim()
                : master?.barcode,
            categoryId: (master != null && master.category.isNotEmpty)
                ? master.category
                : line.categoryName,
            purchasePricePaise: cost,
            sellingPricePaise: line.sellingPricePaise > 0
                ? line.sellingPricePaise
                : (master?.sellingPricePaise ?? defaultSellingPricePaise(cost)),
            mrpPaise: line.mrpPaise > 0
                ? line.mrpPaise
                : (master?.mrpPaise ?? defaultMrpPaise(cost)),
            stockQuantity: line.quantity,
            taxRate: master?.taxRate ?? 0.0,
            isTaxInclusive: true,
            unit: line.unit.isNotEmpty ? line.unit : (master?.unit ?? 'pcs'),
            batchNumber: line.batchNumber,
            expiryDate: line.expiryDate,
            // THE fix: without this the constructor default 'grocery' wins and
            // the product is invisible to every non-grocery store.
            businessType: businessType,
            syncStatus: 'pending',
          );

          await db.upsertProduct(newProduct);

          await db.recordInventoryMovement(InventoryMovementModel(
            id: _uuid.v4(),
            businessId: businessId,
            productId: newId,
            productName: name,
            movementType: 'PURCHASE',
            quantity: line.quantity,
            previousStock: 0.0,
            newStock: line.quantity,
            referenceId: reference,
            createdAt: DateTime.now(),
          ));

          await _recordBatchIfTracked(line, newId, businessId);

          unawaited(FirestoreSyncService.instance
              .pushProductToCloud(newProduct)
              .catchError((_) {}));
          created++;
        }
      } catch (e) {
        debugPrint('Inward line "$name" failed: $e');
        skipped++;
      }
    }

    final supplier = supplierName?.trim() ?? '';
    if (supplier.isNotEmpty) {
      try {
        await db.upsertSupplier(SupplierModel(
          id: 'sup_${supplier.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}',
          businessId: businessId,
          name: supplier,
          phone: '',
          category: 'Wholesale Supplier',
          currentBalancePaise: 0,
        ));
      } catch (e) {
        debugPrint('Supplier upsert notice: $e');
      }
    }

    return InwardResult(
      createdCount: created,
      updatedCount: updated,
      skippedCount: skipped,
    );
  }

  /// Records a real FEFO batch row when the line carries batch/expiry detail.
  /// Without this an AI-scanned delivery never reached product_batches, so the
  /// Inventory "Near Expiry" radar could not see it at all.
  static Future<void> _recordBatchIfTracked(
    InwardLine line,
    String productId,
    String businessId,
  ) async {
    final hasBatchDetail = (line.batchNumber?.trim().isNotEmpty ?? false) ||
        (line.expiryDate?.trim().isNotEmpty ?? false);
    if (!hasBatchDetail) return;

    await LocalDatabase.instance.addProductBatch(ProductBatchModel(
      id: _uuid.v4(),
      productId: productId,
      businessId: businessId,
      batchNumber: line.batchNumber?.trim().isNotEmpty == true
          ? line.batchNumber!.trim()
          : null,
      quantity: line.quantity,
      expiryDate: line.expiryDate?.trim().isNotEmpty == true
          ? line.expiryDate!.trim()
          : null,
      purchasePricePaise: line.purchasePricePaise,
      createdAt: DateTime.now(),
    ));
  }

  static Future<ProductModel?> _reloadProduct(String id) async {
    try {
      final all = await LocalDatabase.instance.getAllProducts();
      for (final p in all) {
        if (p.id == id) return p;
      }
    } catch (_) {}
    return null;
  }
}
