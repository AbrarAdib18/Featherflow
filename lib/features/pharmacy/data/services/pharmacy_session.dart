import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/network/auth_service.dart';
import '../models/pharmacy_models.dart';
import '../pharmacy_demo_data.dart';
import 'pharmacy_api_service.dart';

class PharmacySession extends ChangeNotifier {
  PharmacySession._() {
    AuthService.instance.addListener(_loadRegisteredProfile);
    _loadRegisteredProfile();
  }
  static final PharmacySession instance = PharmacySession._();

  PharmacyProfile profile = pharmacyProfile;
  bool isLoading = false;
  String? errorMessage;
  Timer? _pollTimer;

  Future<void> _loadRegisteredProfile() async {
    final session = AuthService.instance.currentSession ??
        await AuthService.instance.getStoredSession();
    if (session == null) {
      _pollTimer?.cancel();
      return;
    }
    final user = session.user;
    if (!user.roles.any((role) => role.toLowerCase() == 'pharmacy')) return;
    profile = PharmacyProfile(
      name: user.profileValue('business_name', user.fullName),
      licenseNumber: user.profileValue('pharmacy_license_number'),
      location: user.profileValue('business_address', user.presentAddress),
      phone: user.phone,
    );
    notifyListeners();
    await refresh();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
        const Duration(seconds: 4), (_) => refresh(silent: true));
  }

  final List<PharmacyProduct> _products = List.of(demoProducts);
  final List<PharmacyOrder> _orders = List.of(demoOrders);

  Future<void> refresh({bool silent = false}) async {
    if (isLoading) return;
    isLoading = true;
    errorMessage = null;
    if (!silent) notifyListeners();
    try {
      final data = await PharmacyApiService.instance.dashboard();
      profile = PharmacyProfile.fromJson(
          Map<String, dynamic>.from(data['profile'] as Map));
      _products
        ..clear()
        ..addAll((data['products'] as List).map((e) =>
            PharmacyProduct.fromJson(Map<String, dynamic>.from(e as Map))));
      _orders
        ..clear()
        ..addAll((data['orders'] as List).map((e) =>
            PharmacyOrder.fromJson(Map<String, dynamic>.from(e as Map))));
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  List<PharmacyProduct> get products => List.unmodifiable(_products);
  List<PharmacyOrder> get orders => List.unmodifiable(_orders);

  // ── Computed stats ────────────────────────────────────────────────────────

  int get pendingOrderCount =>
      _orders.where((o) => o.status == OrderStatus.pending).length;

  int get processingOrderCount =>
      _orders.where((o) => o.status == OrderStatus.processing).length;

  int get lowStockCount =>
      _products.where((p) => p.stockStatus == StockStatus.lowStock).length;

  int get outOfStockCount =>
      _products.where((p) => p.stockStatus == StockStatus.outOfStock).length;

  int get totalProducts => _products.length;

  double get todayRevenue => _orders
      .where((o) =>
          o.status == OrderStatus.delivered &&
          o.deliveredAt != null &&
          _isToday(o.deliveredAt!))
      .fold(0.0, (sum, o) => sum + o.totalAmount);

  double get totalRevenue => _orders
      .where((o) => o.status == OrderStatus.delivered)
      .fold(0.0, (sum, o) => sum + o.totalAmount);

  List<PharmacyProduct> get lowStockProducts => _products
      .where((p) =>
          p.stockStatus == StockStatus.lowStock ||
          p.stockStatus == StockStatus.outOfStock)
      .toList();

  List<PharmacyOrder> get recentOrders =>
      List.of(_orders)..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> updateOrderStatus(
      String orderId, OrderStatus newStatus, String message) async {
    final idx = _orders.indexWhere((o) => o.id == orderId);
    if (idx == -1) return;
    final original = _orders[idx];
    _orders[idx] = _orders[idx].copyWith(
      status: newStatus,
      deliveredAt: newStatus == OrderStatus.delivered ? DateTime.now() : null,
    );
    notifyListeners();
    try {
      final result = await PharmacyApiService.instance.updateOrder(orderId, {
        'status': newStatus.name,
        'status_message': message,
        'delivery_confirmed': newStatus == OrderStatus.delivered,
        'delivered_at': newStatus == OrderStatus.delivered
            ? DateTime.now().toIso8601String()
            : null,
      });
      _orders[idx] = PharmacyOrder.fromJson(result);
    } catch (error) {
      _orders[idx] = original;
      errorMessage = error.toString();
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  Future<void> updateStock(String productId, int newCount) async {
    final idx = _products.indexWhere((p) => p.id == productId);
    if (idx == -1) return;
    final original = _products[idx];
    _products[idx] = original.copyWith(stockCount: newCount);
    notifyListeners();
    try {
      final result = await PharmacyApiService.instance
          .updateProduct(productId, {'stock_count': newCount});
      _products[idx] = PharmacyProduct.fromJson(result);
    } catch (error) {
      _products[idx] = original;
      errorMessage = error.toString();
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  Future<void> adjustStock(String productId, int delta) async {
    final idx = _products.indexWhere((p) => p.id == productId);
    if (idx == -1) return;
    final original = _products[idx];
    final current = original.stockCount;
    final updated = (current + delta).clamp(0, 9999);
    _products[idx] = _products[idx].copyWith(stockCount: updated);
    notifyListeners();
    try {
      final result = await PharmacyApiService.instance
          .updateProduct(productId, {'stock_count': updated});
      _products[idx] = PharmacyProduct.fromJson(result);
    } catch (error) {
      _products[idx] = original;
      errorMessage = error.toString();
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  Future<void> addProduct(PharmacyProduct product) async {
    final result =
        await PharmacyApiService.instance.createProduct(product.toJson());
    _products.add(PharmacyProduct.fromJson(result));
    notifyListeners();
  }

  Future<void> editProduct(PharmacyProduct product) async {
    final idx = _products.indexWhere((p) => p.id == product.id);
    if (idx == -1) return;
    final result = await PharmacyApiService.instance
        .updateProduct(product.id, product.toJson());
    _products[idx] = PharmacyProduct.fromJson(result);
    notifyListeners();
  }

  Future<void> deleteProduct(String productId) async {
    await PharmacyApiService.instance.deleteProduct(productId);
    _products.removeWhere((p) => p.id == productId);
    notifyListeners();
  }

  List<PharmacyOrder> filteredOrders(OrderStatus? status) {
    if (status == null) return recentOrders;
    return _orders.where((o) => o.status == status).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<PharmacyProduct> filteredProducts({
    ProductCategory? category,
    String query = '',
  }) {
    var list = _products.where((p) {
      if (category != null && p.category != category) return false;
      if (query.isNotEmpty &&
          !p.name.toLowerCase().contains(query.toLowerCase()) &&
          !p.manufacturer.toLowerCase().contains(query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
    list.sort((a, b) {
      final sa = a.stockStatus.index;
      final sb = b.stockStatus.index;
      if (sa != sb) return sb.compareTo(sa);
      return a.name.compareTo(b.name);
    });
    return list;
  }

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }
}
