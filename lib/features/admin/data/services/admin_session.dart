import 'package:flutter/foundation.dart';
import '../models/admin_role.dart';

class AdminSession extends ChangeNotifier {
  static final AdminSession _instance = AdminSession._();
  AdminSession._();
  static AdminSession get instance => _instance;

  AdminRole _role = AdminRole.superAdmin;
  String _name = 'System Administrator';
  String _email = 'admin@featherflow.com';

  AdminRole get role => _role;
  String get name => _name;
  String get email => _email;
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
