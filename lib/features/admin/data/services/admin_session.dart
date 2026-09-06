import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/network/auth_service.dart';
import '../models/admin_role.dart';
import 'admin_api_service.dart';

/// Holds the signed-in admin's identity, role, tier and effective permission
/// map. The permission map is authoritative and comes from the backend
/// (`GET /api/admin-panel/me/`); [can] / [canAccess] gate the whole panel UI.
class AdminSession extends ChangeNotifier {
  static final AdminSession _instance = AdminSession._();
  AdminSession._() {
    AuthService.instance.addListener(refresh);
    refresh();
  }
  static AdminSession get instance => _instance;

  AdminRole _role = AdminRole.supportAgent;
  int _tier = 4;
  String _name = 'Administrator';
  String _email = '';
  String _department = '';
  bool _loaded = false;
  bool _loading = false;
  String? _error;
  AdminPermissions _permissions = const AdminPermissions({});
  Map<String, dynamic> _profileData = {};

  // ── shift timer ─────────────────────────────────────────────────────────
  bool _tracksShifts = false;
  Map<String, dynamic> _shift = const {};
  Timer? _shiftPoll;

  bool get tracksShifts => _tracksShifts;
  Map<String, dynamic> get shift => Map.unmodifiable(_shift);
  bool get isOnShift => _shift['is_on_shift'] == true;
  bool get onBreak => _shift['on_break'] == true;
  int get shiftSecondsElapsed => (_shift['seconds_elapsed'] as num?)?.toInt() ?? 0;
  double get hoursToday => (_shift['hours_today'] as num?)?.toDouble() ?? 0;
  double get hoursThisWeek => (_shift['hours_this_week'] as num?)?.toDouble() ?? 0;
  double get hoursThisMonth => (_shift['hours_this_month'] as num?)?.toDouble() ?? 0;
  double get hourlyRate => (_shift['hourly_rate'] as num?)?.toDouble() ?? 0;

  Future<void> _pushShift(Map<String, dynamic>? s) async {
    if (s == null) return;
    _shift = s;
    notifyListeners();
  }

  Future<void> refreshShift() async {
    if (!_tracksShifts) return;
    try {
      _shift = await AdminApiService.instance.shiftStatus();
      notifyListeners();
    } catch (_) {}
  }

  Future<String?> startShift() => _shiftAction(AdminApiService.instance.startShift);
  Future<String?> endShift() => _shiftAction(AdminApiService.instance.endShift);
  Future<String?> startBreak() => _shiftAction(AdminApiService.instance.startBreak);
  Future<String?> endBreak() => _shiftAction(AdminApiService.instance.endBreak);

  Future<String?> _shiftAction(Future<Map<String, dynamic>> Function() call) async {
    try {
      await _pushShift(await call());
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  void _startShiftPoll() {
    _shiftPoll?.cancel();
    if (!_tracksShifts) return;
    _shiftPoll = Timer.periodic(const Duration(seconds: 10), (_) => refreshShift());
  }

  AdminRole get role => _role;
  int get tier => _tier;
  String get name => _name;
  String get email => _email;
  String get department => _department;
  bool get isLoaded => _loaded;
  bool get isLoading => _loading;
  String? get error => _error;
  bool get isSuperAdmin => _tier == 1;
  bool get isOperationsAdmin => _tier <= 2;
  AdminPermissions get permissions => _permissions;
  Map<String, dynamic> get profileData => Map.unmodifiable(_profileData);
  String get roleDisplayName => kRoleDisplayNames[_role] ?? 'Admin';

  Future<void> refresh() async {
    final session = AuthService.instance.currentSession ??
        await AuthService.instance.getStoredSession();
    if (session == null) {
      _loaded = false;
      _tracksShifts = false;
      _shift = const {};
      _shiftPoll?.cancel();
      return;
    }
    final isAdmin = session.user.roles.any(
        (r) => r == 'admin' || r.startsWith('admin_'));
    if (!isAdmin) return;

    _loading = true;
    notifyListeners();
    try {
      final me = await AdminApiService.instance.me();
      _name = (me['name'] ?? session.user.fullName).toString();
      _email = (me['email'] ?? session.user.email).toString();
      _department = (me['department'] ?? '').toString();
      _role = adminRoleFromName(me['role']?.toString());
      _tier = (me['tier'] as num?)?.toInt() ?? kRoleTiers[_role] ?? 4;
      _permissions = AdminPermissions.fromJson(
          (me['permissions'] as Map?)?.cast<String, dynamic>());
      _profileData = session.user.profileData;
      _tracksShifts = me['tracks_shifts'] == true;
      _shift = (me['shift'] as Map?)?.cast<String, dynamic>() ?? const {};
      _startShiftPoll();
      _error = null;
      _loaded = true;
    } catch (e) {
      // Fall back to a name-derived role so the shell still renders, but the
      // permission map stays conservative until /me/ succeeds.
      final names = session.user.roles;
      _role = adminRoleFromName(
          names.firstWhere((r) => r.startsWith('admin_'), orElse: () => 'admin'));
      _tier = kRoleTiers[_role] ?? 4;
      _permissions = AdminPermissions.fallback(_role);
      _name = session.user.fullName;
      _email = session.user.email;
      _error = e.toString();
      _loaded = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  bool can(AdminModule module, AdminPermission permission) =>
      _permissions.can(module, permission);

  bool canAccess(AdminModule module) =>
      module == AdminModule.dashboard || _permissions.canAccess(module);

  List<AdminModule> get accessibleModules =>
      AdminModule.values.where(canAccess).toList();
}
