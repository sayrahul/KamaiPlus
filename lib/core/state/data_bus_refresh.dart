import 'package:flutter/widgets.dart';

/// Keeps a screen in step with data changed elsewhere in the app.
///
/// The dashboard tabs live inside a `PageView` and are built exactly once, so a screen
/// that loads in `initState` alone can never see a sale, stock change or khata entry made
/// on another tab. Mixing this in subscribes the screen to the relevant [AppDataBus]
/// counters and guarantees the listeners are removed on dispose.
///
/// Usage:
/// ```dart
/// class _MyScreenState extends State<MyScreen> with DataBusRefresh<MyScreen> {
///   @override
///   List<ValueNotifier<int>> get dataBusSignals => [
///         AppDataBus.instance.salesRevision,
///         AppDataBus.instance.productsRevision,
///       ];
///
///   @override
///   void onDataBusChanged() => _loadData();
/// }
/// ```
///
/// The subclass must call `super.initState()` and `super.dispose()` as usual.
mixin DataBusRefresh<T extends StatefulWidget> on State<T> {
  /// The counters this screen cares about.
  List<ValueNotifier<int>> get dataBusSignals;

  /// Called when any of [dataBusSignals] fires. Reload your data here.
  /// Only invoked while the screen is still mounted.
  void onDataBusChanged();

  late final List<ValueNotifier<int>> _subscribed;

  void _handleChange() {
    if (!mounted) return;
    onDataBusChanged();
  }

  @override
  void initState() {
    super.initState();
    // Captured once so dispose detaches from exactly what initState attached to,
    // even if the getter is rebuilt or returns a fresh list each call.
    _subscribed = List<ValueNotifier<int>>.unmodifiable(dataBusSignals);
    for (final signal in _subscribed) {
      signal.addListener(_handleChange);
    }
  }

  @override
  void dispose() {
    for (final signal in _subscribed) {
      signal.removeListener(_handleChange);
    }
    super.dispose();
  }
}
