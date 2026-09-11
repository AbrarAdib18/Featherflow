import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/auth_service.dart';
import '../../../core/network/upload_helpers.dart';

class CommunityApiException implements Exception {
  final String message;
  const CommunityApiException(this.message);
  @override
  String toString() => message;
}

/// Thin client for `/api/community/…`. Same shape as ResearchApiService:
/// a singleton with one private [_request] that adds the bearer token and
/// unwraps `{detail: …}` errors, plus a multipart [uploadMedia].
class CommunityApiService {
  CommunityApiService._();
  static final instance = CommunityApiService._();

  // ── feed & discovery ────────────────────────────────────────────────
  Future<Map<String, dynamic>> feed({String tab = 'latest', String? category, String? search}) {
    final q = <String, String>{'tab': tab};
    if (category != null && category.isNotEmpty && category != 'All Posts') q['category'] = category;
    if (search != null && search.isNotEmpty) q['search'] = search;
    return _request('community/', query: q);
  }

  Future<List<Map<String, dynamic>>> trending() => _list('community/trending/', 'posts');
  Future<List<Map<String, dynamic>>> following() => _list('community/following/', 'posts');
  Future<List<Map<String, dynamic>>> bookmarks() => _list('community/bookmarks/', 'posts');

  Future<Map<String, dynamic>> search({
    String? query,
    String? category,
    String? tag,
    String? postType,
    bool verifiedOnly = false,
    String sort = 'latest',
  }) {
    final q = <String, String>{'sort': sort};
    if (query != null && query.isNotEmpty) q['q'] = query;
    if (category != null && category.isNotEmpty && category != 'All Posts') q['category'] = category;
    if (tag != null && tag.isNotEmpty) q['tag'] = tag.replaceFirst('#', '');
    if (postType != null && postType.isNotEmpty) q['post_type'] = postType;
    if (verifiedOnly) q['verified'] = '1';
    return _request('community/search/', query: q);
  }

  Future<List<Map<String, dynamic>>> categories() => _list('community/categories/', 'results');
  Future<List<Map<String, dynamic>>> hashtags() => _list('community/hashtags/', 'results');
  Future<List<Map<String, dynamic>>> followSuggestions() =>
      _list('community/follows/suggestions/', 'suggestions');

  // ── posts ───────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> createPost(Map<String, dynamic> body) =>
      _request('community/', method: 'POST', body: body);

  Future<Map<String, dynamic>> post(String id) => _request('community/posts/$id/');

  Future<void> deletePost(String id, {String? reason}) =>
      _request('community/posts/$id/', method: 'DELETE', body: reason == null ? null : {'reason': reason});

  Future<Map<String, dynamic>> react(String postId, String type) =>
      _request('community/react/', method: 'POST', body: {'post_id': postId, 'reaction_type': type});

  Future<Map<String, dynamic>> reactToComment(String commentId, String type) => _request(
      'community/comments/$commentId/react/', method: 'POST', body: {'reaction_type': type});

  Future<Map<String, dynamic>> comment(String postId, String content, {String? parentId, bool anonymous = false}) =>
      _request('community/comment/', method: 'POST', body: {
        'post_id': postId, 'content': content,
        if (parentId != null) 'parent_comment_id': parentId,
        'is_anonymous': anonymous,
      });

  Future<Map<String, dynamic>> markBestAnswer(String commentId, {bool value = true}) => _request(
      'community/comments/$commentId/best-answer/', method: 'PATCH', body: {'is_best_answer': value});

  Future<bool> toggleBookmark(String postId) async {
    final data = await _request('community/bookmark/', method: 'POST', body: {'post_id': postId});
    return data['bookmarked'] == true;
  }

  Future<Map<String, dynamic>> repost(String postId, {String? comment}) => _request(
      'community/repost/', method: 'POST', body: {'post_id': postId, if (comment != null) 'comment': comment});

  Future<void> report({required String targetType, required String targetId, required String reason}) =>
      _request('community/report/', method: 'POST',
          body: {'target_type': targetType, 'target_id': targetId, 'reason': reason});

  Future<Map<String, dynamic>> votePoll(String postId, List<int> optionIndexes) => _request(
      'community/vote/', method: 'POST', body: {'post_id': postId, 'option_indexes': optionIndexes});

  // ── follows & profile ───────────────────────────────────────────────
  Future<bool> followUser(String userId) async {
    final data = await _request('community/follows/', method: 'POST', body: {'user_id': userId});
    return data['following'] == true;
  }

  Future<void> unfollowUser(String userId) =>
      _request('community/follows/$userId/', method: 'DELETE');

  Future<bool> blockUser(String userId) async {
    final data = await _request('community/blocks/', method: 'POST', body: {'user_id': userId});
    return data['blocked'] == true;
  }

  Future<void> unblockUser(String userId) =>
      _request('community/blocks/', method: 'DELETE', body: {'user_id': userId});

  Future<List<Map<String, dynamic>>> userPosts(String userId) =>
      _list('community/users/$userId/posts/', 'posts');

  Future<Map<String, dynamic>> userStats(String userId) =>
      _request('community/users/$userId/stats/');

  // ── notifications ───────────────────────────────────────────────────
  Future<Map<String, dynamic>> notifications() => _request('community/notifications/');
  Future<void> markNotificationsRead() =>
      _request('community/notifications/', method: 'PATCH', body: const {});

  // ── media ───────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> uploadMedia(List<int> bytes, String filename) async {
    final session = await _session();
    final uri = Uri.parse('${AuthService.instance.baseUrl}/api/community/upload/');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer ${session.accessToken}'
      ..files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: filename, contentType: mediaTypeForFilename(filename)));
    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CommunityApiException(_detail(response.body, 'Upload failed (${response.statusCode}).'));
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  // ── internals ───────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _list(String path, String key) async {
    final data = await _request(path);
    return List<Map<String, dynamic>>.from(
        (data[key] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<AuthSession> _session() async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null || session.accessToken.isEmpty) {
      throw const CommunityApiException('Please sign in again.');
    }
    return session;
  }

  static String _detail(String body, String fallback) {
    try {
      return (jsonDecode(body) as Map)['detail']?.toString() ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final session = await _session();
    final uri = Uri.parse('${AuthService.instance.baseUrl}/api/$path')
        .replace(queryParameters: (query == null || query.isEmpty) ? null : query);
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}',
    };
    final response = switch (method) {
      'POST' => await http.post(uri, headers: headers, body: jsonEncode(body ?? const {})),
      'PUT' => await http.put(uri, headers: headers, body: jsonEncode(body ?? const {})),
      'PATCH' => await http.patch(uri, headers: headers, body: jsonEncode(body ?? const {})),
      'DELETE' => await http.delete(uri, headers: headers, body: jsonEncode(body ?? const {})),
      _ => await http.get(uri, headers: headers),
    };
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CommunityApiException(_detail(response.body, 'Request failed (${response.statusCode}).'));
    }
    return response.body.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }
}
