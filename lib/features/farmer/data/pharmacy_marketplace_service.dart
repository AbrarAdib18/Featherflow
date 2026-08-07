import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/auth_service.dart';

class MarketplaceMedicine {
  final Map<String, dynamic> data;
  const MarketplaceMedicine(this.data);
  String get id => data['id'].toString();
  String get name => data['name']?.toString() ?? '';
  String get pharmacyId => data['pharmacy_user_id'].toString();
  String get pharmacyName => data['pharmacy_name']?.toString() ?? '';
  String get manufacturer => data['manufacturer']?.toString() ?? '';
  String get unit => data['unit']?.toString() ?? 'piece';
  int get stock => (data['stock_count'] as num?)?.toInt() ?? 0;
  double get price => (data['price'] as num?)?.toDouble() ?? 0;
}

class PharmacyMarketplaceService {
  static Future<Map<String, String>> _headers() async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null) throw Exception('Please sign in to continue.');
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}'
    };
  }

  static Future<List<MarketplaceMedicine>> medicines() async {
    final response = await http.get(
        Uri.parse('${AuthService.instance.baseUrl}/api/pharmacy/marketplace/'),
        headers: await _headers());
    if (response.statusCode != 200) throw Exception(_message(response));
    final body = jsonDecode(response.body) as Map;
    return (body['results'] as List)
        .map((e) => MarketplaceMedicine(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<void> order(MarketplaceMedicine medicine, int quantity,
      String address, String notes) async {
    final response = await http.post(
        Uri.parse('${AuthService.instance.baseUrl}/api/pharmacy/place-order/'),
        headers: await _headers(),
        body: jsonEncode({
          'pharmacy_user_id': medicine.pharmacyId,
          'items': [
            {'product_id': medicine.id, 'quantity': quantity}
          ],
          'delivery_address': address,
          'notes': notes,
        }));
    if (response.statusCode != 201) throw Exception(_message(response));
  }

  static String _message(http.Response response) {
    try {
      return (jsonDecode(response.body) as Map)['detail']?.toString() ??
          'Request failed (${response.statusCode}).';
    } catch (_) {
      return 'Request failed (${response.statusCode}).';
    }
  }
}
