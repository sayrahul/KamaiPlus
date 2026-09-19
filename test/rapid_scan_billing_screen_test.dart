// POS Rapid Scan screen, driven end to end with a fake camera.
//
// mobile_scanner's platform layer is replaced by a fake whose barcode stream
// the test feeds, so these tests "show" packs to the real screen and check
// what lands in the bill: one scan per pack, quick quantity chips, the stock
// limit, undo, not-found handling, payment QRs ignored, and Checkout.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kamaiplus_pos/core/utils/scan_rules.dart';
import 'package:kamaiplus_pos/models/models.dart';
import 'package:kamaiplus_pos/views/pos/rapid_scan_billing_screen.dart';

import 'helpers/fake_scanner_platform.dart';

/// Stands in for PosBillingScreen's cart, applying the same stock rule.
class FakeCart {
  final Map<String, ProductModel> catalog = {
    '8901001': ProductModel(id: 'maggi', businessId: 'b', name: 'Maggi 70g', sellingPricePaise: 1400, mrpPaise: 1500, stockQuantity: 50),
    '8901002': ProductModel(id: 'oil', businessId: 'b', name: 'Fortune Oil 1L', sellingPricePaise: 18000, mrpPaise: 19000, stockQuantity: 3),
  };
  final Map<String, CartItemModel> items = {};
  final ValueNotifier<int> changes = ValueNotifier(0);
  final List<String> lookups = [];

  late final RapidScanBridge bridge = RapidScanBridge(
    billTitle: () => 'Bill #1',
    cartItems: () => items.values.toList(),
    totalPaise: () => items.values.fold(0, (s, i) => s + i.grossTotalPaise),
    addBarcode: (code) async {
      lookups.add(code);
      final p = catalog[code];
      if (p == null) return ScanAddResult(status: ScanAddStatus.notFound, message: 'Barcode "$code" not found in store catalog');
      final next = (items[p.id]?.quantity ?? 0) + 1;
      final err = stockErrorFor(p, next);
      if (err != null) return ScanAddResult(status: ScanAddStatus.blocked, message: err, product: p);
      items.putIfAbsent(p.id, () => CartItemModel(product: p, quantity: 0)).quantity = next;
      changes.value++;
      return ScanAddResult(status: ScanAddStatus.added, product: p, quantityNow: next, addedQuantity: 1);
    },
    setQuantity: (id, qty) {
      final item = items[id];
      if (item == null) return null;
      if (qty <= 0) {
        items.remove(id);
      } else {
        final err = stockErrorFor(item.product, qty);
        if (err != null) return err;
        item.quantity = qty;
      }
      changes.value++;
      return null;
    },
    restoreItem: (item) {
      items[item.product.id] = item;
      changes.value++;
    },
    cartChanges: changes,
  );

  double qty(String id) => items[id]?.quantity ?? 0;
}

void main() {
  late FakeScannerPlatform camera;
  late FakeCart cart;
  RapidScanExit? exit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    camera = FakeScannerPlatform();
    MobileScannerPlatform.instance = camera;
    cart = FakeCart();
    exit = null;
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => exit = await RapidScanBillingScreen.show(context, bridge: cart.bridge),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> show(WidgetTester tester, String code) async {
    camera.show(code);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Lets banner and notification timers run out before the test ends.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('each pack shown adds to the bill, once while it stays in view', (tester) async {
    await open(tester);
    await show(tester, '8901001');
    expect(cart.qty('maggi'), 1);
    expect(find.text('LAST SCANNED'), findsOneWidget);
    expect(find.text('Maggi 70g'), findsWidgets);

    // Same pack still in front of the camera: more frames, no more units.
    await show(tester, '8901001');
    await show(tester, '8901001');
    expect(cart.qty('maggi'), 1);

    // A different pack is picked up straight away.
    await show(tester, '8901002');
    expect(cart.qty('oil'), 1);

    // Maggi taken away and shown again → one more.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1000)));
    await show(tester, '8901001');
    expect(cart.qty('maggi'), 2);
    await settle(tester);
  });

  testWidgets('quick chips set the quantity; the stock limit still applies', (tester) async {
    await open(tester);
    await show(tester, '8901001');
    await tester.tap(find.text('×5'));
    await tester.pump();
    expect(cart.qty('maggi'), 5);

    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1000)));
    await show(tester, '8901002'); // oil: only 3 in stock
    await tester.tap(find.text('×5'));
    await tester.pump();
    expect(cart.qty('oil'), 1, reason: 'refused — only 3 in stock');
    expect(find.textContaining('Only 3 pcs'), findsOneWidget);

    await tester.tap(find.text('×3'));
    await tester.pump();
    expect(cart.qty('oil'), 3);
    await settle(tester);
  });

  testWidgets('undo takes back exactly the last scan', (tester) async {
    await open(tester);
    await show(tester, '8901001');
    expect(cart.qty('maggi'), 1);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(cart.items, isEmpty);
    await settle(tester);
  });

  testWidgets('unknown barcode is reported; payment QRs are never looked up', (tester) async {
    await open(tester);
    await show(tester, '0000111122223');
    expect(find.textContaining('not found in store catalog'), findsOneWidget);
    expect(cart.items, isEmpty);

    await show(tester, 'upi://pay?pa=shop@okaxis&pn=Shop');
    expect(cart.lookups, ['0000111122223'], reason: 'the UPI sticker near the counter is ignored');
    await settle(tester);
  });

  testWidgets('scans from a scanner gun show up live in the list', (tester) async {
    await open(tester);
    // PosBillingScreen bumps cartChanges when the USB/Bluetooth gun adds.
    cart.items['maggi'] = CartItemModel(product: cart.catalog['8901001']!, quantity: 4);
    cart.changes.value++;
    await tester.pump();
    expect(find.textContaining('BILL ITEMS (1)'), findsOneWidget);
    expect(find.text('₹56.00'), findsWidgets);
    await settle(tester);
  });

  testWidgets('Checkout returns to billing with the checkout request', (tester) async {
    await open(tester);
    await show(tester, '8901001');
    await tester.tap(find.text('Checkout'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(exit, RapidScanExit.checkout);
    expect(cart.qty('maggi'), 1, reason: 'the bill is kept for checkout');
    await settle(tester);
  });
}
