// 1. Pure RBAC-gate logic: the fallback permission matrix scopes each role.
// 2. Smoke: the real app boots with a stored admin session and routes to the
//    admin panel without throwing.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/main.dart';
import 'package:featherflow/features/admin/data/models/admin_role.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdminPermissions gate', () {
    test('super admin can access every module', () {
      const perms = AdminPermissions({}, isSuper: true);
      for (final m in AdminModule.values) {
        expect(perms.canAccess(m), isTrue, reason: '$m');
        expect(perms.can(m, AdminPermission.delete), isTrue);
      }
    });

    test('finance admin is scoped to finance/subscriptions/audit/approvals', () {
      final perms = AdminPermissions.fallback(AdminRole.financeAdmin);
      expect(perms.canAccess(AdminModule.financeSubscriptions), isTrue);
      expect(perms.can(AdminModule.financeSubscriptions, AdminPermission.refund), isTrue);
      expect(perms.canAccess(AdminModule.deliveryManagement), isFalse);
      expect(perms.canAccess(AdminModule.adminManagement), isFalse);
      expect(perms.can(AdminModule.userManagement, AdminPermission.suspend), isFalse);
    });

    test('support agent cannot approve content or manage admins', () {
      final perms = AdminPermissions.fallback(AdminRole.supportAgent);
      expect(perms.canAccess(AdminModule.supportSafety), isTrue);
      expect(perms.can(AdminModule.researchArticles, AdminPermission.approve), isFalse);
      expect(perms.canAccess(AdminModule.adminManagement), isFalse);
      expect(perms.canAccess(AdminModule.financeSubscriptions), isFalse);
    });

    test('server permission map wins over the fallback', () {
      final perms = AdminPermissions.fromJson({
        'delivery': ['view', 'assign'],
        'audit': ['view'],
      });
      expect(perms.can(AdminModule.deliveryManagement, AdminPermission.assign), isTrue);
      expect(perms.can(AdminModule.deliveryManagement, AdminPermission.delete), isFalse);
      expect(perms.canAccess(AdminModule.financeSubscriptions), isFalse);
    });
  });

  testWidgets('app boots with an admin session and reaches the panel', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({
      'featherflow_auth_session': jsonEncode({
        'access': 'test-token',
        'refresh': 'test-refresh',
        'user': {
          'id': 'test-admin',
          'email': 'admin@test.dev',
          'full_name': 'Test Admin',
          'roles': ['admin_super'],
          'account_status': 'active',
          'phone': '+880000',
          'present_address': 'x',
          'date_of_birth': '1990-01-01',
          'profile_data': {},
        },
      }),
    });
    await t.pumpWidget(const FeatherflowApp());
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 400));
    }
    expect(find.text('Dashboard'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
