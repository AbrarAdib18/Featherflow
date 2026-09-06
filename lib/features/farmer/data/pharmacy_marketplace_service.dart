import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/auth_service.dart';

class MarketplaceException implements Exception {
  final String message;
  const MarketplaceException(this.message);
  @override
  String toString() => message;
}

class MarketMedicine {
  final Map<String, dynamic> data;
  const MarketMedicine(this.data);

  String get id => data['id'].toString();
  String get name => data['name']?.toString() ?? '';
  String get genericName => data['generic_name']?.toString() ?? '';
  String get manufacturer => data['manufacturer']?.toString() ?? '';
  String get category => data['category']?.toString() ?? 'other';
  String get unit => data['unit']?.toString() ?? 'piece';
  String get packSize => data['pack_size']?.toString() ?? '';
  String get description => data['description']?.toString() ?? '';
  String get dosageInstructions => data['dosage_instructions']?.toString() ?? '';
  String get storageInstructions => data['storage_instructions']?.toString() ?? '';
  double get price => (data['price'] as num?)?.toDouble() ?? 0;
  int get stock => (data['stock_quantity'] as num?)?.toInt() ?? 0;
  bool get prescriptionRequired => data['prescription_required'] == true;
  bool get coldChainRequired => data['cold_chain_required'] == true;
  List<String> get images =>
      (data['images'] as List? ?? const []).map((e) => e.toString()).toList();
  Map<String, dynamic> get pharmacy =>
      (data['pharmacy'] as Map?)?.cast<String, dynamic>() ?? const {};
  String get pharmacyId => pharmacy['id']?.toString() ?? '';
  String get pharmacyName => pharmacy['name']?.toString() ?? '';
}

class CartLine {
  final MarketMedicine medicine;
  int quantity;
  CartLine(this.medicine, this.quantity);
  double get subtotal => medicine.price * quantity;
}

class FarmerPharmacyService {
  static Future<Map<String, String>> _headers() async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null) throw const MarketplaceException('Please sign in to continue.');
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  static Uri _uri(String path, [Map<String, String>? q]) {
    final base = Uri.parse('${AuthService.instance.baseUrl}/api/farmers/$path');
    return (q == null || q.isEmpty) ? base : base.replace(queryParameters: q);
  }

  static Future<List<Map<String, dynamic>>> pharmacies() async {
    final r = await http.get(_uri('pharmacies/'), headers: await _headers());
    return _rows(r);
  }

  static Future<List<MarketMedicine>> search({
    String query = '',
    String? category,
    bool? prescriptionRequired,
    String? pharmacyId,
  }) async {
    final r = await http.get(
      _uri('medicines/search/', {
        if (query.isNotEmpty) 'query': query,
        if (category != null) 'category': category,
        if (prescriptionRequired != null)
          'prescription_required': '$prescriptionRequired',
        if (pharmacyId != null) 'pharmacy': pharmacyId,
      }),
      headers: await _headers(),
    );
    return _rows(r).map(MarketMedicine.new).toList();
  }

  static Future<MarketMedicine> medicineDetail(String id) async {
    final r = await http.get(_uri('medicines/$id/'), headers: await _headers());
    return MarketMedicine(_map(r));
  }

  static Future<String> uploadPrescription(List<int> bytes, String filename) async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null) throw const MarketplaceException('Please sign in to continue.');
    final request = http.MultipartRequest('POST', _uri('prescriptions/upload/'))
      ..headers['Authorization'] = 'Bearer ${session.accessToken}'
      ..files.add(http.MultipartFile.fromBytes('image', bytes, filename: filename));
    final r = await http.Response.fromStream(await request.send());
    return _map(r)['image_url']?.toString() ?? '';
  }

  static Future<Map<String, dynamic>> placeOrder({
    required String pharmacyId,
    required List<CartLine> cart,
    required String deliveryMethod,
    required String paymentMethod,
    String deliveryAddress = '',
    String? prescriptionImage,
    String notes = '',
  }) async {
    final r = await http.post(
      _uri('orders/'),
      headers: await _headers(),
      body: jsonEncode({
        'pharmacy_id': pharmacyId,
        'items': [
          for (final line in cart)
            {'medicine_id': line.medicine.id, 'quantity': line.quantity}
        ],
        'delivery_method': deliveryMethod,
        'payment_method': paymentMethod,
        'delivery_address': deliveryAddress,
        if (prescriptionImage != null) 'prescription_image': prescriptionImage,
        'notes': notes,
      }),
    );
    return _map(r);
  }

  static Future<List<Map<String, dynamic>>> myOrders() async {
    final r = await http.get(_uri('orders/'), headers: await _headers());
    return _rows(r);
  }

  static Future<Map<String, dynamic>> orderDetail(String id) async {
    final r = await http.get(_uri('orders/$id/'), headers: await _headers());
    return _map(r);
  }

  static Future<Map<String, dynamic>> cancelOrder(String id, String reason) async {
    final r = await http.post(_uri('orders/$id/cancel/'),
        headers: await _headers(), body: jsonEncode({'reason': reason}));
    return _map(r);
  }

  static Future<Map<String, dynamic>> payOrder(String id, String method) async {
    final r = await http.post(_uri('orders/$id/pay/'),
        headers: await _headers(), body: jsonEncode({'payment_method': method}));
    return _map(r);
  }

  // ── decode helpers ─────────────────────────────────────────────────────
  static Map<String, dynamic> _map(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) throw _err(r);
    return r.body.isEmpty ? {} : Map<String, dynamic>.from(jsonDecode(r.body) as Map);
  }

  static List<Map<String, dynamic>> _rows(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) throw _err(r);
    final body = jsonDecode(r.body);
    final list = body is Map ? (body['results'] as List? ?? const []) : (body as List);
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static MarketplaceException _err(http.Response r) {
    try {
      return MarketplaceException(
          (jsonDecode(r.body) as Map)['detail']?.toString() ?? 'Request failed (${r.statusCode}).');
    } catch (_) {
      return MarketplaceException('Request failed (${r.statusCode}).');
    }
  }
}
