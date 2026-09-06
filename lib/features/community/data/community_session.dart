import 'dart:async';

import 'package:flutter/foundation.dart';

import 'community_api_service.dart';

/// Holds the community feed + notification badge and refreshes them on a 4s
/// poll (requirements §H.10). Screens read [posts]/[topics]/[unreadCount] and
/// rebuild on [notifyListeners]; [setView] switches tab/category and refreshes
/// immediately. One instance, started once the feed screen mounts.
class CommunitySession extends ChangeNotifier {
  CommunitySession._();
  static final CommunitySession instance = CommunitySession._();

  final _api = CommunityApiService.instance;
  static const _interval = Duration(seconds: 4);

  Timer? _timer;
  bool _loading = false;
  String? _error;
  String _tab = 'latest';
  String _category = 'All Posts';

  List<Map<String, dynamic>> _posts = const [];
  List<String> _topics = const ['All Posts'];
  List<Map<String, dynamic>> _trending = const [];
  int _unreadCount = 0;
  int _listeners = 0;

  bool get loading => _loading;
  String? get error => _error;
  String get tab => _tab;
  String get category => _category;
  List<Map<String, dynamic>> get posts => _posts;
  List<String> get topics => _topics;
  List<Map<String, dynamic>> get trendingHashtags => _trending;
  int get unreadCount => _unreadCount;

  /// Call from a screen's initState; balance with [release] in dispose.
  void attach() {
    _listeners++;
    if (_timer == null) {
      _timer = Timer.periodic(_interval, (_) => refresh(silent: true));
      refresh();
    }
  }

  void release() {
    _listeners = (_listeners - 1).clamp(0, 1 << 30);
    if (_listeners == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> setView({String? tab, String? category}) async {
    _tab = tab ?? _tab;
    _category = category ?? _category;
    notifyListeners();
    await refresh();
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      notifyListeners();
    }
    try {
      final results = await Future.wait([
        _api.feed(tab: _tab, category: _category == 'All Posts' ? null : _category),
        _api.notifications(),
      ]);
      final feed = results[0];
      _posts = List<Map<String, dynamic>>.from(
          (feed['posts'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
      _topics = List<String>.from(feed['topics'] as List? ?? const ['All Posts']);
      _trending = List<Map<String, dynamic>>.from(
          (feed['trending'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
      _unreadCount = (results[1]['unread_count'] as num?)?.toInt() ?? 0;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Optimistically patch one post in the cached list (after a react/bookmark)
  /// so the UI doesn't wait for the next poll.
  void patchPost(String id, Map<String, dynamic> updated) {
    _posts = _posts.map((p) => p['id'] == id ? updated : p).toList();
    notifyListeners();
  }

  void clearBadge() {
    _unreadCount = 0;
    notifyListeners();
  }
}
