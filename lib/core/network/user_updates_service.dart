import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';

/// Polls `GET /api/me/updates/?since=<iso>` so every role's UI reflects admin
/// actions (verification, suspension, assignment, content decisions, shift-rate
/// changes) within ~10s without any WebSocket infrastructure.
///
/// - [accessRevoked] flips to true when the account is suspended mid-session;
///   the router redirects to login on the next navigation tick.
/// - [verified] / [accountStatus] mirror the live backend state so role sessions
///   that don't poll their own profile (e.g. DoctorSession) can still react.
/// - [consumeToast] hands a screen the newest unseen admin notification once,
///   for a "Your account has been verified by admin" style toast.
/// - Role sessions register a [addRefreshHook] callback; it fires whenever
///   something meaningful changed so they can re-fetch their own data.
class UserUpdatesService extends ChangeNotifier {
  UserUpdatesService._();
  static final UserUpdatesService instance = UserUpdatesService._();

  Timer? _timer;
  DateTime? _since;
  bool _accessRevoked = false;
  bool _verified = false;
  String _accountStatus = 'active';
  int _unreadCount = 0;
  Map<String, dynamic> _profile = const {};
  final List<Map<String, dynamic>> _pendingToasts = [];
  final Set<String> _seen = {};
  final List<void Function()> _refreshHooks = [];

  Duration interval = const Duration(seconds: 10);

  bool get accessRevoked => _accessRevoked;
  bool get verified => _verified;
  String get accountStatus => _accountStatus;
  int get unreadCount => _unreadCount;
  Map<String, dynamic> get profile => Map.unmodifiable(_profile);

  void addRefreshHook(void Function() hook) {
    if (!_refreshHooks.contains(hook)) _refreshHooks.add(hook);
  }

  void removeRefreshHook(void Function() hook) => _refreshHooks.remove(hook);

  /// Returns (and clears) the newest admin-action notification the UI hasn't
  /// shown yet, or null. Call from a toast listener on each notify.
  Map<String, dynamic>? consumeToast() {
    if (_pendingToasts.isEmpty) return null;
    return _pendingToasts.removeAt(0);
  }

  void start() {
    _timer?.cancel();
    _since = DateTime.now().toUtc();
    _accessRevoked = false;
    _timer = Timer.periodic(interval, (_) => poll());
    poll();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _accessRevoked = false;
    _pendingToasts.clear();
    _seen.clear();
  }

  Future<void> poll() async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null || session.accessToken.isEmpty) return;

    final sinceParam = (_since ?? DateTime.now().toUtc()).toIso8601String();
    final uri = Uri.parse('${auth.baseUrl}/api/me/updates/')
        .replace(queryParameters: {'since': sinceParam});
    try {
      final response = await http.get(uri, headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${session.accessToken}',
      });
      if (response.statusCode == 403 || response.statusCode == 401) {
        _accessRevoked = true;
        notifyListeners();
        return;
      }
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      var changed = false;

      final status = data['account_status']?.toString() ?? _accountStatus;
      if (status != _accountStatus) {
        _accountStatus = status;
        changed = true;
      }
      final verified = data['is_verified'] == true;
      if (verified != _verified) {
        _verified = verified;
        changed = true;
      }
      _unreadCount = (data['unread_count'] as num?)?.toInt() ?? _unreadCount;
      final newProfile = (data['profile'] as Map?)?.cast<String, dynamic>() ?? const {};
      if (newProfile.toString() != _profile.toString()) {
        _profile = newProfile;
        changed = true;
      }

      for (final raw in (data['notifications'] as List? ?? const [])) {
        final n = Map<String, dynamic>.from(raw as Map);
        final id = n['id']?.toString() ?? '';
        if (id.isEmpty || _seen.contains(id)) continue;
        _seen.add(id);
        changed = true;
        final type = (n['type'] ?? '').toString();
        if (type == 'approval' || type == 'alert' ||
            (n['reference_type'] ?? '').toString().startsWith('admin')) {
          _pendingToasts.add(n);
        }
      }

      final serverTime = data['server_time']?.toString();
      if (serverTime != null) {
        _since = DateTime.tryParse(serverTime)?.toUtc() ?? _since;
      }
      if (data['access_revoked'] == true || _accountStatus == 'suspended') {
        _accessRevoked = true;
        changed = true;
      }

      if (changed) {
        for (final hook in List.of(_refreshHooks)) {
          hook();
        }
        notifyListeners();
      }
    } catch (_) {
      // Network hiccup — retry next tick.
    }
  }
}
