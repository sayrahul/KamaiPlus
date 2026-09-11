import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamaiplus_pos/core/state/app_data_bus.dart';
import 'package:kamaiplus_pos/core/state/data_bus_refresh.dart';

void main() {
  group('AppDataBus', () {
    setUp(() {
      AppDataBus.synchronousForTest = true;
      AppDataBus.instance.resetForTest();
    });

    tearDown(() {
      AppDataBus.synchronousForTest = false;
      AppDataBus.instance.resetForTest();
    });

    test('each bump notifies only its own listeners', () {
      var sales = 0;
      var products = 0;
      var customers = 0;
      var cash = 0;

      AppDataBus.instance.salesRevision.addListener(() => sales++);
      AppDataBus.instance.productsRevision.addListener(() => products++);
      AppDataBus.instance.customersRevision.addListener(() => customers++);
      AppDataBus.instance.cashRevision.addListener(() => cash++);

      AppDataBus.instance.bumpSales();

      expect(sales, 1);
      expect(products, 0, reason: 'a sales bump must not wake unrelated screens');
      expect(customers, 0);
      expect(cash, 0);
    });

    test('repeated bumps always fire (counter, not a flag)', () {
      var fired = 0;
      AppDataBus.instance.productsRevision.addListener(() => fired++);

      AppDataBus.instance.bumpProducts();
      AppDataBus.instance.bumpProducts();
      AppDataBus.instance.bumpProducts();

      expect(fired, 3, reason: 'ValueNotifier skips equal values; the counter must keep rising');
    });

    test('a cash sale wakes sales, products and cash but not khata', () {
      var sales = 0, products = 0, customers = 0, cash = 0;
      AppDataBus.instance.salesRevision.addListener(() => sales++);
      AppDataBus.instance.productsRevision.addListener(() => products++);
      AppDataBus.instance.customersRevision.addListener(() => customers++);
      AppDataBus.instance.cashRevision.addListener(() => cash++);

      AppDataBus.instance.bumpSaleCompleted(affectsCustomer: false, affectsCash: true);

      expect(sales, 1);
      expect(products, 1, reason: 'stock moved');
      expect(cash, 1, reason: 'money went into the drawer');
      expect(customers, 0, reason: 'no udhaar on a cash bill');
    });

    test('a credit sale wakes khata but not the cash drawer', () {
      var customers = 0, cash = 0;
      AppDataBus.instance.customersRevision.addListener(() => customers++);
      AppDataBus.instance.cashRevision.addListener(() => cash++);

      AppDataBus.instance.bumpSaleCompleted(affectsCustomer: true, affectsCash: false);

      expect(customers, 1);
      expect(cash, 0);
    });

    test('bumps are coalesced so a bulk write loop causes one reload', () async {
      AppDataBus.synchronousForTest = false;
      var fired = 0;
      AppDataBus.instance.productsRevision.addListener(() => fired++);

      // Simulates the Firestore restore / catalog seed loop.
      for (var i = 0; i < 200; i++) {
        AppDataBus.instance.bumpProducts();
      }

      expect(fired, 0, reason: 'nothing should fire while writes are still streaming in');

      await Future<void>.delayed(AppDataBus.coalesceWindow * 2);

      expect(fired, 1, reason: '200 writes must collapse into a single reload');
    });
  });

  group('DataBusRefresh mixin', () {
    setUp(() {
      AppDataBus.synchronousForTest = true;
      AppDataBus.instance.resetForTest();
    });

    tearDown(() {
      AppDataBus.synchronousForTest = false;
      AppDataBus.instance.resetForTest();
    });

    testWidgets('reloads on signal and detaches on dispose', (tester) async {
      await tester.pumpWidget(const _Harness(show: true));
      expect(_ProbeState.reloadCount, 0);

      AppDataBus.instance.bumpSales();
      expect(_ProbeState.reloadCount, 1);

      AppDataBus.instance.bumpSales();
      expect(_ProbeState.reloadCount, 2);

      // Remove the widget; its listener must be gone.
      await tester.pumpWidget(const _Harness(show: false));
      AppDataBus.instance.bumpSales();

      expect(
        _ProbeState.reloadCount,
        2,
        reason: 'a disposed screen must not keep reloading in the background',
      );
    });

    testWidgets('ignores signals it did not subscribe to', (tester) async {
      await tester.pumpWidget(const _Harness(show: true));

      AppDataBus.instance.bumpProducts();
      AppDataBus.instance.bumpCash();

      expect(_ProbeState.reloadCount, 0);
    });
  });
}

class _Harness extends StatelessWidget {
  const _Harness({required this.show});
  final bool show;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: show ? const _Probe() : const SizedBox.shrink(),
    );
  }
}

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with DataBusRefresh<_Probe> {
  static int reloadCount = 0;

  @override
  void initState() {
    reloadCount = 0;
    super.initState();
  }

  @override
  List<ValueNotifier<int>> get dataBusSignals => [AppDataBus.instance.salesRevision];

  @override
  void onDataBusChanged() => reloadCount++;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
