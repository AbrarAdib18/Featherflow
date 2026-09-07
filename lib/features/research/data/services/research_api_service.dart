import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../../core/network/auth_service.dart';

class ResearchApiException implements Exception {
  final String message;
  const ResearchApiException(this.message);
  @override
  String toString() => message;
}

class ResearchApiService {
  ResearchApiService._();
  static final instance = ResearchApiService._();

  Future<Map<String, dynamic>> profile() => _request('research/profile/');
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> body) =>
      _request('research/profile/', method: 'PUT', body: body);

  Future<List<Map<String, dynamic>>> changeApplications() async {
    final data = await _request('research/profile/change-applications/');
    return List<Map<String, dynamic>>.from(
        (data['results'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<Map<String, dynamic>> submitChangeApplication({
    required String fieldName,
    required String newValue,
    required String reason,
  }) =>
      _request('research/profile/change-applications/', method: 'POST', body: {
        'field_name': fieldName, 'new_value': newValue, 'reason': reason,
      });

  Future<List<Map<String, dynamic>>> tagOptions() async {
    final data = await _request('research/tag-options/');
    return List<Map<String, dynamic>>.from(
        (data['results'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<List<Map<String, dynamic>>> versionHistory(String kind, String id) async {
    final data = await _request('research/$kind/$id/versions/');
    return List<Map<String, dynamic>>.from(
        (data['results'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<List<Map<String, dynamic>>> list(String kind) async {
    final data = await _request('research/$kind/');
    return List<Map<String, dynamic>>.from(
        (data['results'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<Map<String, dynamic>> create(String kind, Map<String, dynamic> body) =>
      _request('research/$kind/', method: 'POST', body: body);

  Future<Map<String, dynamic>> update(String kind, String id, Map<String, dynamic> body) =>
      _request('research/$kind/$id/', method: 'PUT', body: body);

  Future<void> delete(String kind, String id) =>
      _request('research/$kind/$id/', method: 'DELETE');

  Future<Map<String, dynamic>> submitForReview(String kind, String id) =>
      _request('research/$kind/$id/submit-review/', method: 'POST');

  Future<bool> toggleBookmark(String articleId) async {
    final data = await _request('research/bookmark/',
        method: 'POST', body: {'article_id': articleId});
    return data['bookmarked'] == true;
  }

  Future<List<Map<String, dynamic>>> bookmarks() async {
    final data = await _request('research/bookmarks/');
    return List<Map<String, dynamic>>.from(
        (data['results'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<Map<String, dynamic>> articleFeed({
    String? type,
    String? tag,
    String? search,
    String sort = 'latest',
    bool featuredOnly = false,
    int page = 1,
    int pageSize = 20,
  }) {
    final query = <String, String>{
      'sort': sort,
      'page': '$page',
      'page_size': '$pageSize',
    };
    if (type != null) query['type'] = type;
    if (tag != null) query['tag'] = tag;
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (featuredOnly) query['featured'] = '1';
    return _request('articles/all/', query: query);
  }

  Future<Map<String, dynamic>> articleDetail(String contentType, String id) =>
      _request('articles/$contentType/$id/');

  Future<List<Map<String, dynamic>>> tags() async {
    final data = await _request('articles/tags/');
    return List<Map<String, dynamic>>.from(
        (data['results'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<void> reportContent(String contentId, String reason) =>
      _request('articles/report/', method: 'POST', body: {'content_id': contentId, 'reason': reason});

  Future<String> uploadPdf(List<int> bytes, String filename) async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null || session.accessToken.isEmpty) {
      throw const ResearchApiException('Sign in is required.');
    }
    final uri = Uri.parse('${auth.baseUrl}/api/research/upload-pdf/');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer ${session.accessToken}'
      ..files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: filename, contentType: MediaType('application', 'pdf')));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'Upload failed (${response.statusCode}).';
      try {
        message = (jsonDecode(response.body) as Map)['detail']?.toString() ?? message;
      } catch (_) {}
      throw ResearchApiException(message);
    }
    return (jsonDecode(response.body) as Map)['url'] as String;
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null || session.accessToken.isEmpty) {
      throw const ResearchApiException('Sign in is required.');
    }
    final uri = Uri.parse('${auth.baseUrl}/api/$path')
        .replace(queryParameters: query?.isEmpty == true ? null : query);
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}',
    };
    final response = switch (method) {
      'POST' => await http.post(uri, headers: headers, body: jsonEncode(body ?? const {})),
      'PUT' => await http.put(uri, headers: headers, body: jsonEncode(body ?? const {})),
      'PATCH' => await http.patch(uri, headers: headers, body: jsonEncode(body ?? const {})),
      'DELETE' => await http.delete(uri, headers: headers),
      _ => await http.get(uri, headers: headers),
    };
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'Request failed (${response.statusCode}).';
      try {
        message = (jsonDecode(response.body) as Map)['detail']?.toString() ?? message;
      } catch (_) {}
      throw ResearchApiException(message);
    }
    return response.body.isEmpty
        ? {}
        : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }
}
