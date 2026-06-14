import 'package:flutter/material.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/admin_session.dart';

class PermissionGuard extends StatelessWidget {
  final AdminModule module;
  final AdminPermission permission;
  final Widget child;
  final Widget? fallback;

  const PermissionGuard({
    super.key,
    required this.module,
    required this.permission,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AdminSession.instance,
      builder: (_, __) {
        if (AdminSession.instance.can(module, permission)) return child;
        return fallback ?? const SizedBox.shrink();
      },
    );
  }
}
