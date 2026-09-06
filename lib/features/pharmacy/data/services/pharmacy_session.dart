import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/network/auth_service.dart';
import '../../../../core/network/user_updates_service.dart';
import '../models/medicine_models.dart';
import 'pharmacy_catalogue_service.dart';

/// Live state for the pharmacy panel — real relational catalogue, incoming
/// orders (with delivery hand-off), inventory alerts and suppliers.
/// Polls every 4s and also re-fetches when an admin action pokes
/// [UserUpdatesService] (medicine approval, rider assignment, ...).
class PharmacySession extends ChangeNotifier {
  PharmacySession._() {
    AuthService.instance.addListener(_bootstrap);
    UserUpdatesService.instance.addRefreshHook(() {
      if (_pollTimer != null) refresh(silent: true);
    });
    _bootstrap();
  }
  static final PharmacySession instance = PharmacySession._();

  final _api = PharmacyCatalogueService.instance;

  PharmacyProfile profile = PharmacyProfile.empty;
  bool isLoading = false;
  bool _ready = false;
  bool get ready => _ready;
  String? errorMessage;
  Timer? _pollTimer;

  List<Medicine> _medicines = [];
  List<CatalogueOrder> _orders = [];
  List<Supplier> _suppliers = [];
  Map<String, List<ExpiryAlert>> _expiry = const {};
  InventorySummary summary = const InventorySummary();

  List<Medicine> get medicines => List.unmodifiable(_medicines);
  List<CatalogueOrder> get orders => List.unmodifiable(_orders);
  List<Supplier> get suppliers => List.unmodifiable(_suppliers);
  Map<String, List<ExpiryAlert>> get expiryAlerts => _expiry;

  // ── computed ─────────────────────────────────────────────────────────────
  int get totalProducts => _medicines.where((m) => m.isActive).length;
  int get lowStockCount => summary.lowStockCount;
  int get outOfStockCount => summary.outOfStockCount;
  int get expiringSoonCount => summary.expiringSoonCount;
  int get criticalExpiryCount => summary.criticalExpiryCount;
  int get pendingApprovalCount => summary.pendingApprovalCount;

  int get incomingOrderCount => _orders
      .where((o) => o.status == PharmacyOrderStatus.pending)
      .length;
  int get activeDeliveryCount => _orders
      .where((o) => o.status == PharmacyOrderStatus.outForDelivery ||
          o.status == PharmacyOrderStatus.readyForDelivery)
      .length;

  List<Medicine> get lowStockProducts => _medicines
      .where((m) => m.isActive && m.stockStatus != MedStock.inStock)
      .toList()
    ..sort((a, b) => a.stockQuantity.compareTo(b.stockQuantity));

  List<ExpiryAlert> get criticalAlerts => _expiry['critical'] ?? const [];

  List<CatalogueOrder> get recentOrders => List.of(_orders)
    ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

  List<CatalogueOrder> ordersFor(PharmacyOrderStatus? status) => status == null
      ? recentOrders
      : recentOrders.where((o) => o.status == status).toList();

