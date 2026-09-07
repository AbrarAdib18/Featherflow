import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/auth_service.dart';
import '../../../../core/router/app_router.dart';
import '../../data/services/research_session.dart';
import '../research_theme.dart';

enum ResearchModule {
  dashboard,
  profile,
  papers,
  submit,
  diseases,
  innovations,
  search,
  collaboration,
  analytics,
  review,
}

extension ResearchModuleInfo on ResearchModule {
  String get label => switch (this) {
        ResearchModule.dashboard => 'Dashboard',
        ResearchModule.profile => 'My Profile',
        ResearchModule.papers => 'My Papers',
        ResearchModule.submit => 'Submit Paper',
        ResearchModule.diseases => 'Disease Updates',
        ResearchModule.innovations => 'Innovations',
        ResearchModule.search => 'Search & Discovery',
        ResearchModule.collaboration => 'Collaboration',
        ResearchModule.analytics => 'Analytics',
        ResearchModule.review => 'Review Area',
      };

  IconData get icon => switch (this) {
        ResearchModule.dashboard => Icons.dashboard_outlined,
        ResearchModule.profile => Icons.person_outlined,
        ResearchModule.papers => Icons.article_outlined,
        ResearchModule.submit => Icons.post_add_outlined,
        ResearchModule.diseases => Icons.health_and_safety_outlined,
        ResearchModule.innovations => Icons.lightbulb_outlined,
        ResearchModule.search => Icons.search,
        ResearchModule.collaboration => Icons.group_outlined,
        ResearchModule.analytics => Icons.bar_chart_outlined,
        ResearchModule.review => Icons.rate_review_outlined,
      };

  String get route => switch (this) {
        ResearchModule.dashboard => '/research',
        ResearchModule.profile => '/research/profile',
        ResearchModule.papers => '/research/papers',
        ResearchModule.submit => '/research/new-paper',
        ResearchModule.diseases => '/research/diseases',
        ResearchModule.innovations => '/research/innovations',
        ResearchModule.search => '/research/search',
        ResearchModule.collaboration => '/research/collaboration',
        ResearchModule.analytics => '/research/analytics',
        ResearchModule.review => '/research/review',
      };
}

class ResearchSidebar extends StatelessWidget {
  final ResearchModule selectedModule;

  const ResearchSidebar({super.key, required this.selectedModule});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: RColors.bg,
      child: Column(
        children: [
          // Reactive so the verified badge / name appear once the session loads.
          ListenableBuilder(
            listenable: ResearchSession.instance,
            builder: (context, _) =>
                _SidebarHeader(profile: ResearchSession.instance.profile),
          ),
          const Divider(height: 1, color: RColors.divider),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                const _SectionLabel('Workspace'),
                _NavItem(
                  module: ResearchModule.dashboard,
                  selected: selectedModule == ResearchModule.dashboard,
                ),
                _NavItem(
                  module: ResearchModule.profile,
                  selected: selectedModule == ResearchModule.profile,
                ),
                const SizedBox(height: 8),
                const _SectionLabel('Research'),
                _NavItem(
                  module: ResearchModule.papers,
                  selected: selectedModule == ResearchModule.papers,
                ),
                _NavItem(
                  module: ResearchModule.submit,
                  selected: selectedModule == ResearchModule.submit,
                ),
                _NavItem(
                  module: ResearchModule.review,
                  selected: selectedModule == ResearchModule.review,
                ),
                const SizedBox(height: 8),
                const _SectionLabel('Knowledge'),
                _NavItem(
                  module: ResearchModule.diseases,
                  selected: selectedModule == ResearchModule.diseases,
                ),
                _NavItem(
                  module: ResearchModule.innovations,
                  selected: selectedModule == ResearchModule.innovations,
                ),
                _NavItem(
                  module: ResearchModule.search,
                  selected: selectedModule == ResearchModule.search,
                ),
                const SizedBox(height: 8),
                const _SectionLabel('Tools'),
                _NavItem(
                  module: ResearchModule.collaboration,
                  selected: selectedModule == ResearchModule.collaboration,
                ),
                _NavItem(
                  module: ResearchModule.analytics,
                  selected: selectedModule == ResearchModule.analytics,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: RColors.divider),
          _SidebarFooter(),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  final dynamic profile;
  const _SidebarHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: RColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.science_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Featherflow',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: RColors.primary,
                    ),
                  ),
                  Text(
                    'Research Panel',
                    style: TextStyle(
                      fontSize: 11,
                      color: RColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: RColors.surface2,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: RColors.secondary.withValues(alpha: 0.2),
                  child: Text(
                    profile.name.isNotEmpty
                        ? profile.name[0].toUpperCase()
                        : 'R',
                    style: const TextStyle(
                      color: RColors.secondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: RColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (profile.isVerified)
                        const Row(
                          children: [
                            Icon(
                              Icons.verified,
                              size: 11,
                              color: RColors.secondary,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'Verified Researcher',
                              style: TextStyle(
                                fontSize: 10,
                                color: RColors.secondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        )
                      else
                        const Text(
                          'Unverified',
                          style: TextStyle(
                            fontSize: 10,
                            color: RColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: RColors.grey,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final ResearchModule module;
  final bool selected;

  const _NavItem({required this.module, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected
            ? RColors.secondary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => context.go(module.route),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(
                  module.icon,
                  size: 18,
                  color: selected ? RColors.secondary : RColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    module.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected
                          ? RColors.secondary
                          : RColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextButton.icon(
        onPressed: () async {
          await AuthService.instance.clearSession();
          if (context.mounted) {
            context.go(AppRoutes.login);
          }
        },
        icon: const Icon(Icons.logout, size: 16),
        label: const Text('Sign Out'),
        style: TextButton.styleFrom(
          foregroundColor: RColors.textSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }
}
