import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/admin_models.dart';

/// Every collection the admin console touches, in one typed place — so a
/// screen never builds a raw `.collection('...')` path itself. Matches the
/// exact collections `firestore_sync_service.dart` (in the POS app) already
/// writes: root `businesses`, `merchants`, `sales`, `products`, `customers`
/// (dual-synced there specifically "for Web Admin Portal"), plus
/// `platform_settings` and `coupons`, which this console is the *only*
/// writer of — the app only ever reads them.
class AdminFirestoreService {
  AdminFirestoreService._();
  static final AdminFirestoreService instance = AdminFirestoreService._();

  final _db = FirebaseFirestore.instance;

  // ---------------------------------------------------------------------
  // Admin gate
  // ---------------------------------------------------------------------

  /// True only if `admins/{currentUid}` exists — the sole source of admin
  /// power (see firestore.rules' `isAdmin()`). This is a genuine server-side
  /// check (the read itself fails for a non-admin under the deployed rules,
  /// which only let a user read their own admin doc), not just a
  /// client-side flag the UI trusts blindly. Live (not a one-time Future) so
  /// AuthGate can drop a revoked admin (their admins/{uid} doc deleted
  /// mid-session) immediately instead of only on their next sign-in or page
  /// reload — every actual Firestore read/write this console makes is
  /// already independently re-checked server-side by firestore.rules
  /// regardless of this stream, so this closes a UI-staleness gap, not a
  /// security one.
  Stream<bool> watchCurrentUserIsAdmin() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(false);
    return _db.collection('admins').doc(uid).snapshots().map((doc) => doc.exists).handleError((_) => false);
  }


  // ---------------------------------------------------------------------
  // Merchant directory
  // ---------------------------------------------------------------------

  Stream<List<AdminBusiness>> watchBusinesses() {
    return _db.collection('businesses').snapshots().map(
          (snap) => snap.docs.map((d) => AdminBusiness.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => (b.lastSaleAt ?? DateTime(2000)).compareTo(a.lastSaleAt ?? DateTime(2000))),
        );
  }

  Future<AdminBusiness?> getBusiness(String businessId) async {
    final doc = await _db.collection('businesses').doc(businessId).get();
    if (!doc.exists) return null;
    return AdminBusiness.fromMap(doc.id, doc.data()!);
  }

  /// Every business whose Pro purchase used [code] — surfaced on the
  /// Coupons screen as a usage count. A single-field equality query, no
  /// composite index needed.
  Future<List<AdminBusiness>> getBusinessesUsingCoupon(String code) async {
    final snap = await _db.collection('businesses').where('coupon_code_used', isEqualTo: code.toUpperCase()).get();
    return snap.docs.map((d) => AdminBusiness.fromMap(d.id, d.data())).toList();
  }

  /// Day-by-day revenue across every merchant for the last [days] days, for
  /// the Dashboard trend chart. A single-field range query on `timestamp`
  /// (root `sales`, no `business_id` filter) — no composite index needed,
  /// unlike `getSalesForBusiness`'s per-merchant query. Returns a map keyed
  /// by a `yyyy-MM-dd` date string (UTC-independent, uses each sale's local
  /// `createdAt`) so a day with zero sales is simply absent — the caller
  /// fills gaps when building the chart's x-axis.
  Future<Map<String, int>> getDailyRevenueTrend({int days = 14}) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final snap = await _db.collection('sales').where('timestamp', isGreaterThanOrEqualTo: since.millisecondsSinceEpoch).get();
    final byDay = <String, int>{};
    for (final doc in snap.docs) {
      final sale = AdminSale.fromMap(doc.id, doc.data());
      final date = sale.createdAt;
      if (date == null) continue;
      final key = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      byDay[key] = (byDay[key] ?? 0) + sale.totalAmountPaise;
    }
    return byDay;
  }

  /// Grants or revokes Pro for a business. Writes the exact field set
  /// `firestore_sync_service.dart`'s live "Business Profile Stream" already
  /// listens for — the merchant's app reflects this within seconds, no
  /// app update or manual sync needed on their end.
  Future<void> setProStatus(
    String businessId, {
    required bool isPro,
    String plan = 'annual',
    DateTime? expiry,
  }) async {
    final data = <String, dynamic>{'is_pro': isPro};
    if (isPro) {
      final exp = expiry ?? DateTime.now().add(const Duration(days: 365));
      data['pro_plan'] = plan;
      data['pro_expiry'] = exp.toIso8601String();
      data['subscription_tier'] = plan;
      data['subscription_expires_at'] = exp.toIso8601String();
      data['subscription_valid_until'] = exp.toIso8601String();
      data['razorpay_payment_id'] = 'admin_granted';
    }
    await _db.collection('businesses').doc(businessId).set(data, SetOptions(merge: true));
  }

  /// Admin kill-switch. Writes `account_disabled` on the business doc,
  /// which `firestore_sync_service.dart`'s live "Business Profile Stream"
  /// (the mobile app's own real-time listener, already open for Pro status)
  /// also checks — when true, the merchant is signed out and blocked from
  /// re-entry within seconds. Reversible: pass `disabled: false` to re-admit
  /// them without any data loss, unlike deleting the business doc outright.
  Future<void> setAccountDisabled(String businessId, bool disabled) async {
    await _db.collection('businesses').doc(businessId).set(
      {'account_disabled': disabled},
      SetOptions(merge: true),
    );
  }

  // ---------------------------------------------------------------------
  // Merchant detail — sales / products / customers for one business
  // ---------------------------------------------------------------------

  /// Sorted client-side after fetching rather than via a server-side
  /// `.orderBy('timestamp')` chained onto the `business_id` filter —
  /// deliberately, to avoid needing a Firestore composite index deployed
  /// before this screen works. Fine at this scale (one merchant's sales,
  /// capped at [limit]); revisit if a merchant's sale count grows large
  /// enough that fetching-then-sorting becomes the bottleneck.
  Future<List<AdminSale>> getSalesForBusiness(String businessId, {int limit = 200}) async {
    final snap = await _db.collection('sales').where('business_id', isEqualTo: businessId).limit(limit).get();
    final sales = snap.docs.map((d) => AdminSale.fromMap(d.id, d.data())).toList();
    sales.sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
    return sales;
  }

  Future<List<AdminProduct>> getProductsForBusiness(String businessId) async {
    final snap = await _db.collection('products').where('business_id', isEqualTo: businessId).get();
    return snap.docs.map((d) => AdminProduct.fromMap(d.id, d.data())).toList();
  }

  Future<List<AdminCustomer>> getCustomersForBusiness(String businessId) async {
    final snap = await _db.collection('customers').where('business_id', isEqualTo: businessId).get();
    return snap.docs.map((d) => AdminCustomer.fromMap(d.id, d.data())).toList();
  }

  // ---------------------------------------------------------------------
  // Coupons
  // ---------------------------------------------------------------------

  Stream<List<AdminCoupon>> watchCoupons() {
    return _db.collection('coupons').snapshots().map(
          (snap) => snap.docs.map((d) => AdminCoupon.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => a.code.compareTo(b.code)),
        );
  }

  Future<void> upsertCoupon(AdminCoupon coupon) async {
    await _db.collection('coupons').doc(coupon.code.toUpperCase()).set(coupon.toMap());
  }

  Future<void> deleteCoupon(String code) async {
    await _db.collection('coupons').doc(code.toUpperCase()).delete();
  }

  // ---------------------------------------------------------------------
  // Platform settings — broadcast banner + remote config, read live by
  // every merchant's app (FirestoreSyncService already listens on both).
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>?> getBroadcast() async {
    final doc = await _db.collection('platform_settings').doc('broadcast').get();
    return doc.data();
  }

  Future<void> setBroadcast({required String message, required bool active, String? actionUrl}) async {
    await _db.collection('platform_settings').doc('broadcast').set({
      'message': message,
      'active': active,
      'action_url': actionUrl,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> clearBroadcast() async {
    await _db.collection('platform_settings').doc('broadcast').set({
      'active': false,
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> getGlobalConfig() async {
    final doc = await _db.collection('platform_settings').doc('global_config').get();
    return doc.data();
  }

  /// Full replace (no merge) — this console is the sole writer of
  /// `global_config` (the app only ever listens), and the admin screen is a
  /// generic key/value editor showing the whole doc at once, so "remove a
  /// row then save" must actually remove that key rather than leaving it
  /// behind, which `SetOptions(merge: true)` would do. Stamps `updated_at`
  /// the same way [setBroadcast] does, so the editor can show "last saved".
  Future<void> setGlobalConfig(Map<String, dynamic> data) async {
    await _db.collection('platform_settings').doc('global_config').set({
      ...data,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }
}
