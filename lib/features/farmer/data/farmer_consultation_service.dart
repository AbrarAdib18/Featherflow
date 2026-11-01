import 'farm_management_service.dart';
import 'dart:typed_data';
import '../../../core/documents/prescription_pdf_viewer.dart';

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

  static Future<Map<String, dynamic>> videoRoom(String consultationId) =>
      FarmManagementService.get('consultations/$consultationId/video');

  static Future<Map<String, dynamic>> raiseDispute(
          String consultationId, String category, String description) =>
      FarmManagementService.post('consultations/disputes', {
        'consultation_id': consultationId,
        'category': category,
        'description': description,
      });

  static Future<Map<String, dynamic>> disputes() =>
      FarmManagementService.get('consultations/disputes');

  /// [clientMessageId] is the per-message idempotency key: generated once,
  /// reused on retry, so the server never stores the same send twice.
  static Future<Map<String, dynamic>> sendChat(
          String conversationId, String content,
          {required String clientMessageId}) =>
      FarmManagementService.post('consultations/chats/$conversationId', {
        'content': content,
        'client_message_id': clientMessageId,
      });

  static Future<Map<String, dynamic>> markChatRead(String conversationId) =>
      FarmManagementService.patch(
          'consultations/chats/$conversationId', const {});

  /// The prescription PDF from the protected endpoint (see
  /// core/documents/prescription_pdf_viewer.dart).
  static Future<Uint8List> prescriptionPdf(String prescriptionId) =>
      PrescriptionPdfService.fetch(prescriptionId);
}
