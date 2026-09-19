// The billing screen's barcode funnel, end to end: the real PosBillingScreen
// on a real (FFI) SQLite catalogue, fed the keystrokes a USB/Bluetooth
// scanner gun sends. The gun and the Rapid Scan camera share one funnel
// (`_addScannedBarcode` → `_addProductInteractive`), and grid taps use the
// same one, so this also covers the refactor that made them all awaitable.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kamaiplus_pos/core/constants/business_vertical_config.dart';
import 'package:kamaiplus_pos/core/database/local_database.dart';
import 'package:kamaiplus_pos/models/models.dart';
import 'package:kamaiplus_pos/views/pos/pos_billing_screen.dart';

import 'helpers/fake_scanner_platform.dart';

Future<void> gunScan(WidgetTester tester, String code) async {
  for (final ch in code.split('')) {
    final key = LogicalKeyboardKey(0x30 + int.parse(ch)); // digit keys
    await tester.sendKeyDownEvent(key, character: ch);
    await tester.sendKeyUpEvent(key);
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
}

Future<void> settleDb(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    PosBillingSessionStore.savedTabs = null;
    PosBillingSessionStore.activeTabIndex = 0;
    BusinessVerticals.updateActiveBusinessType('grocery');
  });

  Future<void> openBilling(WidgetTester tester, {double maggiStock = 5}) async {
    await tester.runAsync(() async {
      await LocalDatabase.instance.switchUser('pos_scan_test_${DateTime.now().microsecondsSinceEpoch}');
      await LocalDatabase.instance.saveStoreProfile(StoreProfileModel(storeName: 'Test Kirana', businessType: 'grocery'));
      await LocalDatabase.instance.upsertProduct(ProductModel(
        id: 'maggi',
        businessId: 'biz_test',
        name: 'Maggi Noodles 70g',
        barcode: '8901001',
        sellingPricePaise: 1400,
        mrpPaise: 1500,
        stockQuantity: maggiStock,
        businessType: 'grocery',
      ));
    });
    // A tablet-width surface: this test is about the scan funnel, and the
    // square test font overflows the existing product grid at phone width.
    // (Rapid Scan's own layout is checked at 360dp in its widget test.)
    tester.view.physicalSize = const Size(1600, 2560);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PosBillingScreen()));
    await settleDb(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(() => LocalDatabase.instance.closeDatabase());
  }

  testWidgets('a scanner-gun scan adds the item; a second scan adds one more', (tester) async {
    await openBilling(tester);
    await gunScan(tester, '8901001');
    await settleDb(tester);
    expect(find.text('Bill #1 • 1 items'), findsOneWidget);
    expect(find.text('₹14.00'), findsOneWidget);

    await gunScan(tester, '8901001');
    await settleDb(tester);
    expect(find.text('Bill #1 • 2 items'), findsOneWidget);
    expect(find.text('₹28.00'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the stock limit refuses a scan beyond what is on hand', (tester) async {
    await openBilling(tester, maggiStock: 1);
    await gunScan(tester, '8901001');
    await settleDb(tester);
    await gunScan(tester, '8901001');
    await settleDb(tester);
    expect(find.text('Bill #1 • 1 items'), findsOneWidget, reason: 'only 1 in stock');
    expect(find.textContaining('Only 1 pcs'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('an unknown barcode adds nothing and says so', (tester) async {
    await openBilling(tester);
    await gunScan(tester, '7770001');
    await settleDb(tester);
    expect(find.textContaining('not found in store catalog'), findsOneWidget);
    expect(find.text('Bill #1 • 0 items'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Rapid Scan from the billing screen fills the real bill', (tester) async {
    final camera = FakeScannerPlatform();
    MobileScannerPlatform.instance = camera;
    await openBilling(tester);

    await tester.tap(find.byIcon(Icons.barcode_reader));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Rapid Scan • Bill #1'), findsOneWidget);

    camera.show('8901001');
    await settleDb(tester);
    expect(find.text('LAST SCANNED'), findsOneWidget);

    await tester.tap(find.text('×3'));
    await tester.pump();

    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Bill #1 • 3 items'), findsOneWidget, reason: 'scan + quick qty landed in the POS cart');
    expect(find.text('₹42.00'), findsWidgets);
    await finish(tester);
  });

  testWidgets('the POS search row shows the Rapid Scan barcode button', (tester) async {
    await openBilling(tester);
    expect(find.byIcon(Icons.barcode_reader), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
    await finish(tester);
  });
}
