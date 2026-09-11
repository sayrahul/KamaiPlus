import 'dart:async';

import 'package:flutter/foundation.dart';

/// App-wide change signal for locally mutated data.
///
/// The dashboard builds its tabs once into a `PageView` (`home_dashboard_screen.dart`),
/// so a screen's `initState` never runs again after the first build. Without a shared
/// signal, a sale rung up on the Billing tab can never reach the Home, Khata, Products
/// or Cash Register tabs — they keep whatever they loaded at startup.
///
/// [LocalDatabase] bumps the relevant counter after a write commits; screens listen and
/// reload. Bumping in the data layer rather than in the UI means every caller of a
/// mutation is covered automatically, including ones added later.
///
/// Counters are used rather than booleans or objects because [ValueNotifier] skips
/// notification when the new value equals the old one — an incrementing `int` always fires.
///
/// Bumps are **coalesced** over a short window. Bulk paths (the Firestore restore loop,
/// catalog seeding, CSV inward) call `upsertProduct` hundreds of times in a row; without
/// coalescing each call would trigger a full reload on every listening screen.
class AppDataBus {
  static final AppDataBus instance = AppDataBus._();
  AppDataBus._();

  /// How long to gather bumps before notifying. Long enough to swallow a tight write
  /// loop, short enough that the counter feels instant to a cashier.
  static const Duration coalesceWindow = Duration(milliseconds: 120);

  /// Sales, invoices and anything derived from them (KPIs, GST turnover, Z-report).
  final ValueNotifier<int> salesRevision = ValueNotifier<int>(0);

  /// Catalog and stock levels.
  final ValueNotifier<int> productsRevision = ValueNotifier<int>(0);

  /// Customers and their khata (udhaar) balances.
  final ValueNotifier<int> customersRevision = ValueNotifier<int>(0);

  /// Cash drawer: expenses, shifts, and cash collected against udhaar.
  final ValueNotifier<int> cashRevision = ValueNotifier<int>(0);

  final Map<ValueNotifier<int>, Timer> _pending = {};

  /// Set to true in tests so bumps apply synchronously instead of after a timer.
  @visibleForTesting
  static bool synchronousForTest = false;

  void _bump(ValueNotifier<int> target) {
    if (synchronousForTest) {
      target.value++;
      return;
    }
    _pending[target]?.cancel();
    _pending[target] = Timer(coalesceWindow, () {
      _pending.remove(target);
      target.value++;
    });
  }

  void bumpSales() => _bump(salesRevision);
  void bumpProducts() => _bump(productsRevision);
  void bumpCustomers() => _bump(customersRevision);
  void bumpCash() => _bump(cashRevision);

  /// Convenience for a completed bill, which moves several things at once.
  void bumpSaleCompleted({bool affectsCustomer = false, bool affectsCash = false}) {
    bumpSales();
    bumpProducts();
    if (affectsCustomer) bumpCustomers();
    if (affectsCash) bumpCash();
  }

  /// Test-only: cancel pending timers and return every counter to zero so cases
  /// don't leak into each other.
  @visibleForTesting
  void resetForTest() {
    for (final t in _pending.values) {
      t.cancel();
    }
    _pending.clear();
    salesRevision.value = 0;
    productsRevision.value = 0;
    customersRevision.value = 0;
    cashRevision.value = 0;
  }
}
