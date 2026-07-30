import 'package:flutter/foundation.dart';
import '../models/admin_role.dart';
import '../../../../core/network/auth_service.dart';

class AdminSession extends ChangeNotifier {
  static final AdminSession _instance = AdminSession._();
  AdminSession._() {
    AuthService.instance.addListener(_loadRegisteredProfile);
    _loadRegisteredProfile();
  }
  static AdminSession get instance => _instance;

  AdminRole _role = AdminRole.superAdmin;
  String _name = 'Administrator';
  String _email = '';

  AdminRole get role => _role;
  String get name => _name;
  String get email => _email;
  Map<String, dynamic> _profileData = {};
  Map<String, dynamic> get profileData => Map.unmodifiable(_profileData);

  Future<void> _loadRegisteredProfile() async {
    final session = AuthService.instance.currentSession ??
        await AuthService.instance.getStoredSession();
    if (session == null) return;
    if (!session.user.roles.any((role) => role.toLowerCase() == 'admin'))
      return;
    _name = session.user.fullName;
    _email = session.user.email;
    _profileData = session.user.profileData;
    notifyListeners();
  }

  String get roleDisplayName => kRoleDisplayNames[_role] ?? 'Admin';

  void setRole(AdminRole role, {String? name, String? email}) {
    _role = role;
    if (name != null) _name = name;
    if (email != null) _email = email;
    notifyListeners();
  }

  bool can(AdminModule module, AdminPermission permission) {
    return kRolePermissions[_role]?[module]?.contains(permission) ?? false;
  }

  bool canAccess(AdminModule module) => can(module, AdminPermission.view);

  List<AdminModule> get accessibleModules =>
      AdminModule.values.where(canAccess).toList();
}
