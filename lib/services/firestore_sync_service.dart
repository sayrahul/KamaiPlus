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

  bool _isInitialized = false;
  String _activeBusinessId = 'biz_starter_pos';
  StreamSubscription? _productsSub;
  StreamSubscription? _customersSub;

  String get activeBusinessId => _activeBusinessId;

  /// Batch sync all pending local records (sales, store profile, etc.) to Cloud Firestore
  static Future<void> syncAllPending() async {
    final service = FirestoreSyncService.instance;
    try {
      service.syncState.value = SyncState.syncing;

      if (!service._isInitialized) {
        await service.initialize();
      }

      final firestore = FirebaseFirestore.instance;
      final bizId = service.activeBusinessId;

      // 1. Sync Store Profile & FCM Device Token to businesses/{bizId}
      final profile = await LocalDatabase.instance.getStoreProfile();
      final prefs = await SharedPreferences.getInstance();
      final fcmToken = prefs.getString('fcm_token');
      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

      await firestore.collection('businesses').doc(bizId).set({
        'id': bizId,
        'business_id': bizId,
        'name': profile.storeName,
        'shop_name': profile.storeName,
        'business_name': profile.storeName,
        'store_name': profile.storeName,
        'tagline': profile.tagline,
        'owner_name': profile.ownerName,
        'owner_uid': currentUid,
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
        'is_pro': profile.isPro,
        'pro_plan': profile.proPlan,
        'pro_expiry': profile.proExpiry,
        'subscription_tier': profile.isPro ? (profile.proPlan.isNotEmpty ? profile.proPlan : 'pro') : 'free',
        'subscription_expires_at': profile.proExpiry,
        'razorpay_payment_id': profile.razorpayPaymentId,
        'fcm_token': fcmToken,
        'last_synced_at': FieldValue.serverTimestamp(),
        'platform': 'android_native',
      }, SetOptions(merge: true));

      // Also mirror to merchants collection for Admin Portal fast lookup
      try {
        await firestore.collection('merchants').doc(bizId).set({
          'id': bizId,
          'business_id': bizId,
          'name': profile.storeName,
          'owner_name': profile.ownerName,
          'phone': profile.phone,
          'email': profile.email,
          'is_pro': profile.isPro,
          'subscription_tier': profile.isPro ? (profile.proPlan.isNotEmpty ? profile.proPlan : 'pro') : 'free',
          'subscription_expires_at': profile.proExpiry,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}

      // 2. Sync all pending sales bills
      final pendingSales = await LocalDatabase.instance.getPendingSales(limit: 50);
      for (final sale in pendingSales) {
        await service.pushSaleToCloud(sale);
      }

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
    if (businessId != null && businessId.isNotEmpty) {
      _activeBusinessId = businessId;
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
          if (d != null && (d['is_pro'] == true || d['is_pro'] == 1 || d['subscription_tier'] == 'pro' || d['subscription_tier'] == 'annual' || d['subscription_tier'] == 'monthly')) {
            final plan = d['pro_plan']?.toString() ?? d['subscription_tier']?.toString() ?? 'annual';
            final paymentId = d['razorpay_payment_id']?.toString() ?? 'cloud_verified';
            final expiryStr = (d['pro_expiry'] ?? d['subscription_expires_at'] ?? d['subscription_valid_until'])?.toString();
            final expiry = expiryStr != null ? DateTime.tryParse(expiryStr) : null;
            await LocalDatabase.instance.activateProMembership(
              plan: plan,
              paymentId: paymentId,
              expiryDate: expiry ?? DateTime.now().add(const Duration(days: 365)),
            );
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('is_pro', true);
            await prefs.setString('pro_plan', plan);
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
        'payment_method': sale.paymentMethod,
        'status': sale.status,
        'items': sale.items,
        'created_at': sale.createdAt.toIso8601String(),
        'source': 'mobile_native_pos',
        'synced_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

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
      await firestore
          .collection('businesses')
          .doc(_activeBusinessId)
          .collection('products')
          .doc(product.id)
          .set({
        'id': product.id,
        'business_id': _activeBusinessId,
        'name': product.name,
        'barcode': product.barcode,
        'category_id': product.categoryId,
        'selling_price_paise': product.sellingPricePaise,
        'mrp_paise': product.mrpPaise,
        'purchase_price_paise': product.purchasePricePaise,
        'stock_quantity': product.stockQuantity,
        'tax_rate': product.taxRate,
        'is_tax_inclusive': product.isTaxInclusive,
        'unit': product.unit,
        'is_loose_item': product.isLooseItem,
        'batch_number': product.batchNumber,
        'expiry_date': product.expiryDate,
        'size': product.size,
        'color': product.color,
        'imei_serial': product.imeiSerial,
        'hsn_code': product.hsnCode,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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
    } catch (e) {
      debugPrint('Cloud product delete notice: $e');
    }
  }

  /// Push customer to Cloud Firestore
  Future<void> pushCustomerToCloud(CustomerModel customer) async {
    if (!_isInitialized) return;
    try {
      final firestore = FirebaseFirestore.instance;
      await firestore
          .collection('businesses')
          .doc(_activeBusinessId)
          .collection('customers')
          .doc(customer.id)
          .set({
        'id': customer.id,
        'business_id': _activeBusinessId,
        'name': customer.name,
        'phone': customer.phone,
        'current_balance_paise': customer.currentBalancePaise,
        'credit_limit_paise': customer.creditLimitPaise,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Cloud customer push notice: $e');
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
  }
}
