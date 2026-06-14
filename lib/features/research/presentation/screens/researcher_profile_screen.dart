import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/services/research_session.dart';
import '../research_theme.dart';
import '../widgets/research_scaffold.dart';
import '../widgets/research_sidebar.dart';

class ResearcherProfileScreen extends StatelessWidget {
  const ResearcherProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResearchScaffold(
      title: 'My Profile',
      module: ResearchModule.profile,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _ProfileBody(),
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final profile = ResearchSession.instance.profile;
    final published = ResearchSession.instance.publishedPapers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProfileHeader(profile: profile),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 640) {
              return Column(
                children: [
                  _AboutCard(profile: profile),
                  const SizedBox(height: 16),
                  _StatsCard(profile: profile),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _AboutCard(profile: profile)),
                const SizedBox(width: 16),
                Expanded(flex: 1, child: _StatsCard(profile: profile)),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        _InterestsCard(interests: profile.researchInterests),
        const SizedBox(height: 20),
        _PublicationsCard(papers: published),
        const SizedBox(height: 20),
        _ContactCard(profile: profile),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final dynamic profile;
  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF01291E), Color(0xFF023D2D)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(
              profile.name.isNotEmpty
                  ? profile.name[0].toUpperCase()
                  : 'R',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 28,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        profile.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (profile.isVerified) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: RColors.secondary.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: RColors.secondary
                                  .withValues(alpha: 0.5)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified,
                                size: 13, color: RColors.secondary),
                            SizedBox(width: 4),
                            Text(
                              'Featherflow Verified',
                              style: TextStyle(
                                fontSize: 11,
                                color: RColors.secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  profile.specialty,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${profile.department} · ${profile.institution}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${profile.yearsExperience} years experience',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.6),
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

class _AboutCard extends StatelessWidget {
  final dynamic profile;
  const _AboutCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: RColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            profile.bio,
            style: const TextStyle(
              fontSize: 13,
              color: RColors.textSecondary,
              height: 1.6,
            ),
          ),
          if (profile.orcid != null) ...[
            const SizedBox(height: 16),
            const Divider(color: RColors.divider),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.fingerprint,
              label: 'ORCID',
              value: profile.orcid!,
            ),
          ],
          if (profile.linkedIn != null) ...[
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.link,
              label: 'LinkedIn',
              value: profile.linkedIn!,
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: RColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 12,
            color: RColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: RColors.secondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  final dynamic profile;
  const _StatsCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Impact',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: RColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _ImpactStat(
            value: '${profile.totalPublications}',
            label: 'Publications',
            icon: Icons.article_outlined,
            color: RColors.secondary,
          ),
          const SizedBox(height: 12),
          _ImpactStat(
            value: '${profile.totalCitations}',
            label: 'Total Citations',
            icon: Icons.format_quote_outlined,
            color: RColors.accepted,
          ),
          const SizedBox(height: 12),
          _ImpactStat(
            value: '${profile.hIndex}',
            label: 'h-Index',
            icon: Icons.trending_up,
            color: RColors.published,
          ),
          const SizedBox(height: 12),
          _ImpactStat(
            value: '${profile.yearsExperience}',
            label: 'Years Active',
            icon: Icons.history_edu_outlined,
            color: RColors.underReview,
          ),
        ],
      ),
    );
  }
}

class _ImpactStat extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _ImpactStat({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: RColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InterestsCard extends StatelessWidget {
  final List<String> interests;
  const _InterestsCard({required this.interests});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Research Interests',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: RColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: interests
                .map((i) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: RColors.secondary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color:
                                RColors.secondary.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        i,
                        style: const TextStyle(
                          fontSize: 12,
                          color: RColors.secondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _PublicationsCard extends StatelessWidget {
  final List<dynamic> papers;
  const _PublicationsCard({required this.papers});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                const Text(
                  'Publications',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: RColors.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.go('/research/papers'),
                  child: const Text('View All'),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: RColors.divider),
          if (papers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No published papers yet.',
                style: TextStyle(color: RColors.textSecondary, fontSize: 13),
              ),
            )
          else
            ...papers.take(5).map(
                  (p) => _PublicationRow(paper: p),
                ),
        ],
      ),
    );
  }
}

class _PublicationRow extends StatelessWidget {
  final dynamic paper;
  const _PublicationRow({required this.paper});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            paper.title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: RColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (paper.journal != null)
                Flexible(
                  child: Text(
                    paper.journal!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: RColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (paper.publishedAt != null) ...[
                const Text(' · ',
                    style: TextStyle(color: RColors.grey)),
                Text(
                  '${paper.publishedAt!.year}',
                  style: const TextStyle(
                      fontSize: 12, color: RColors.grey),
                ),
              ],
              const SizedBox(width: 8),
              const Icon(Icons.visibility_outlined,
                  size: 12, color: RColors.grey),
              const SizedBox(width: 3),
              Text(
                '${paper.views}',
                style: const TextStyle(fontSize: 12, color: RColors.grey),
              ),
            ],
          ),
          const Divider(height: 20, color: RColors.divider),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final dynamic profile;
  const _ContactCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Contact & Collaboration',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: RColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.email_outlined,
            label: 'Email',
            value: profile.contactEmail,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.business_outlined,
            label: 'Institution',
            value: profile.institution,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => context.go('/research/collaboration'),
                icon: const Icon(Icons.group_outlined, size: 16),
                label: const Text('Collaboration Tools'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: RColors.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
