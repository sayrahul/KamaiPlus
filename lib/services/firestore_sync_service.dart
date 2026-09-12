import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../core/database/local_database.dart';

enum SyncState { synced, syncing, offline, error }

class FirestoreSyncService {
  static final FirestoreSyncService instance = FirestoreSyncService._init();
  FirestoreSyncService._init();

  final ValueNotifier<SyncState> syncState = ValueNotifier<SyncState>(SyncState.offline);
  final ValueNotifier<int> liveSyncCounter = ValueNotifier<int>(0);

  // Global Reactive Pro Notifiers (Immediately updates UI when Pro changes in Cloud/Admin)
  static final ValueNotifier<bool> isProNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<String> proPlanNotifier = ValueNotifier<String>('free');

  bool _isInitialized = false;
  String _activeBusinessId = 'biz_starter_pos';
  StreamSubscription? _productsSub;
  StreamSubscription? _customersSub;
  StreamSubscription? _businessSub;
  StreamSubscription? _broadcastSub;
  StreamSubscription? _globalConfigSub;

  final ValueNotifier<Map<String, dynamic>?> broadcastNotifier = ValueNotifier<Map<String, dynamic>?>(null);
  final ValueNotifier<Map<String, dynamic>?> globalConfigNotifier = ValueNotifier<Map<String, dynamic>?>(null);

  /// Admin kill-switch signal: flips true the moment an admin sets
  /// `account_disabled: true` on this business's Firestore doc (see
  /// admin_console's merchant_detail_screen.dart). `main.dart` listens for
  /// this at app startup and forces a sign-out + redirect to the login
  /// screen — this ValueNotifier only carries the signal, it never performs
  /// navigation itself (this services layer has no view/navigator access,
  /// deliberately, to avoid a services->views import cycle).
  final ValueNotifier<bool> accountDisabledNotifier = ValueNotifier<bool>(false);

  String get activeBusinessId => _activeBusinessId;

