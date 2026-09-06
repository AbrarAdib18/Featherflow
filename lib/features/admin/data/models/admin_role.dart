/// Admin RBAC model.
///
/// Roles, tiers and the permission matrix are owned by the backend
/// (`roles.permissions` / `roles.tier_level`). The frontend receives the
/// caller's effective permission map from `GET /api/admin-panel/me/` and gates
/// UI with [AdminPermissions.can]. The static [kRolePermissions] map below is a
/// last-resort fallback only (used if `/me/` cannot be reached).
library;

enum AdminRole {
  superAdmin,
  operationsAdmin,
  financeAdmin,
  contentAdmin,
  researchAdmin,
  deliveryAdmin,
  pharmacyAdmin,
  doctorAdmin,
  teamAdmin,
  supportAgent,
}

/// Backend role name (`roles.name`) <-> enum.
const kRoleNames = <AdminRole, String>{
  AdminRole.superAdmin: 'admin_super',
  AdminRole.operationsAdmin: 'admin_operations',
  AdminRole.financeAdmin: 'admin_finance',
  AdminRole.contentAdmin: 'admin_content',
  AdminRole.researchAdmin: 'admin_research',
  AdminRole.deliveryAdmin: 'admin_delivery',
  AdminRole.pharmacyAdmin: 'admin_pharmacy',
  AdminRole.doctorAdmin: 'admin_doctor',
  AdminRole.teamAdmin: 'admin_team',
  AdminRole.supportAgent: 'admin_support',
};

AdminRole adminRoleFromName(String? name) {
  for (final entry in kRoleNames.entries) {
    if (entry.value == name) return entry.key;
  }
  if (name == 'admin') return AdminRole.operationsAdmin; // legacy generic role
  return AdminRole.supportAgent;
}

const kRoleDisplayNames = <AdminRole, String>{
  AdminRole.superAdmin: 'Super Admin',
  AdminRole.operationsAdmin: 'Operations Admin',
  AdminRole.financeAdmin: 'Finance Admin',
  AdminRole.contentAdmin: 'Content Admin',
  AdminRole.researchAdmin: 'Research Admin',
  AdminRole.deliveryAdmin: 'Delivery Admin',
  AdminRole.pharmacyAdmin: 'Pharmacy Admin',
  AdminRole.doctorAdmin: 'Doctor Admin',
  AdminRole.teamAdmin: 'Team Admin',
  AdminRole.supportAgent: 'Support Agent',
};

const kRoleTiers = <AdminRole, int>{
  AdminRole.superAdmin: 1,
  AdminRole.operationsAdmin: 2,
  AdminRole.financeAdmin: 3,
  AdminRole.contentAdmin: 3,
  AdminRole.researchAdmin: 3,
  AdminRole.deliveryAdmin: 3,
  AdminRole.pharmacyAdmin: 3,
  AdminRole.doctorAdmin: 3,
  AdminRole.teamAdmin: 3,
  AdminRole.supportAgent: 4,
};

/// UI module ids. The string value is the backend permission-map key.
enum AdminModule {
  dashboard('dashboard'),
  userManagement('users'),
  doctorPatient('doctors'),
  deliveryManagement('delivery'),
  pharmacyManagement('pharmacy'),
  researchArticles('articles'),
  researchWorkspace('research'),
  communityModeration('community'),
  financeSubscriptions('finance'),
  subscriptions('subscriptions'),
  supportSafety('support'),
  teamManagement('team'),
  adminManagement('team'),
  teamPayroll('team'),
  auditTrail('audit'),
  approvals('approvals'),
  escalations('escalations'),
  oversight('oversight'),
  platformSettings('settings');

  const AdminModule(this.key);
  final String key;
}

const kModuleDisplayNames = <AdminModule, String>{
  AdminModule.dashboard: 'Dashboard',
  AdminModule.userManagement: 'User Management',
  AdminModule.doctorPatient: 'Doctors & Patients',
  AdminModule.deliveryManagement: 'Delivery',
  AdminModule.pharmacyManagement: 'Pharmacy',
  AdminModule.researchArticles: 'Research & Articles',
  AdminModule.researchWorkspace: 'Research',
  AdminModule.communityModeration: 'Community',
  AdminModule.financeSubscriptions: 'Finance',
  AdminModule.subscriptions: 'Subscriptions',
  AdminModule.supportSafety: 'Support & Safety',
  AdminModule.teamManagement: 'Team Management',
  AdminModule.adminManagement: 'Admin Management',
  AdminModule.teamPayroll: 'Team & Payroll',
  AdminModule.auditTrail: 'Audit Trail',
  AdminModule.approvals: 'Approval Queue',
  AdminModule.escalations: 'Escalations',
  AdminModule.oversight: 'Oversight',
  AdminModule.platformSettings: 'Platform Settings',
};

enum AdminPermission {
  view,
  create,
  edit,
  approve,
  reject,
  delete,
  suspend,
  assign,
  export,
  refund,
  override;

  String get key => name;
}

/// The caller's effective permissions, as delivered by `/api/admin-panel/me/`
/// (`{ "module": ["action", ...] }`, or `{ "*": ["*"] }` for Super Admin).
class AdminPermissions {
  const AdminPermissions(this._map, {this.isSuper = false});

  final Map<String, Set<String>> _map;
  final bool isSuper;

