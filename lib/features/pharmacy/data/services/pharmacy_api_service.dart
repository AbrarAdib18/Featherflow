import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/network/auth_service.dart';

class PharmacyApiException implements Exception {
  final String message;
  const PharmacyApiException(this.message);
  @override
  String toString() => message;
}

class PharmacyApiService {
  PharmacyApiService._();
  static final instance = PharmacyApiService._();

  Future<Map<String, dynamic>> dashboard() => _request('dashboard/');
  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> body) =>
      _request('products/', method: 'POST', body: body);
  Future<Map<String, dynamic>> updateProduct(
          String id, Map<String, dynamic> body) =>
      _request('products/$id/', method: 'PATCH', body: body);
  Future<void> deleteProduct(String id) =>
      _request('products/$id/', method: 'DELETE');
  Future<Map<String, dynamic>> updateOrder(
          String id, Map<String, dynamic> body) =>
      _request('orders/$id/', method: 'PATCH', body: body);

  Future<Map<String, dynamic>> _request(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null || session.accessToken.isEmpty) {
      throw const PharmacyApiException('Pharmacy authentication is required.');
    }
    final uri = Uri.parse('${auth.baseUrl}/api/pharmacy/$path');
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}'
    };
    final response = switch (method) {
      'POST' => await http.post(uri,
          headers: headers, body: jsonEncode(body ?? const {})),
      'PATCH' => await http.patch(uri,
          headers: headers, body: jsonEncode(body ?? const {})),
      'DELETE' => await http.delete(uri, headers: headers),
      _ => await http.get(uri, headers: headers),
    };
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'Pharmacy request failed (${response.statusCode}).';
      try {
        message =
            (jsonDecode(response.body) as Map)['detail']?.toString() ?? message;
      } catch (_) {}
      throw PharmacyApiException(message);
    }
    return response.body.isEmpty
        ? {}
        : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }
}
