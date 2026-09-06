import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/network/auth_service.dart';
import '../models/delivery_order.dart';

class DeliveryApiException implements Exception {
  final String message;
  const DeliveryApiException(this.message);

  @override
  String toString() => message;
}

class DeliveryApiService {
  static Future<Map<String, String>> _headers() async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null) {
      throw const DeliveryApiException('Delivery authentication is required.');
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  static Uri _uri(String path) =>
      Uri.parse('${AuthService.instance.baseUrl}/api/delivery/$path');

  static Future<Map<String, dynamic>> _get(String path) async {
    final response = await http.get(_uri(path), headers: await _headers());
    return _decode(response);
  }

  static Future<Map<String, dynamic>> _patch(
      String path, Map<String, dynamic> body) async {
    final response = await http.patch(_uri(path),
        headers: await _headers(), body: jsonEncode(body));
    return _decode(response);
  }

  static Future<Map<String, dynamic>> _uploadImage(
      String path, List<int> bytes, String filename) async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null) {
      throw const DeliveryApiException('Delivery authentication is required.');
    }
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers['Authorization'] = 'Bearer ${session.accessToken}'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return _decode(response);
  }

  static Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Delivery request failed (${response.statusCode}).';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['detail'] != null) {
          message = decoded['detail'].toString();
        }
      } catch (_) {}
      throw DeliveryApiException(message);
    }
    if (response.body.isEmpty) return {};
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  static Future<Map<String, dynamic>> dashboard() => _get('dashboard/');

  static Future<Map<String, dynamic>> setAvailability(
      {bool? isOnline, String? currentStatus}) {
    final body = <String, dynamic>{};
    if (isOnline != null) body['is_online'] = isOnline;
    if (currentStatus != null) body['current_status'] = currentStatus;
    return _patch('availability/', body);
  }

  static Future<List<DeliveryOrder>> requests() async {
    final data = await _get('requests/');
    final rows = (data['results'] as List? ?? const []);
    return rows
        .map((e) => DeliveryOrder.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<DeliveryOrder> respond(String orderId, bool accept) async {
    final data = await _patch(
        'requests/$orderId/respond/', {'action': accept ? 'accept' : 'reject'});
    return DeliveryOrder.fromJson(data);
  }

  static Future<List<DeliveryOrder>> orders(
      {String? status, int limit = 50, int offset = 0}) async {
    final query = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (status != null) 'status': status,
    };
    final path = 'orders/?${Uri(queryParameters: query).query}';
    final data = await _get(path);
    final rows = (data['results'] as List? ?? const []);
    return rows
        .map((e) => DeliveryOrder.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<DeliveryOrder> updateStatus(
    String orderId,
    OrderStatus status, {
    String? otpCode,
    String? proofOfDeliveryUrl,
    String? failureReason,
  }) async {
    final body = <String, dynamic>{'status': orderStatusToApi(status)};
    if (otpCode != null) body['otp_code'] = otpCode;
    if (proofOfDeliveryUrl != null) body['proof_of_delivery_url'] = proofOfDeliveryUrl;
    if (failureReason != null) body['failure_reason'] = failureReason;
    final data = await _patch('orders/$orderId/status/', body);
    return DeliveryOrder.fromJson(data);
  }

  static Future<Map<String, dynamic>> checkIn() => _patch('attendance/checkin/', {});

  static Future<Map<String, dynamic>> checkOut() => _patch('attendance/checkout/', {});

  static Future<void> pushLocation(double lat, double lng) =>
      _patch('location/', {'lat': lat, 'lng': lng});

  static Future<Map<String, dynamic>> route(String orderId) =>
      _get('orders/$orderId/route/');

  static Future<String> uploadProof(List<int> bytes, String filename) async {
    final data = await _uploadImage('proof-upload/', bytes, filename);
    return data['url']?.toString() ?? '';
  }

  static Future<List<Map<String, dynamic>>> attendanceHistory() async {
    final data = await _get('attendance/');
    return (data['records'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> earnings() => _get('earnings/');
}
