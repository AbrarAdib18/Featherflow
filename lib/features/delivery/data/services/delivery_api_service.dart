import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/network/auth_service.dart';
import '../models/delivery_order.dart';

class DeliveryApiService {
  static Future<Map<String, String>> _headers() async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null) {
      throw Exception('Delivery authentication is required.');
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}'
    };
  }

  static Future<List<DeliveryOrder>> pharmacyOrders() async {
    final response = await http.get(
        Uri.parse('${AuthService.instance.baseUrl}/api/delivery/orders/'),
        headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception('Could not load delivery orders.');
    }
    final rows = (jsonDecode(response.body) as Map)['results'] as List;
    return rows
        .where((raw) =>
            (raw as Map)['type'] == 'pharmacy' && raw['status'] == 'Pending')
        .map((raw) {
      final data = Map<String, dynamic>.from(raw as Map);
      final items = data['items'] is List ? data['items'] as List : const [];
      return DeliveryOrder(
        id: data['id'].toString(),
        pickupAddress:
            data['pickup']?.toString() ?? data['pharmacy']?.toString() ?? '',
        dropAddress: data['destination']?.toString() ?? '',
        customerName: data['customer']?.toString() ?? '',
        customerPhone: data['customer_phone']?.toString() ?? '',
        distanceKm: 0,
        type: OrderType.pharmacy,
        status: OrderStatus.pending,
        items: items.map((e) {
          final item = e as Map;
          return OrderItem(
              name: item['product_name']?.toString() ?? '',
              quantity: (item['quantity'] as num?)?.toInt() ?? 1);
        }).toList(),
        requiresOtp: true,
        earning: 100,
        createdAt: DateTime.now(),
      );
    }).toList();
  }

  static Future<void> status(String id, String status,
      {bool deliveryConfirmed = false}) async {
    final response = await http.patch(
        Uri.parse('${AuthService.instance.baseUrl}/api/delivery/orders/$id/'),
        headers: await _headers(),
        body: jsonEncode({
          'status': status,
          'delivery_confirmed': deliveryConfirmed,
        }));
    if (response.statusCode != 200) {
      throw Exception('Could not update delivery order.');
    }
  }
}
