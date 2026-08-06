enum AdminRole {
  superAdmin,
  operationsAdmin,
  financeAdmin,
  contentAdmin,
  researchAdmin,
  deliveryAdmin,
  pharmacyAdmin,
  supportAgent,
}

enum AdminModule {
  dashboard,
  userManagement,
  doctorPatient,
  deliveryManagement,
  teamManagement,
  pharmacyManagement,
  researchArticles,
  communityModeration,
  financeSubscriptions,
  supportSafety,
}

enum AdminPermission {
  view,
  create,
  edit,
  approve,
  delete,
  suspend,
  assign,
  export,
  refund,
}

const kRoleDisplayNames = <AdminRole, String>{
  AdminRole.superAdmin: 'Super Admin',
  AdminRole.operationsAdmin: 'Operations Admin',
  AdminRole.financeAdmin: 'Finance Admin',
  AdminRole.contentAdmin: 'Content Admin',
  AdminRole.researchAdmin: 'Research Admin',
  AdminRole.deliveryAdmin: 'Delivery Admin',
  AdminRole.pharmacyAdmin: 'Pharmacy Admin',
  AdminRole.supportAgent: 'Support Agent',
};

const kModuleDisplayNames = <AdminModule, String>{
  AdminModule.dashboard: 'Dashboard',
  AdminModule.userManagement: 'User Management',
  AdminModule.doctorPatient: 'Doctors & Patients',
  AdminModule.deliveryManagement: 'Delivery',
  AdminModule.teamManagement: 'Team Management',
  AdminModule.pharmacyManagement: 'Pharmacy',
  AdminModule.researchArticles: 'Research & Articles',
  AdminModule.communityModeration: 'Community',
  AdminModule.financeSubscriptions: 'Finance',
  AdminModule.supportSafety: 'Support & Safety',
};

final _all = AdminPermission.values.toSet();
final _view = {AdminPermission.view};

final Map<AdminRole, Map<AdminModule, Set<AdminPermission>>> kRolePermissions =
    {
  AdminRole.superAdmin: {for (final m in AdminModule.values) m: _all},
  AdminRole.operationsAdmin: {
    AdminModule.dashboard: _view,
    AdminModule.userManagement: {
      AdminPermission.view,
      AdminPermission.edit,
      AdminPermission.suspend,
      AdminPermission.approve
    },
    AdminModule.doctorPatient: {
      AdminPermission.view,
      AdminPermission.approve,
      AdminPermission.edit
    },
    AdminModule.deliveryManagement: {
      AdminPermission.view,
      AdminPermission.assign,
      AdminPermission.edit,
      AdminPermission.approve
    },
    AdminModule.teamManagement: {
      AdminPermission.view,
      AdminPermission.create,
      AdminPermission.edit,
      AdminPermission.assign
    },
    AdminModule.pharmacyManagement: {
      AdminPermission.view,
      AdminPermission.approve
    },
    AdminModule.communityModeration: _view,
    AdminModule.supportSafety: _view,
  },
  AdminRole.financeAdmin: {
    AdminModule.dashboard: _view,
    AdminModule.userManagement: _view,
    AdminModule.financeSubscriptions: {
      AdminPermission.view,
      AdminPermission.refund,
      AdminPermission.export,
      AdminPermission.edit
    },
  },
  AdminRole.contentAdmin: {
    AdminModule.dashboard: _view,
    AdminModule.researchArticles: {
      AdminPermission.view,
      AdminPermission.approve,
      AdminPermission.edit,
      AdminPermission.delete,
      AdminPermission.create
    },
    AdminModule.communityModeration: {
      AdminPermission.view,
      AdminPermission.delete,
      AdminPermission.suspend
    },
  },
  AdminRole.researchAdmin: {
    AdminModule.dashboard: _view,
    AdminModule.researchArticles: {
      AdminPermission.view,
      AdminPermission.create,
      AdminPermission.edit,
      AdminPermission.approve
    },
  },
  AdminRole.deliveryAdmin: {
    AdminModule.dashboard: _view,
    AdminModule.deliveryManagement: {
      AdminPermission.view,
      AdminPermission.assign,
      AdminPermission.edit,
      AdminPermission.approve,
      AdminPermission.delete
    },
  },
  AdminRole.pharmacyAdmin: {
    AdminModule.dashboard: _view,
    AdminModule.pharmacyManagement: {
      AdminPermission.view,
      AdminPermission.create,
      AdminPermission.edit,
      AdminPermission.approve,
      AdminPermission.delete
    },
  },
  AdminRole.supportAgent: {
    AdminModule.dashboard: _view,
    AdminModule.userManagement: _view,
    AdminModule.doctorPatient: _view,
    AdminModule.communityModeration: {
      AdminPermission.view,
      AdminPermission.delete,
      AdminPermission.suspend
    },
    AdminModule.supportSafety: {
      AdminPermission.view,
      AdminPermission.edit,
      AdminPermission.create
    },
  },
};