  List<Medicine> filteredMedicines({String? category, String query = ''}) {
    final q = query.toLowerCase().trim();
    final list = _medicines.where((m) {
      if (category != null && m.category != category) return false;
      if (q.isNotEmpty &&
          !m.name.toLowerCase().contains(q) &&
          !m.genericName.toLowerCase().contains(q) &&
          !m.manufacturer.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
    list.sort((a, b) {
      final s = b.stockStatus.index.compareTo(a.stockStatus.index);
      return s != 0 ? s : a.name.compareTo(b.name);
    });
    return list;
  }

  // ── lifecycle ───────────────────────────────────────────────────────────
  Future<void> _bootstrap() async {
    final session = AuthService.instance.currentSession ??
        await AuthService.instance.getStoredSession();
    if (session == null || !session.user.roles.any((r) => r.toLowerCase() == 'pharmacy')) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    final u = session.user;
    profile = PharmacyProfile(
      name: u.profileValue('business_name', u.fullName),
      licenseNumber: u.profileValue('pharmacy_license_number'),
      location: u.profileValue('business_address', u.presentAddress),
      phone: u.phone,
    );
    notifyListeners();
    await refresh();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => refresh(silent: true));
  }

  Future<void> refresh({bool silent = false}) async {
    if (isLoading) return;
    isLoading = true;
    if (!silent) {
      errorMessage = null;
      notifyListeners();
    }
    try {
      final results = await Future.wait([
        _api.medicines(),
        _api.orders(),
        _api.inventorySummary(),
        _api.expiringSoon(),
        _api.suppliers(),
      ]);
      _medicines = results[0] as List<Medicine>;
      _orders = results[1] as List<CatalogueOrder>;
      summary = results[2] as InventorySummary;
      _expiry = results[3] as Map<String, List<ExpiryAlert>>;
      _suppliers = results[4] as List<Supplier>;
      errorMessage = null;
      _ready = true;
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // ── medicine actions ────────────────────────────────────────────────────
  Future<Medicine> addMedicine(Map<String, dynamic> body) async {
    final m = await _api.createMedicine(body);
    _medicines = [..._medicines, m];
    notifyListeners();
    unawaited(refresh(silent: true));
    return m;
  }

  Future<void> editMedicine(String id, Map<String, dynamic> body) async {
    final updated = await _api.updateMedicine(id, body);
    _replace(updated);
    unawaited(refresh(silent: true));
  }

  Future<void> deleteMedicine(String id) async {
    await _api.deleteMedicine(id);
    _medicines = _medicines.where((m) => m.id != id).toList();
    notifyListeners();
    unawaited(refresh(silent: true));
  }

  Future<void> adjustStock(String id, int delta) async =>
      _replace(await _api.setStock(id, delta: delta));

  Future<void> setStock(String id, int quantity) async =>
      _replace(await _api.setStock(id, quantity: quantity));

  Future<void> setPrice(String id, double price) async =>
      _replace(await _api.setPrice(id, price));

  Future<List<String>> uploadMedicineImage(
      String id, List<int> bytes, String filename) async {
    final data = await _api.uploadMedicineImage(id, bytes, filename);
    unawaited(refresh(silent: true));
    return (data['images'] as List? ?? const []).map((e) => e.toString()).toList();
  }

  Future<Map<String, dynamic>> bulkUpload(List<int> bytes, String filename) async {
    final data = await _api.bulkUpload(bytes, filename);
    await refresh(silent: true);
    return data;
  }

  void _replace(Medicine m) {
    _medicines = _medicines.map((x) => x.id == m.id ? m : x).toList();
    notifyListeners();
  }

  // ── order actions ───────────────────────────────────────────────────────
  Future<CatalogueOrder> confirmOrder(String id) => _afterOrder(_api.confirmOrder(id));
  Future<CatalogueOrder> readyForDelivery(String id) => _afterOrder(_api.readyForDelivery(id));
  Future<CatalogueOrder> cancelOrder(String id, String reason) =>
      _afterOrder(_api.cancelOrder(id, reason));
  Future<CatalogueOrder> markDelivered(String id, String message) => _afterOrder(
      _api.setOrderStatus(id, 'delivered', message: message, deliveryConfirmed: true));

  Future<CatalogueOrder> _afterOrder(Future<CatalogueOrder> future) async {
    final order = await future;
    _orders = _orders.map((o) => o.id == order.id ? order : o).toList();
    notifyListeners();
    unawaited(refresh(silent: true));
    return order;
  }

  // ── supplier actions ────────────────────────────────────────────────────
  Future<void> addSupplier(Map<String, dynamic> body) async {
    _suppliers = [..._suppliers, await _api.createSupplier(body)];
    notifyListeners();
  }

  Future<void> editSupplier(String id, Map<String, dynamic> body) async {
    final updated = await _api.updateSupplier(id, body);
    _suppliers = _suppliers.map((s) => s.id == id ? updated : s).toList();
    notifyListeners();
  }

  Future<void> deleteSupplier(String id) async {
    await _api.deleteSupplier(id);
    _suppliers = _suppliers.where((s) => s.id != id).toList();
    notifyListeners();
  }

  // ── expiry ──────────────────────────────────────────────────────────────
  Future<void> acknowledgeAlerts(List<String> ids) async {
    await _api.acknowledgeAlerts(ids);
    await refresh(silent: true);
  }
}
