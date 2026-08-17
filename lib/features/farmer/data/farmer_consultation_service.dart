import 'farm_management_service.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../../core/network/auth_service.dart';

class FarmerConsultationService {
  static Future<Map<String, dynamic>> list() =>
      FarmManagementService.get('consultations');
  static Future<Map<String, dynamic>> chats() =>
      FarmManagementService.get('consultations/chats');
  static Future<Map<String, dynamic>> clinicalResults(String consultationId) =>
      FarmManagementService.get(
          'consultations/$consultationId/clinical-results');
  static Future<Map<String, dynamic>> receipt(String consultationId) =>
      FarmManagementService.get('consultations/$consultationId/receipt');
  static Future<Map<String, dynamic>> markPaid(String consultationId) =>
      FarmManagementService.post(
          'consultations/$consultationId/mark-paid', const {});
  static Future<Map<String, dynamic>> action(String id, String action,
          {String reason = '', int? rating, String review = ''}) =>
      FarmManagementService.post('consultations/$id/action', {
        'action': action,
        'reason': reason,
        if (rating != null) 'rating': rating,
        if (review.isNotEmpty) 'review': review,
      });

  static Future<Uint8List> prescriptionPdf(String prescriptionId) async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null) throw AuthException('Please sign in again.');
    final uri = Uri.parse(
        '${auth.baseUrl}/api/consultations/prescriptions/$prescriptionId/pdf/');
    final response = await http.get(uri, headers: {
      'Accept': 'application/pdf',
      'Authorization': 'Bearer ${session.accessToken}',
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException('Unable to load this prescription PDF.');
    }
    if (response.headers['content-type']?.contains('application/pdf') != true) {
      throw AuthException('The server returned an invalid prescription file.');
    }
    return response.bodyBytes;
  }
}