  /// Batch sync all pending local records (sales, store profile, etc.) to Cloud Firestore
  static Future<void> syncAllPending({String? businessId}) async {
    final service = FirestoreSyncService.instance;
    try {
      service.syncState.value = SyncState.syncing;

      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (businessId != null && businessId.isNotEmpty) {
        service._activeBusinessId = businessId;
      } else if (service._activeBusinessId == 'biz_starter_pos' && currentUid != null && currentUid.isNotEmpty) {
        service._activeBusinessId = 'biz_$currentUid';
      }

      if (!service._isInitialized) {
        await service.initialize(businessId: businessId);
      }

      final firestore = FirebaseFirestore.instance;
      final bizId = service.activeBusinessId;

      // 1. Sync Store Profile & FCM Device Token to businesses/{bizId}
      final profile = await LocalDatabase.instance.getStoreProfile();
      final prefs = await SharedPreferences.getInstance();
      final fcmToken = prefs.getString('fcm_token');

      // Check Cloud Firestore first so we NEVER overwrite an active Admin-granted Pro status!
      bool isProFromCloud = false;
      String cloudProPlan = '';
      String cloudProExpiry = '';
      try {
        final cloudDoc = await firestore.collection('businesses').doc(bizId).get();
        if (cloudDoc.exists) {
          final cd = cloudDoc.data();
          if (cd != null) {
            final isProCloud = (cd['is_pro'] == true ||
                cd['is_pro'] == 1 ||
                cd['subscription_tier'] == 'pro' ||
                cd['subscription_tier'] == 'annual' ||
                cd['subscription_tier'] == 'monthly');
            final rawExp = cd['pro_expiry']?.toString();
            final rawSubExp = cd['subscription_expires_at']?.toString();
            final rawValid = cd['subscription_valid_until']?.toString();
            final expStr = (rawExp != null && rawExp.isNotEmpty)
                ? rawExp
                : ((rawSubExp != null && rawSubExp.isNotEmpty)
                    ? rawSubExp
                    : ((rawValid != null && rawValid.isNotEmpty) ? rawValid : null));
            final expDate = expStr != null ? DateTime.tryParse(expStr) : null;
            if (isProCloud && (expDate == null || !DateTime.now().isAfter(expDate))) {
              isProFromCloud = true;
              cloudProPlan = cd['pro_plan']?.toString() ?? cd['subscription_tier']?.toString() ?? 'pro';
              cloudProExpiry = expStr ?? DateTime.now().add(const Duration(days: 365)).toIso8601String();
              await LocalDatabase.instance.activateProMembership(
                plan: cloudProPlan,
                paymentId: cd['razorpay_payment_id']?.toString() ?? 'admin_granted',
                expiryDate: expDate ?? DateTime.now().add(const Duration(days: 365)),
              );
              await prefs.setBool('is_pro', true);
              await prefs.setString('pro_plan', cloudProPlan);
              isProNotifier.value = true;
              proPlanNotifier.value = cloudProPlan;
            }
          }
        }
      } catch (_) {}

      final effectiveIsPro = isProFromCloud || profile.isProEffective;
      final effectivePlan = isProFromCloud ? cloudProPlan : (profile.proPlan.isNotEmpty ? profile.proPlan : 'pro');
      final effectiveExpiry = isProFromCloud ? cloudProExpiry : profile.proExpiry;

      final bizPayload = <String, dynamic>{
        'id': bizId,
        'business_id': bizId,
        'name': profile.storeName,
        'shop_name': profile.storeName,
        'business_name': profile.storeName,
        'store_name': profile.storeName,
        'tagline': profile.tagline,
        'owner_name': profile.ownerName,
        'owner_uid': currentUid ?? '',
        'phone': profile.phone,
        'email': profile.email,
        'upi_vpa': profile.upiVpa,
        'category': profile.category,
        'business_type': profile.businessType,
        'address': profile.address,
        'pincode': profile.pincode,
        'city': profile.pincode,
        'gstin': profile.gstin,
        'fssai': profile.fssai,
        'fcm_token': fcmToken,
        'last_synced_at': FieldValue.serverTimestamp(),
        'platform': 'android_native',
      };

      // Only push Pro subscription fields if merchant is Pro (protecting Admin grants)
      if (effectiveIsPro) {
        bizPayload['is_pro'] = true;
        bizPayload['pro_plan'] = effectivePlan;
        bizPayload['pro_expiry'] = effectiveExpiry;
        bizPayload['subscription_tier'] = effectivePlan;
        bizPayload['subscription_expires_at'] = effectiveExpiry;
        bizPayload['subscription_valid_until'] = effectiveExpiry;
        if (profile.razorpayPaymentId.isNotEmpty) {
          bizPayload['razorpay_payment_id'] = profile.razorpayPaymentId;
        }
      }

      await firestore.collection('businesses').doc(bizId).set(bizPayload, SetOptions(merge: true));

      // Also mirror to merchants collection for Admin Portal fast lookup (both by bizId and by owner UID)
      try {
        final merchantPayload = <String, dynamic>{
          'id': (currentUid != null && currentUid.isNotEmpty) ? currentUid : bizId,
          'uid': currentUid ?? '',
          'business_id': bizId,
          'name': profile.ownerName.isNotEmpty ? profile.ownerName : profile.storeName,
          'owner_name': profile.ownerName,
          'shop_name': profile.storeName,
          'phone': profile.phone,
          'email': profile.email,
          'role': 'admin',
          'createdAt': DateTime.now().toIso8601String(),
          'lastSyncedAt': DateTime.now().toIso8601String(),
          'updated_at': FieldValue.serverTimestamp(),
        };

        if (effectiveIsPro) {
          merchantPayload['is_pro'] = true;
          merchantPayload['subscription_tier'] = effectivePlan;
          merchantPayload['subscription_expires_at'] = effectiveExpiry;
        }

        if (currentUid != null && currentUid.isNotEmpty) {
          await firestore.collection('merchants').doc(currentUid).set(merchantPayload, SetOptions(merge: true));
        }
        await firestore.collection('merchants').doc(bizId).set(merchantPayload, SetOptions(merge: true));
      } catch (_) {}

      // 2. Sync all pending sales bills
      final pendingSales = await LocalDatabase.instance.getPendingSales(limit: 50);
      for (final sale in pendingSales) {
        await service.pushSaleToCloud(sale);
      }

      // 3. Dual-sync all store products to root catalog for admin panel
      try {
        final products = await LocalDatabase.instance.getAllProducts();
        for (final p in products) {
          await service.pushProductToCloud(p);
        }
      } catch (_) {}

      // 4. Dual-sync all customers to root collection for admin panel
      try {
        final customers = await LocalDatabase.instance.getAllCustomers();
        for (final c in customers) {
          await service.pushCustomerToCloud(c);
        }
      } catch (_) {}

      service.syncState.value = SyncState.synced;
      service.liveSyncCounter.value++;
      debugPrint('Cloud sync complete: ${pendingSales.length} pending sales pushed.');
    } catch (e) {
      debugPrint('Cloud sync error in syncAllPending: $e');
      service.syncState.value = SyncState.offline;
    }
  }

