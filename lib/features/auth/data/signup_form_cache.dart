import 'package:flutter/foundation.dart';

/// In-memory cache of partly-filled signup forms.
///
/// Why in memory (not `shared_preferences` / Hive): the signup forms hold a
/// plaintext password and identity documents. Persisting that to disk widens the
/// attack surface for very little gain, so the cache lives only for the life of
/// the running app — it survives navigating back and forth inside the signup
/// flow (every screen is rebuilt fresh by `context.go`, losing its `State`), and
/// is gone on restart.
///
/// Lifecycle:
///   * `save(key, values)` — called on every field change.
///   * `read(key)`         — called from `initState` to repopulate the form.
///   * `clear(key)`        — explicit "start this step over".
///   * `clearAll()`        — registration succeeded (see `routeAfterRegistration`).
///
/// Navigating back/forward between steps does **not** clear anything — that is
/// the whole point; a returning step repopulates from its stored entry.
class SignupFormCache {
  SignupFormCache._();

  /// Singleton — mirrors `AuthService.instance` style used across the app.
  static final SignupFormCache instance = SignupFormCache._();

  /// Key for the shared step-1 "basic information" screen.
  static const String basicInfoKey = 'basic';

  /// Key for step-2 role selection.
  static const String roleSelectionKey = 'role_selection';

  /// Flip to false to silence the breadcrumb logs.
  static bool debugLogging = kDebugMode;

  final Map<String, Map<String, dynamic>> _forms = <String, Map<String, dynamic>>{};

  void _log(String action, String key, [Map<String, dynamic>? values]) {
    if (!debugLogging) return;
    final keys = values == null ? '' : ' keys=${values.keys.toList()}';
    debugPrint('[SignupFormCache] $action key=$key$keys '
        'at=${DateTime.now().toIso8601String()}');
  }

  void save(String key, Map<String, dynamic> values) {
    _forms[key] = Map<String, dynamic>.from(values);
    _log('save', key, values);
  }

  Map<String, dynamic>? read(String key) {
    final stored = _forms[key];
    _log(stored == null ? 'read (miss)' : 'read (hit)', key, stored);
    return stored == null ? null : Map<String, dynamic>.from(stored);
  }

  /// True when [key] holds at least one non-empty / non-default value.
  bool hasData(String key) {
    final stored = _forms[key];
    if (stored == null) return false;
    return stored.values.any(_isMeaningful);
  }

  void clear(String key) {
    _forms.remove(key);
    _log('clear', key);
  }

  void clearAll() {
    _forms.clear();
    _log('clearAll', '*');
  }

  static bool _isMeaningful(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is bool) return value;
    if (value is Iterable) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }
}
