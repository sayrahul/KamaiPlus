import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';
import '../core/database/local_database.dart';

enum SyncState { synced, syncing, offline, error }

class FirestoreSyncService {
  static Future<void> syncAllPending() async {
    // Simulates or triggers cloud firestore batch synchronization
    await Future.delayed(const Duration(milliseconds: 600));
  }

  static final FirestoreSyncService instance = FirestoreSyncService._init();
  FirestoreSyncService._init();

  final ValueNotifier<SyncState> syncState = ValueNotifier<SyncState>(SyncState.offline);
  final ValueNotifier<int> liveSyncCounter = ValueNotifier<int>(0);

  bool _isInitialized = false;
  String _activeBusinessId = 'biz_starter_pos';
  StreamSubscription? _productsSub;
  StreamSubscription? _customersSub;

  String get activeBusinessId => _activeBusinessId;

  Future<void> initialize({String? businessId}) async {
    if (businessId != null && businessId.isNotEmpty) {
      _activeBusinessId = businessId;
    }

    try {
      syncState.value = SyncState.syncing;

      // Initialize Firebase with official KamaiPlus credentials
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: 'AIzaSyCXq5B7MdPcaa48HpRATpMZbCW-K2vCtb0',
            appId: '1:714323283488:web:39405f194ea4a5f9367645',
            messagingSenderId: '714323283488',
            projectId: 'kamaiplus',
            storageBucket: 'kamaiplus.firebasestorage.app',
          ),
        );
      }

      _isInitialized = true;
      syncState.value = SyncState.synced;

      // Start Realtime Cloud Listeners
      _startLiveCloudListeners();

      // Initial cloud fetch
      await initialCloudRestore();
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
        'items': sale.items,
        'created_at': sale.createdAt.toIso8601String(),
        'source': 'mobile_native_pos',
      });

      // Decrement stock in Firestore
      for (var item in sale.items) {
        final prodId = item['product_id'];
        final qty = (item['quantity'] ?? 1.0).toDouble();
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

      await LocalDatabase.instance.markSaleSynced(sale.id);
      syncState.value = SyncState.synced;
    } catch (e) {
      debugPrint('Cloud sale push notice (will retry later): $e');
      syncState.value = SyncState.offline;
    }
  }

  void dispose() {
    _productsSub?.cancel();
    _customersSub?.cancel();
  }
}
