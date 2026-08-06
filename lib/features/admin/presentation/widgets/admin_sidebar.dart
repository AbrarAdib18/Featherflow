import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/auth_service.dart';
import '../../../../core/router/app_router.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/admin_session.dart';
import '../admin_theme.dart';

class AdminSidebar extends StatelessWidget {
  final AdminModule selectedModule;

  const AdminSidebar({super.key, required this.selectedModule});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AdminSession.instance,
      builder: (_, __) {
        final session = AdminSession.instance;
        return Column(
          children: [
            _SidebarHeader(session: session),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  if (session.canAccess(AdminModule.dashboard))
                    _NavItem(
                      icon: Icons.dashboard_outlined,
                      label: 'Dashboard',
                      route: '/admin',
                      module: AdminModule.dashboard,
                      selected: selectedModule == AdminModule.dashboard,
                    ),
                  if (session.canAccess(AdminModule.userManagement))
                    _NavItem(
                      icon: Icons.people_outline,
                      label: 'User Management',
                      route: '/admin/users',
                      module: AdminModule.userManagement,
                      selected: selectedModule == AdminModule.userManagement,
                    ),
                  if (session.canAccess(AdminModule.doctorPatient))
                    _NavItem(
                      icon: Icons.medical_services_outlined,
                      label: 'Doctors & Patients',
                      route: '/admin/doctors',
                      module: AdminModule.doctorPatient,
                      selected: selectedModule == AdminModule.doctorPatient,
                    ),
                  if (session.canAccess(AdminModule.deliveryManagement))
                    _NavItem(
                      icon: Icons.local_shipping_outlined,
                      label: 'Delivery',
                      route: '/admin/delivery',
                      module: AdminModule.deliveryManagement,
                      selected:
                          selectedModule == AdminModule.deliveryManagement,
                    ),
                  if (session.canAccess(AdminModule.pharmacyManagement))
                    _NavItem(
                      icon: Icons.local_pharmacy_outlined,
                      label: 'Pharmacy',
                      route: '/admin/pharmacy',
                      module: AdminModule.pharmacyManagement,
                      selected:
                          selectedModule == AdminModule.pharmacyManagement,
                    ),
                  if (session.canAccess(AdminModule.teamManagement))
                    _NavItem(
                      icon: Icons.group_outlined,
                      label: 'Team Management',
                      route: '/admin/team',
                      module: AdminModule.teamManagement,
                      selected: selectedModule == AdminModule.teamManagement,
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Divider(height: 1, color: AColors.divider),
                  ),
                  if (session.canAccess(AdminModule.researchArticles))
                    _NavItem(
                      icon: Icons.article_outlined,
                      label: 'Research & Articles',
                      route: '/admin/content',
                      module: AdminModule.researchArticles,
                      selected: selectedModule == AdminModule.researchArticles,
                    ),
                  if (session.canAccess(AdminModule.communityModeration))
                    _NavItem(
                      icon: Icons.forum_outlined,
                      label: 'Community',
                      route: '/admin/community',
                      module: AdminModule.communityModeration,
                      selected:
                          selectedModule == AdminModule.communityModeration,
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Divider(height: 1, color: AColors.divider),
                  ),
                  if (session.canAccess(AdminModule.financeSubscriptions))
                    _NavItem(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Finance',
                      route: '/admin/finance',
                      module: AdminModule.financeSubscriptions,
                      selected:
                          selectedModule == AdminModule.financeSubscriptions,
                    ),
                  if (session.canAccess(AdminModule.supportSafety))
                    _NavItem(
                      icon: Icons.support_agent_outlined,
                      label: 'Support & Safety',
                      route: '/admin/support',
                      module: AdminModule.supportSafety,
                      selected: selectedModule == AdminModule.supportSafety,
                    ),
                ],
              ),
            ),
            _SidebarFooter(),
          ],
        );
      },
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  final AdminSession session;
  const _SidebarHeader({required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AColors.appBar,
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AColors.secondary.withValues(alpha: 0.2),
            child: Text(
              session.name.isNotEmpty ? session.name[0].toUpperCase() : 'A',
              style: const TextStyle(
                  color: AColors.secondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 20),
            ),
          ),
          const SizedBox(height: 10),
          Text(session.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          aChip(session.roleDisplayName, AColors.secondary, AColors.secondary),
        ],
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(height: 1, color: AColors.divider),
        ListTile(
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: AColors.secondary.withValues(alpha: 0.15),
            child: const Icon(Icons.person, size: 14, color: AColors.secondary),
          ),
          title: const Text('My Profile',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AColors.textPrimary)),
          trailing:
              const Icon(Icons.chevron_right, color: AColors.grey, size: 16),
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          onTap: () {
            if (Navigator.canPop(context)) Navigator.pop(context);
            context.go('/admin/profile');
          },
        ),
        ListTile(
          leading: const Icon(Icons.logout, color: AColors.red, size: 18),
          title: const Text('Sign Out',
              style: TextStyle(
                  color: AColors.red,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          onTap: () async {
            if (Navigator.canPop(context)) Navigator.pop(context);
            await AuthService.instance.clearSession();
            if (context.mounted) {
              context.go(AppRoutes.login);
            }
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String route;
  final AdminModule module;
  final bool selected;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.module,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        leading: Icon(icon,
            color: selected ? AColors.secondary : AColors.textSecondary,
            size: 20),
        title: Text(
          label,
          style: TextStyle(
            color: selected ? AColors.primary : AColors.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        selected: selected,
        selectedTileColor: AColors.secondary.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        dense: true,
        onTap: () {
          if (Navigator.canPop(context)) Navigator.pop(context);
          context.go(route);
        },
      ),
    );
  }
}