  factory AdminPermissions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AdminPermissions({});
    if (json['*'] is List && (json['*'] as List).contains('*')) {
      return const AdminPermissions({}, isSuper: true);
    }
    final map = <String, Set<String>>{};
    json.forEach((module, actions) {
      if (actions is List) {
        map[module] = actions.map((a) => a.toString()).toSet();
      }
    });
    return AdminPermissions(map);
  }

  factory AdminPermissions.fallback(AdminRole role) {
    if (role == AdminRole.superAdmin) return const AdminPermissions({}, isSuper: true);
    final raw = kRolePermissions[role] ?? const {};
    return AdminPermissions({
      for (final entry in raw.entries)
        entry.key.key: entry.value.map((p) => p.key).toSet(),
    });
  }

  bool can(AdminModule module, AdminPermission permission) {
    if (isSuper) return true;
    final actions = _map[module.key];
    if (actions == null) return false;
    return actions.contains(permission.key) || actions.contains('*');
  }

  bool canAccess(AdminModule module) {
    if (isSuper) return true;
    return (_map[module.key]?.isNotEmpty ?? false);
  }

  Iterable<String> get modules => isSuper ? const ['*'] : _map.keys;
}

// ── Fallback permission matrix (only used when /me/ is unreachable) ──────────

final _all = AdminPermission.values.toSet();
final _view = {AdminPermission.view};

final Map<AdminRole, Map<AdminModule, Set<AdminPermission>>> kRolePermissions = {
  AdminRole.superAdmin: {for (final m in AdminModule.values) m: _all},
  AdminRole.operationsAdmin: {
    AdminModule.dashboard: _view,
    AdminModule.userManagement: {
      AdminPermission.view, AdminPermission.edit, AdminPermission.suspend, AdminPermission.approve,
    },
    AdminModule.doctorPatient: {AdminPermission.view, AdminPermission.approve, AdminPermission.edit},
    AdminModule.deliveryManagement: {
      AdminPermission.view, AdminPermission.assign, AdminPermission.edit, AdminPermission.approve,
    },
    AdminModule.pharmacyManagement: {AdminPermission.view, AdminPermission.approve},
    AdminModule.supportSafety: {AdminPermission.view, AdminPermission.edit, AdminPermission.assign},
    AdminModule.communityModeration: _view,
    AdminModule.auditTrail: _view,
    AdminModule.approvals: {AdminPermission.view, AdminPermission.approve, AdminPermission.reject},
    AdminModule.escalations: {AdminPermission.view, AdminPermission.approve},
    AdminModule.oversight: _view,
    AdminModule.teamManagement: _view,
  },
  AdminRole.financeAdmin: {
    AdminModule.dashboard: _view,
    AdminModule.financeSubscriptions: {
      AdminPermission.view, AdminPermission.refund, AdminPermission.export, AdminPermission.edit,
      AdminPermission.approve,
    },
    AdminModule.subscriptions: {AdminPermission.view, AdminPermission.edit, AdminPermission.refund},
    AdminModule.auditTrail: _view,
    AdminModule.approvals: _view,
  },
  AdminRole.contentAdmin: {
    AdminModule.dashboard: _view,
    AdminModule.researchArticles: {
      AdminPermission.view, AdminPermission.approve, AdminPermission.reject,
      AdminPermission.edit, AdminPermission.delete, AdminPermission.create,
    },
    AdminModule.communityModeration: {
      AdminPermission.view, AdminPermission.delete, AdminPermission.suspend, AdminPermission.edit,
    },
    AdminModule.auditTrail: _view,
  },
  AdminRole.researchAdmin: {
    AdminModule.dashboard: _view,
    AdminModule.researchWorkspace: {
      AdminPermission.view, AdminPermission.create, AdminPermission.edit,
      AdminPermission.approve, AdminPermission.reject, AdminPermission.suspend,
    },
    AdminModule.researchArticles: {
      AdminPermission.view, AdminPermission.create, AdminPermission.edit,
      AdminPermission.approve, AdminPermission.reject,
    },
    AdminModule.auditTrail: _view,
  },
  AdminRole.deliveryAdmin: {
    AdminModule.dashboard: _view,
    AdminModule.deliveryManagement: {
      AdminPermission.view, AdminPermission.assign, AdminPermission.edit,
      AdminPermission.approve, AdminPermission.reject, AdminPermission.suspend,
      AdminPermission.export, AdminPermission.refund,
    },
    AdminModule.auditTrail: _view,
  },
  AdminRole.pharmacyAdmin: {
    AdminModule.dashboard: _view,
    AdminModule.pharmacyManagement: {
      AdminPermission.view, AdminPermission.create, AdminPermission.edit,
      AdminPermission.approve, AdminPermission.reject, AdminPermission.suspend,
      AdminPermission.delete, AdminPermission.export,
    },
    AdminModule.auditTrail: _view,
  },
  AdminRole.doctorAdmin: {
    AdminModule.dashboard: _view,
    AdminModule.doctorPatient: {
      AdminPermission.view, AdminPermission.edit, AdminPermission.approve,
      AdminPermission.reject, AdminPermission.suspend, AdminPermission.export,
    },
    AdminModule.escalations: _view,
    AdminModule.supportSafety: _view,
    AdminModule.auditTrail: _view,
  },
  AdminRole.teamAdmin: {
    AdminModule.dashboard: _view,
    AdminModule.teamManagement: {
      AdminPermission.view, AdminPermission.create, AdminPermission.edit,
      AdminPermission.assign, AdminPermission.suspend,
    },
    AdminModule.adminManagement: {AdminPermission.view},
    AdminModule.auditTrail: _view,
    AdminModule.approvals: _view,
  },
  AdminRole.supportAgent: {
    AdminModule.dashboard: _view,
    AdminModule.userManagement: _view,
    AdminModule.doctorPatient: _view,
    AdminModule.communityModeration: _view,
    AdminModule.supportSafety: {
      AdminPermission.view, AdminPermission.edit, AdminPermission.create, AdminPermission.assign,
    },
    AdminModule.escalations: {AdminPermission.view, AdminPermission.create},
    AdminModule.auditTrail: _view,
  },
};