  /// Initialize Cloud Firestore connection and background listeners
  Future<void> initialize({String? businessId}) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (businessId != null && businessId.isNotEmpty) {
      _activeBusinessId = businessId;
    } else if (currentUid != null && currentUid.isNotEmpty) {
      _activeBusinessId = 'biz_$currentUid';
    }

    try {
      syncState.value = SyncState.syncing;

      // Initialize Firebase if not already initialized
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      _isInitialized = true;
      syncState.value = SyncState.synced;

      // Start Realtime Cloud Listeners
      _startLiveCloudListeners();

      // Initial cloud fetch in background
      initialCloudRestore();
    } catch (e) {
      debugPrint('Firebase sync initialization notice: $e');
      syncState.value = SyncState.offline;
    }
  }

  void _startLiveCloudListeners() {
    if (!_isInitialized) return;

    final firestore = FirebaseFirestore.instance;

    // 1. Live Products Stream: Counter changes on Desktop Web reflect here in real-time
    _productsSub?.cancel();
    _productsSub = firestore
        .collection('businesses')
        .doc(_activeBusinessId)
        .collection('products')
        .snapshots()
        .listen((snapshot) async {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.removed) {
          try {
            await LocalDatabase.instance.deleteProduct(change.doc.id);
          } catch (e) {
            debugPrint('Error deleting local product on cloud removal: $e');
          }
          continue;
        }

        if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
          final data = change.doc.data();
          if (data != null) {
            try {
              final product = ProductModel(
                id: change.doc.id,
                businessId: _activeBusinessId,
                name: data['name'] ?? 'Item',
                barcode: data['barcode']?.toString(),
                categoryId: data['category_id']?.toString(),
                sellingPricePaise: (data['selling_price_paise'] ?? ((data['price'] ?? 0) * 100)).toInt(),
                mrpPaise: (data['mrp_paise'] ?? ((data['mrp'] ?? 0) * 100)).toInt(),
                purchasePricePaise: (data['purchase_price_paise'] ?? 0).toInt(),
                stockQuantity: (data['stock_quantity'] ?? data['stock'] ?? 0.0).toDouble(),
                taxRate: (data['tax_rate'] ?? 0.0).toDouble(),
                isTaxInclusive: (data['is_tax_inclusive'] == true || data['is_tax_inclusive'] == 1),
                unit: data['unit'] ?? 'pcs',
                syncStatus: 'synced',
              );
              await LocalDatabase.instance.upsertProduct(product);
            } catch (e) {
              debugPrint('Error syncing cloud product: $e');
            }
          }
        }
      }
      liveSyncCounter.value++;
      syncState.value = SyncState.synced;
    }, onError: (err) {
      debugPrint('Live product stream error: $err');
      syncState.value = SyncState.offline;
    });

    // 2. Live Customers & Khata Balances Stream
    _customersSub?.cancel();
    _customersSub = firestore
        .collection('businesses')
        .doc(_activeBusinessId)
        .collection('customers')
        .snapshots()
        .listen((snapshot) async {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.removed) {
          try {
            await LocalDatabase.instance.deleteCustomer(change.doc.id);
          } catch (e) {
            debugPrint('Error deleting local customer on cloud removal: $e');
          }
          continue;
        }

        if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
          final data = change.doc.data();
          if (data != null) {
            try {
              final customer = CustomerModel(
                id: change.doc.id,
                businessId: _activeBusinessId,
                name: data['name'] ?? 'Customer',
                phone: data['phone'] ?? '',
                currentBalancePaise: (data['current_balance_paise'] ?? ((data['current_balance'] ?? 0) * 100)).toInt(),
                creditLimitPaise: (data['credit_limit_paise'] ?? 500000).toInt(),
                syncStatus: 'synced',
              );
              await LocalDatabase.instance.upsertCustomer(customer);
            } catch (e) {
              debugPrint('Error syncing cloud customer: $e');
            }
          }
        }
      }
      liveSyncCounter.value++;
    }, onError: (_) {});

    // 3. Live Business Profile Stream (Immediate Pro Upgrade / Downgrade sync from Admin Portal)
    _businessSub?.cancel();
    _businessSub = firestore
        .collection('businesses')
        .doc(_activeBusinessId)
        .snapshots()
        .listen((docSnap) async {
      if (docSnap.exists) {
        final d = docSnap.data();
        if (d != null) {
          accountDisabledNotifier.value = d['account_disabled'] == true;

          final isProCloud = (d['is_pro'] == true ||
              d['is_pro'] == 1 ||
              d['subscription_tier'] == 'pro' ||
              d['subscription_tier'] == 'annual' ||
              d['subscription_tier'] == 'monthly');

          final prefs = await SharedPreferences.getInstance();
          final currentIsPro = prefs.getBool('is_pro') ?? false;

          final plan = d['pro_plan']?.toString() ?? d['subscription_tier']?.toString() ?? 'annual';
          final paymentId = d['razorpay_payment_id']?.toString() ?? 'admin_granted';
          
          final rawExp = d['pro_expiry']?.toString();
          final rawSubExp = d['subscription_expires_at']?.toString();
          final rawValid = d['subscription_valid_until']?.toString();
          final expiryStr = (rawExp != null && rawExp.isNotEmpty)
              ? rawExp
              : ((rawSubExp != null && rawSubExp.isNotEmpty)
                  ? rawSubExp
                  : ((rawValid != null && rawValid.isNotEmpty) ? rawValid : null));
          final expiry = expiryStr != null ? DateTime.tryParse(expiryStr) : null;
          final isExpired = expiry != null && DateTime.now().isAfter(expiry);

          if (isProCloud && !isExpired) {
            await LocalDatabase.instance.activateProMembership(
              plan: plan,
              paymentId: paymentId,
              expiryDate: expiry ?? DateTime.now().add(const Duration(days: 365)),
            );
            await prefs.setBool('is_pro', true);
            await prefs.setString('pro_plan', plan);
            isProNotifier.value = true;
            proPlanNotifier.value = plan;
            debugPrint('Live sync: Pro membership active ($plan)');
          } else if (isExpired || (currentIsPro && (d['subscription_tier'] == 'free' || d['is_pro'] == false))) {
            // Revert / Downgrade to Free tier if expired or revoked by Super Admin
            await LocalDatabase.instance.deactivateProMembership();
            await prefs.setBool('is_pro', false);
            await prefs.remove('pro_plan');
            isProNotifier.value = false;
            proPlanNotifier.value = 'free';
            debugPrint('Live sync: Subscription expired or downgraded to Free');
          }
        }
      }
    }, onError: (e) {
      debugPrint('Live business stream error: $e');
    });

    // 4. Live Platform Broadcast Announcements from Admin WebApp
    _broadcastSub?.cancel();
    _broadcastSub = firestore
        .collection('platform_settings')
        .doc('broadcast')
        .snapshots()
        .listen((docSnap) {
      if (docSnap.exists && docSnap.data() != null) {
        final data = docSnap.data()!;
        final enabled = data['enabled'] == true;
        final expiresAtStr = data['expires_at']?.toString();
        final expiresAt = expiresAtStr != null ? DateTime.tryParse(expiresAtStr) : null;
        final isExpired = expiresAt != null && DateTime.now().isAfter(expiresAt);

        if (enabled && !isExpired && (data['message']?.toString().isNotEmpty ?? false)) {
          broadcastNotifier.value = data;
        } else {
          broadcastNotifier.value = null;
        }
      } else {
        broadcastNotifier.value = null;
      }
    }, onError: (_) {});

    // 5. Live Global Remote Config (Maintenance, Pricing & Versioning)
    _globalConfigSub?.cancel();
    _globalConfigSub = firestore
        .collection('platform_settings')
        .doc('global_config')
        .snapshots()
        .listen((docSnap) {
      if (docSnap.exists && docSnap.data() != null) {
        globalConfigNotifier.value = docSnap.data();
      }
    }, onError: (_) {});
  }

  /// Initial Cloud Catalog download
  Future<void> initialCloudRestore() async {
    if (!_isInitialized) return;
    try {
      syncState.value = SyncState.syncing;
      final firestore = FirebaseFirestore.instance;

      // 0. Fetch Business Profile & Verified Pro Status
      try {
        final bizDoc = await firestore.collection('businesses').doc(_activeBusinessId).get();
        if (bizDoc.exists) {
          final d = bizDoc.data();
          if (d != null) {
            final isProCloud = (d['is_pro'] == true ||
                d['is_pro'] == 1 ||
                d['subscription_tier'] == 'pro' ||
                d['subscription_tier'] == 'annual' ||
                d['subscription_tier'] == 'monthly');
            final prefs = await SharedPreferences.getInstance();

            final plan = d['pro_plan']?.toString() ?? d['subscription_tier']?.toString() ?? 'annual';
            final paymentId = d['razorpay_payment_id']?.toString() ?? 'cloud_verified';
            final expiryStr = (d['pro_expiry'] ?? d['subscription_expires_at'] ?? d['subscription_valid_until'])?.toString();
            final expiry = expiryStr != null ? DateTime.tryParse(expiryStr) : null;
            final isExpired = expiry != null && DateTime.now().isAfter(expiry);

            if (isProCloud && !isExpired) {
              await LocalDatabase.instance.activateProMembership(
                plan: plan,
                paymentId: paymentId,
                expiryDate: expiry ?? DateTime.now().add(const Duration(days: 365)),
              );
              await prefs.setBool('is_pro', true);
              await prefs.setString('pro_plan', plan);
            } else if (isExpired || d['subscription_tier'] == 'free' || d['is_pro'] == false) {
              await LocalDatabase.instance.deactivateProMembership();
              await prefs.setBool('is_pro', false);
              await prefs.remove('pro_plan');
            }
          }
        }
      } catch (e) {
        debugPrint('Cloud pro status check notice: $e');
      }

      // Fetch Categories
      final catSnap = await firestore
          .collection('businesses')
          .doc(_activeBusinessId)
          .collection('categories')
          .get();

      for (var doc in catSnap.docs) {
        final d = doc.data();
        await LocalDatabase.instance.upsertCategory(
          CategoryModel(id: doc.id, businessId: _activeBusinessId, name: d['name'] ?? 'Category'),
        );
      }

      // Fetch Products
      final prodSnap = await firestore
          .collection('businesses')
          .doc(_activeBusinessId)
          .collection('products')
          .get();

      for (var doc in prodSnap.docs) {
        final d = doc.data();
        await LocalDatabase.instance.upsertProduct(
          ProductModel(
            id: doc.id,
            businessId: _activeBusinessId,
            name: d['name'] ?? 'Item',
            barcode: d['barcode']?.toString(),
            categoryId: d['category_id']?.toString(),
            sellingPricePaise: (d['selling_price_paise'] ?? ((d['price'] ?? 0) * 100)).toInt(),
            mrpPaise: (d['mrp_paise'] ?? ((d['mrp'] ?? 0) * 100)).toInt(),
            purchasePricePaise: (d['purchase_price_paise'] ?? 0).toInt(),
            stockQuantity: (d['stock_quantity'] ?? d['stock'] ?? 0.0).toDouble(),
            taxRate: (d['tax_rate'] ?? 0.0).toDouble(),
            isTaxInclusive: (d['is_tax_inclusive'] == true || d['is_tax_inclusive'] == 1),
            unit: d['unit'] ?? 'pcs',
            syncStatus: 'synced',
          ),
        );
      }

      syncState.value = SyncState.synced;
      liveSyncCounter.value++;
    } catch (e) {
      debugPrint('Initial cloud restore error: $e');
      syncState.value = SyncState.offline;
    }
  }

  /// Pushes a completed sale to Cloud Firestore in the background
  Future<void> pushSaleToCloud(SaleModel sale) async {
    if (!_isInitialized) return;

    try {
      syncState.value = SyncState.syncing;
      final firestore = FirebaseFirestore.instance;

      final saleDocRef = firestore
          .collection('businesses')
          .doc(_activeBusinessId)
          .collection('sales')
          .doc(sale.id);

      await saleDocRef.set({
        'id': sale.id,
        'business_id': _activeBusinessId,
        'invoice_number': sale.invoiceNumber,
        'customer_id': sale.customerId,
        'customer_name': sale.customerName,
        'customer_phone': sale.customerPhone,
        'subtotal_paise': sale.subtotalPaise,
        'tax_amount_paise': sale.taxAmountPaise,
        'discount_paise': sale.discountPaise,
        'total_amount_paise': sale.totalAmountPaise,
        'total_amount': sale.totalAmountPaise / 100.0,
        'payment_method': sale.paymentMethod,
        'status': sale.status,
        'items': sale.items,
        'created_at': sale.createdAt.toIso8601String(),
        'timestamp': sale.createdAt.millisecondsSinceEpoch,
        'source': 'mobile_native_pos',
        'synced_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Dual-Sync: Pushes directly to Root 'sales' Collection for Web Admin Portal (kamaiplus.proventure.in/admin)
      try {
        await firestore.collection('sales').doc(sale.id).set({
          'id': sale.id,
          'business_id': _activeBusinessId,
          'invoice_number': sale.invoiceNumber,
          'customer_id': sale.customerId,
          'customer_name': sale.customerName ?? 'Cash Customer',
          'customer_phone': sale.customerPhone,
          'subtotal': sale.subtotalPaise,
          'subtotal_paise': sale.subtotalPaise,
          'tax_total': sale.taxAmountPaise,
          'tax_amount_paise': sale.taxAmountPaise,
          'discount_total': sale.discountPaise,
          'discount_paise': sale.discountPaise,
          'grand_total': sale.totalAmountPaise,
          'total_amount_paise': sale.totalAmountPaise,
          'total_amount': sale.totalAmountPaise / 100.0,
          'amount_received': sale.totalAmountPaise,
          'balance_due': 0,
          'change_returned': 0,
          'payment_method': sale.paymentMethod,
          'payment_status': 'paid',
          'status': sale.status,
          'created_by': 'owner',
          'items': sale.items,
          'created_at': sale.createdAt.toIso8601String(),
          'timestamp': sale.createdAt.millisecondsSinceEpoch,
          'source': 'mobile_native_pos',
          'sync_status': 'synced',
          'lastSyncedAt': DateTime.now().toIso8601String(),
          'synced_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}

      // Realtime aggregate sync for Admin Portal (kamaiplus.proventure.in/admin)
      try {
        final liveMetrics = {
          'last_sale_at': FieldValue.serverTimestamp(),
          'last_synced_at': FieldValue.serverTimestamp(),
          'total_sales_count': FieldValue.increment(1),
          'total_revenue_paise': FieldValue.increment(sale.totalAmountPaise),
        };
        firestore.collection('businesses').doc(_activeBusinessId).set(liveMetrics, SetOptions(merge: true)).catchError((_) {});
        firestore.collection('merchants').doc(_activeBusinessId).set(liveMetrics, SetOptions(merge: true)).catchError((_) {});
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        if (currentUid != null && currentUid.isNotEmpty) {
          firestore.collection('merchants').doc(currentUid).set(liveMetrics, SetOptions(merge: true)).catchError((_) {});
        }
      } catch (_) {}

      // Decrement stock in Firestore if not already refunded
      if (sale.status != 'refunded') {
        for (var item in sale.items) {
          final prodId = item['product_id'] ?? item['id'];
          final qty = (item['quantity'] ?? item['qty'] ?? 1.0).toDouble();
          if (prodId != null) {
            firestore
                .collection('businesses')
                .doc(_activeBusinessId)
                .collection('products')
                .doc(prodId)
                .update({
              'stock_quantity': FieldValue.increment(-qty),
            }).catchError((_) {});
            firestore
                .collection('products')
                .doc(prodId)
                .update({
              'current_stock': FieldValue.increment(-qty),
            }).catchError((_) {});
          }
        }
      }

      await LocalDatabase.instance.markSaleSynced(sale.id);
      syncState.value = SyncState.synced;
    } catch (e) {
      debugPrint('Cloud sale push notice (will retry later): $e');
      syncState.value = SyncState.offline;
    }
  }

  /// Push a single product to Cloud Firestore
  Future<void> pushProductToCloud(ProductModel product) async {
    if (!_isInitialized) return;
    try {
      final firestore = FirebaseFirestore.instance;
      final payload = {
        'id': product.id,
        'business_id': _activeBusinessId,
        'name': product.name,
        'barcode': product.barcode,
        'category_id': product.categoryId,
        'selling_price_paise': product.sellingPricePaise,
        'selling_price': product.sellingPricePaise,
        'mrp_paise': product.mrpPaise,
        'mrp': product.mrpPaise,
        'purchase_price_paise': product.purchasePricePaise,
        'purchase_price': product.purchasePricePaise,
        'stock_quantity': product.stockQuantity,
        'current_stock': product.stockQuantity,
        'tax_rate': product.taxRate,
        'is_tax_inclusive': product.isTaxInclusive,
        'unit': product.unit,
        'is_loose_item': product.isLooseItem,
        'is_active': true,
        'is_favorite': false,
        'batch_number': product.batchNumber,
        'expiry_date': product.expiryDate,
        'size': product.size,
        'color': product.color,
        'imei_serial': product.imeiSerial,
        'hsn_code': product.hsnCode,
        'sync_status': 'synced',
        'lastSyncedAt': DateTime.now().toIso8601String(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      await firestore
          .collection('businesses')
          .doc(_activeBusinessId)
          .collection('products')
          .doc(product.id)
          .set(payload, SetOptions(merge: true));

      // Dual-sync to root products collection for admin portal
      try {
        await firestore.collection('products').doc(product.id).set(payload, SetOptions(merge: true));
      } catch (_) {}
    } catch (e) {
      debugPrint('Cloud product push notice: $e');
    }
  }

  /// Delete a product from Cloud Firestore
  Future<void> deleteProductFromCloud(String productId) async {
    if (!_isInitialized) return;
    try {
      final firestore = FirebaseFirestore.instance;
      await firestore
          .collection('businesses')
          .doc(_activeBusinessId)
          .collection('products')
          .doc(productId)
          .delete();
      try {
        await firestore.collection('products').doc(productId).delete();
      } catch (_) {}
    } catch (e) {
      debugPrint('Cloud product delete notice: $e');
    }
  }

  /// Push customer to Cloud Firestore
  Future<void> pushCustomerToCloud(CustomerModel customer) async {
    if (!_isInitialized) return;
    try {
      final firestore = FirebaseFirestore.instance;
      final payload = {
        'id': customer.id,
        'business_id': _activeBusinessId,
        'name': customer.name,
        'phone': customer.phone,
        'address': customer.address ?? '',
        'current_balance': customer.currentBalancePaise,
        'current_balance_paise': customer.currentBalancePaise,
        'credit_limit_paise': customer.creditLimitPaise,
        'opening_balance': 0,
        'customer_type': customer.isVip ? 'vip' : (customer.currentBalancePaise > 0 ? 'credit' : 'regular'),
        'sync_status': 'synced',
        'lastSyncedAt': DateTime.now().toIso8601String(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      await firestore
          .collection('businesses')
          .doc(_activeBusinessId)
          .collection('customers')
          .doc(customer.id)
          .set(payload, SetOptions(merge: true));

      // Dual-sync to root customers collection for admin portal
      try {
        await firestore.collection('customers').doc(customer.id).set(payload, SetOptions(merge: true));
      } catch (_) {}
    } catch (e) {
      debugPrint('Cloud customer push notice: $e');
    }
  }

  /// Delete customer from Cloud Firestore
  Future<void> deleteCustomerFromCloud(String customerId) async {
    if (!_isInitialized) return;
    try {
      final firestore = FirebaseFirestore.instance;
      await firestore
          .collection('businesses')
          .doc(_activeBusinessId)
          .collection('customers')
          .doc(customerId)
          .delete();
      try {
        await firestore.collection('customers').doc(customerId).delete();
      } catch (_) {}
    } catch (e) {
      debugPrint('Cloud customer delete notice: $e');
    }
  }

  /// Wipe cloud catalog on Fresh Start / Factory Reset
  Future<void> wipeCloudData() async {
    if (!_isInitialized) return;
    try {
      syncState.value = SyncState.syncing;
      final firestore = FirebaseFirestore.instance;
      final bizRef = firestore.collection('businesses').doc(_activeBusinessId);

      final prods = await bizRef.collection('products').get();
      for (final doc in prods.docs) {
        await doc.reference.delete().catchError((_) {});
      }

      final sales = await bizRef.collection('sales').get();
      for (final doc in sales.docs) {
        await doc.reference.delete().catchError((_) {});
      }

      final custs = await bizRef.collection('customers').get();
      for (final doc in custs.docs) {
        await doc.reference.delete().catchError((_) {});
      }

      syncState.value = SyncState.synced;
      liveSyncCounter.value++;
    } catch (e) {
      debugPrint('Cloud wipe error: $e');
    }
  }

  void dispose() {
    _productsSub?.cancel();
    _customersSub?.cancel();
    _businessSub?.cancel();
    _broadcastSub?.cancel();
    _globalConfigSub?.cancel();
    _productsSub = null;
    _customersSub = null;
    _businessSub = null;
    _broadcastSub = null;
    _globalConfigSub = null;
    broadcastNotifier.value = null;
    globalConfigNotifier.value = null;
    accountDisabledNotifier.value = false;
    _isInitialized = false;
    _activeBusinessId = 'biz_starter_pos';
    syncState.value = SyncState.offline;
  }
}
