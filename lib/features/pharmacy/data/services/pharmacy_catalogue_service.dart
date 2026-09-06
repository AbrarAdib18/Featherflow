import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/network/auth_service.dart';
import '../models/medicine_models.dart';

class PharmacyApiException implements Exception {
  final String message;
  const PharmacyApiException(this.message);
  @override
  String toString() => message;
}

/// Talks to the real relational catalogue endpoints under /api/pharmacy/.
class PharmacyCatalogueService {
  PharmacyCatalogueService._();
  static final instance = PharmacyCatalogueService._();

  // ── medicines ──────────────────────────────────────────────────────────
  Future<List<Medicine>> medicines({String? category, String? search}) async {
    final data = await _get('medicines/', query: {
      if (category != null) 'category': category,
      if (search != null && search.isNotEmpty) 'search': search,
    });
    return _list(data).map(Medicine.fromJson).toList();
  }

  Future<Medicine> createMedicine(Map<String, dynamic> body) async =>
      Medicine.fromJson(await _send('medicines/', 'POST', body));

  Future<Medicine> updateMedicine(String id, Map<String, dynamic> body) async =>
      Medicine.fromJson(await _send('medicines/$id/', 'PATCH', body));

  Future<void> deleteMedicine(String id) => _send('medicines/$id/', 'DELETE', null);

  Future<Medicine> setStock(String id, {int? quantity, int? delta}) async =>
      Medicine.fromJson(await _send('medicines/$id/stock/', 'PATCH', {
        if (quantity != null) 'stock_quantity': quantity,
        if (delta != null) 'delta': delta,
      }));

  Future<Medicine> setPrice(String id, double price) async =>
      Medicine.fromJson(await _send('medicines/$id/price/', 'PATCH', {'price': price}));

  Future<Map<String, dynamic>> uploadMedicineImage(
      String id, List<int> bytes, String filename) async {
    final data = await _multipart('medicines/$id/upload-image/', bytes, filename);
    return data;
  }

  Future<Map<String, dynamic>> bulkUpload(List<int> bytes, String filename) =>
      _multipart('medicines/bulk-upload/', bytes, filename);

  // ── inventory & expiry ─────────────────────────────────────────────────
  Future<InventorySummary> inventorySummary() async =>
      InventorySummary.fromJson(await _get('inventory/summary/'));

  Future<Map<String, List<ExpiryAlert>>> expiringSoon() async {
    final data = await _get('inventory/expiring-soon/');
    final grouped = (data['grouped'] as Map?)?.cast<String, dynamic>() ?? const {};
    return {
      for (final level in ['critical', 'warning', 'info'])
        level: (grouped[level] as List? ?? const [])
            .map((e) => ExpiryAlert.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
    };
  }

  Future<List<Medicine>> lowStock() async =>
      _list(await _get('inventory/low-stock/')).map(Medicine.fromJson).toList();

  Future<void> acknowledgeAlerts(List<String> alertIds) =>
      _send('inventory/alerts/acknowledge/', 'POST', {'alert_ids': alertIds});

  // ── suppliers ──────────────────────────────────────────────────────────
  Future<List<Supplier>> suppliers({String? search}) async => _list(await _get(
        'suppliers/',
        query: {if (search != null && search.isNotEmpty) 'search': search},
      )).map(Supplier.fromJson).toList();

  Future<Supplier> createSupplier(Map<String, dynamic> body) async =>
      Supplier.fromJson(await _send('suppliers/', 'POST', body));

  Future<Supplier> updateSupplier(String id, Map<String, dynamic> body) async =>
      Supplier.fromJson(await _send('suppliers/$id/', 'PATCH', body));

  Future<void> deleteSupplier(String id) => _send('suppliers/$id/', 'DELETE', null);

  // ── orders ─────────────────────────────────────────────────────────────
  Future<List<CatalogueOrder>> orders({String? status}) async => _list(await _get(
        'orders/',
        query: {if (status != null && status.isNotEmpty) 'status': status},
      )).map(CatalogueOrder.fromJson).toList();

  Future<CatalogueOrder> orderDetail(String id) async =>
      CatalogueOrder.fromJson(await _get('orders/$id/detail/'));

  Future<CatalogueOrder> confirmOrder(String id, {String message = ''}) async =>
      CatalogueOrder.fromJson(await _send('orders/$id/confirm/', 'POST', {'message': message}));

  Future<CatalogueOrder> cancelOrder(String id, String reason) async =>
      CatalogueOrder.fromJson(await _send('orders/$id/cancel/', 'POST', {'reason': reason}));

  Future<CatalogueOrder> readyForDelivery(String id) async =>
      CatalogueOrder.fromJson(await _send('orders/$id/ready-for-delivery/', 'POST', {}));

  Future<CatalogueOrder> setOrderStatus(String id, String status,
          {String message = '', bool deliveryConfirmed = false}) async =>
      CatalogueOrder.fromJson(await _send('orders/$id/status/', 'PATCH', {
        'status': status,
        'message': message,
        'delivery_confirmed': deliveryConfirmed,
      }));

  // ── analytics ──────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> salesAnalytics({String period = 'daily'}) =>
      _get('analytics/sales/', query: {'period': period});
  Future<List<Map<String, dynamic>>> topProducts() async =>
      _list(await _get('analytics/top-products/'));
  Future<Map<String, dynamic>> revenueAnalytics() => _get('analytics/revenue/');

  // ── transport ──────────────────────────────────────────────────────────
  Future<Map<String, String>> _headers() async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null || session.accessToken.isEmpty) {
      throw const PharmacyApiException('Pharmacy authentication is required.');
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse('${AuthService.instance.baseUrl}/api/pharmacy/$path');
    return (query == null || query.isEmpty) ? base : base.replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _get(String path, {Map<String, String>? query}) async {
    final r = await http.get(_uri(path, query), headers: await _headers());
    return _decode(r);
  }

  Future<Map<String, dynamic>> _send(
      String path, String method, Map<String, dynamic>? body) async {
    final headers = await _headers();
    final payload = jsonEncode(body ?? const {});
    final r = switch (method) {
      'POST' => await http.post(_uri(path), headers: headers, body: payload),
      'PATCH' => await http.patch(_uri(path), headers: headers, body: payload),
      'DELETE' => await http.delete(_uri(path), headers: headers),
      _ => await http.get(_uri(path), headers: headers),
    };
    return _decode(r);
  }

  Future<Map<String, dynamic>> _multipart(
      String path, List<int> bytes, String filename) async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null) throw const PharmacyApiException('Pharmacy authentication is required.');
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers['Authorization'] = 'Bearer ${session.accessToken}'
      ..files.add(http.MultipartFile.fromBytes('image', bytes, filename: filename));
    final r = await http.Response.fromStream(await request.send());
    return _decode(r);
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic> data) =>
      (data['results'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  Map<String, dynamic> _decode(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      var message = 'Pharmacy request failed (${r.statusCode}).';
      try {
        message = (jsonDecode(r.body) as Map)['detail']?.toString() ?? message;
      } catch (_) {}
      throw PharmacyApiException(message);
    }
    if (r.body.isEmpty) return {};
    final decoded = jsonDecode(r.body);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : {'results': decoded};
  }
}
