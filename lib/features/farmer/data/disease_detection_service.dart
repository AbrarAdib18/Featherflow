import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../../../core/network/auth_service.dart';

/// One class the model ranked for an image.
class DiseasePrediction {
  final String disease;
  final double confidence;
  const DiseasePrediction(this.disease, this.confidence);
}

/// A completed (or historical) disease-detection result.
class DiseaseResult {
  final Map<String, dynamic> raw;
  const DiseaseResult(this.raw);

  String get scanId => raw['scan_id']?.toString() ?? '';
  String get disease => raw['disease']?.toString() ?? 'Unknown';
  bool get isHealthy => raw['is_healthy'] == true;
  bool get uncertain => raw['uncertain'] == true;
  double get confidence => (raw['confidence'] as num?)?.toDouble() ?? 0;
  String? get severity => raw['severity']?.toString();
  bool get requiresImmediateVet => raw['requires_immediate_vet'] == true;
  bool get notifiable => raw['notifiable'] == true;
  String get urgency => raw['urgency']?.toString() ?? 'routine';
  String get description => raw['description']?.toString() ?? '';
  String? get imageUrl => raw['image_url']?.toString();
  String? get diseaseRefId => raw['disease_ref_id']?.toString();
  String get disclaimer => raw['disclaimer']?.toString() ?? '';
  String? get createdAt => raw['created_at']?.toString();
  String? get status => raw['status']?.toString();

  List<String> get symptoms => _list('symptoms');
  List<String> get recommendations => _list('recommendations');
  List<String> get avoid => _list('avoid');
  List<String> get prevention => _list('prevention');

  List<DiseasePrediction> get allPredictions =>
      ((raw['all_predictions'] as List?) ?? const [])
          .map((e) => DiseasePrediction(
              e['disease']?.toString() ?? '',
              (e['confidence'] as num?)?.toDouble() ?? 0))
          .toList();

  List<String> _list(String key) =>
      ((raw[key] as List?) ?? const []).map((e) => e.toString()).toList();
}

class DiseaseDetectionException implements Exception {
  final String message;
  const DiseaseDetectionException(this.message);
  @override
  String toString() => message;
}

class DiseaseDetectionService {
  static MediaType _mediaType(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    return MediaType('image', switch (ext) {
      'png' => 'png',
      'webp' => 'webp',
      'jpeg' || 'jpg' => 'jpeg',
      _ => 'jpeg',
    });
  }

  static Future<AuthSession> _session() async {
    final s = AuthService.instance.currentSession ??
        await AuthService.instance.getStoredSession();
    if (s == null) throw const DiseaseDetectionException('Please sign in again.');
    return s;
  }

  /// Upload a photo and run the model. Returns the prediction + advice.
  static Future<DiseaseResult> analyze(List<int> bytes, String filename,
      {String? flockId}) async {
    final session = await _session();
    final uri = Uri.parse('${AuthService.instance.baseUrl}/api/ml/predict-disease/');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer ${session.accessToken}'
      ..files.add(http.MultipartFile.fromBytes('image', bytes,
          filename: filename, contentType: _mediaType(filename)));
    if (flockId != null) request.fields['flock_id'] = flockId;

    final response = await http.Response.fromStream(await request.send());
    final decoded = response.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DiseaseDetectionException(
          (decoded is Map ? decoded['detail']?.toString() : null) ??
              'Analysis failed (${response.statusCode}).');
    }
    return DiseaseResult(Map<String, dynamic>.from(decoded as Map));
  }

  /// Recent completed scans for the "Recent Cases" list.
  static Future<List<DiseaseResult>> recentScans({int limit = 10}) async {
    final session = await _session();
    final uri = Uri.parse(
        '${AuthService.instance.baseUrl}/api/ml/scans/?limit=$limit');
    final response = await http.get(uri,
        headers: {'Authorization': 'Bearer ${session.accessToken}'});
    if (response.statusCode != 200) {
      throw const DiseaseDetectionException('Could not load recent scans.');
    }
    final rows = (jsonDecode(response.body)['results'] as List?) ?? const [];
    return rows
        .map((e) => DiseaseResult(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
