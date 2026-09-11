import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/core/widgets/profile_photo_field.dart';
import '../../data/models/researcher_profile.dart';
import '../../data/services/research_api_service.dart';
import '../../data/services/research_session.dart';
import '../research_theme.dart';
import '../widgets/research_scaffold.dart';
import '../widgets/research_sidebar.dart';

const _verifiedFieldLabels = {
  'institution_name': 'Institution',
  'institutional_email': 'Institutional Email',
  'department': 'Department',
  'highest_degree': 'Highest Degree',
  'field_of_study': 'Field of Study',
  'university_name': 'University',
  'graduation_year': 'Graduation Year',
  'research_role_type': 'Research Role Type',
  'areas_of_expertise': 'Areas of Expertise',
  'poultry_specific_experience': 'Poultry-Specific Experience',
  'ethics_certificate_url': 'Ethics/Training Certificate URL',
  'conflict_of_interest_declaration': 'Conflict of Interest Declaration',
  'publication_consent': 'Publication Consent',
  'ip_agreement': 'IP Agreement',
};

class ResearcherProfileScreen extends StatelessWidget {
  const ResearcherProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResearchScaffold(
      title: 'My Profile',
      module: ResearchModule.profile,
      child: ListenableBuilder(
        listenable: ResearchSession.instance,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _ProfileBody(),
        ),
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
        _ContributionsCard(profile: profile),
        const SizedBox(height: 20),
        _PublicationsCard(papers: published),
        const SizedBox(height: 20),
        if (profile.fieldsLocked) ...[
          const _ChangeApplicationsCard(),
          const SizedBox(height: 20),
        ],
        _ContactCard(profile: profile),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final ResearcherProfile profile;
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
          ProfilePhotoField(
            radius: 36,
            currentUrl:
                AuthService.instance.currentSession?.user.profilePhotoUrl ?? '',
            fallbackInitial:
                profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'R',
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(profile.name,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    _StatusChip(status: profile.verificationStatus),
                  ],
                ),
                if (!profile.hasPremiumSubscription) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'A premium subscription is required to submit papers, disease updates, or innovations.',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  profile.specialty,
                  style: TextStyle(
                      fontSize: 14, color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  '${profile.department} · ${profile.institution}',
                  style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 4),
                Text(
                  '${profile.yearsExperience} years experience',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _openEditProfileDialog(context, profile),
            icon: const Icon(Icons.edit_outlined, color: Colors.white),
            tooltip: 'Edit profile',
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (status) {
      'verified' => (RColors.published, Icons.verified, 'Featherflow Verified'),
      'suspended' => (RColors.needsRevision, Icons.block, 'Suspended'),
      _ => (RColors.underReview, Icons.hourglass_empty, 'Verification Pending'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  final ResearcherProfile profile;
  const _AboutCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('About',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: RColors.textPrimary)),
          const SizedBox(height: 12),
          Text(profile.bio.isEmpty ? 'No bio provided yet.' : profile.bio,
              style: const TextStyle(fontSize: 13, color: RColors.textSecondary, height: 1.6)),
          const SizedBox(height: 16),
          const Divider(color: RColors.divider),
          const SizedBox(height: 12),
          _InfoRow(icon: Icons.school_outlined, label: 'Degree', value: profile.highestDegree),
          const SizedBox(height: 8),
          _InfoRow(icon: Icons.account_balance_outlined, label: 'University', value: profile.universityName),
          const SizedBox(height: 8),
          _InfoRow(
              icon: Icons.event_outlined,
              label: 'Graduated',
              value: profile.graduationYear > 0 ? '${profile.graduationYear}' : '—'),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: RColors.textSecondary),
        const SizedBox(width: 8),
        Text('$label: ',
            style: const TextStyle(fontSize: 12, color: RColors.textSecondary, fontWeight: FontWeight.w500)),
        Flexible(
          child: Text(value.isEmpty ? '—' : value,
              style: const TextStyle(fontSize: 12, color: RColors.secondary)),
        ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  final ResearcherProfile profile;
  const _StatsCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Impact',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: RColors.textPrimary)),
          const SizedBox(height: 16),
          _ImpactStat(
            value: '${profile.totalPublications}',
            label: 'Published Items',
            icon: Icons.article_outlined,
            color: RColors.secondary,
          ),
          const SizedBox(height: 12),
          _ImpactStat(
            value: '${profile.totalViews}',
            label: 'Total Views',
            icon: Icons.visibility_outlined,
            color: RColors.accepted,
          ),
          const SizedBox(height: 12),
          _ImpactStat(
            value: '${profile.totalBookmarks}',
            label: 'Total Bookmarks',
            icon: Icons.bookmark_outline,
            color: RColors.published,
          ),
          const SizedBox(height: 12),
          _ImpactStat(
            value: '${profile.pendingReviewCount + profile.needsRevisionCount}',
            label: 'Awaiting Action',
            icon: Icons.pending_actions_outlined,
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

  const _ImpactStat({required this.value, required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
            Text(label, style: const TextStyle(fontSize: 11, color: RColors.textSecondary)),
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
          const Text('Research Interests',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: RColors.textPrimary)),
          const SizedBox(height: 12),
          if (interests.isEmpty)
            const Text('No research interests listed yet.',
                style: TextStyle(fontSize: 13, color: RColors.textSecondary))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: interests
                  .map((i) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: RColors.secondary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: RColors.secondary.withValues(alpha: 0.3)),
                        ),
                        child: Text(i,
                            style: const TextStyle(
                                fontSize: 12, color: RColors.secondary, fontWeight: FontWeight.w500)),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _ContributionsCard extends StatelessWidget {
  final ResearcherProfile profile;
  const _ContributionsCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Author Contributions',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: RColors.textPrimary)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                  child: _TypeCountTile(
                      label: 'Papers', count: profile.byType['research_paper'] ?? 0)),
              const SizedBox(width: 10),
              Expanded(
                  child: _TypeCountTile(
                      label: 'Disease Updates', count: profile.byType['disease_study'] ?? 0)),
              const SizedBox(width: 10),
              Expanded(
                  child: _TypeCountTile(
                      label: 'Innovations', count: profile.byType['innovation'] ?? 0)),
            ],
          ),
          const SizedBox(height: 16),
          if (profile.contributions.isEmpty)
            const Text('No submissions yet.', style: TextStyle(fontSize: 13, color: RColors.textSecondary))
          else
            ...profile.contributions.take(8).map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(c.title,
                            style: const TextStyle(fontSize: 13, color: RColors.textPrimary),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Text(c.status,
                          style: const TextStyle(
                              fontSize: 11, color: RColors.textSecondary, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      const Icon(Icons.visibility_outlined, size: 12, color: RColors.grey),
                      const SizedBox(width: 3),
                      Text('${c.viewsCount}', style: const TextStyle(fontSize: 11, color: RColors.grey)),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

class _TypeCountTile extends StatelessWidget {
  final String label;
  final int count;
  const _TypeCountTile({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: RColors.surface2, borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Text('$count',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: RColors.secondary)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: RColors.textSecondary), textAlign: TextAlign.center),
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
                const Text('Publications',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: RColors.textPrimary)),
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
              child: Text('No published papers yet.',
                  style: TextStyle(color: RColors.textSecondary, fontSize: 13)),
            )
          else
            ...papers.take(5).map((p) => _PublicationRow(paper: p)),
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
          Text(paper.title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: RColors.textPrimary)),
          const SizedBox(height: 4),
          Row(
            children: [
              if (paper.publishedAt != null) ...[
                Text('${paper.publishedAt!.year}', style: const TextStyle(fontSize: 12, color: RColors.grey)),
                const SizedBox(width: 8),
              ],
              const Icon(Icons.visibility_outlined, size: 12, color: RColors.grey),
              const SizedBox(width: 3),
              Text('${paper.views}', style: const TextStyle(fontSize: 12, color: RColors.grey)),
            ],
          ),
          const Divider(height: 20, color: RColors.divider),
        ],
      ),
    );
  }
}

class _ChangeApplicationsCard extends StatefulWidget {
  const _ChangeApplicationsCard();

  @override
  State<_ChangeApplicationsCard> createState() => _ChangeApplicationsCardState();
}

class _ChangeApplicationsCardState extends State<_ChangeApplicationsCard> {
  List<Map<String, dynamic>>? _applications;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final apps = await ResearchApiService.instance.changeApplications();
      if (!mounted) return;
      setState(() => _applications = apps);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Profile Change Applications',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: RColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('Verified fields are locked — request a change and an admin will review it.',
              style: TextStyle(fontSize: 12, color: RColors.textSecondary)),
          const SizedBox(height: 14),
          if (_error != null)
            Text(_error!, style: const TextStyle(fontSize: 12, color: RColors.needsRevision))
          else if (_applications == null)
            const SizedBox(height: 24, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_applications!.isEmpty)
            const Text('No applications submitted yet.',
                style: TextStyle(fontSize: 13, color: RColors.textSecondary))
          else
            ..._applications!.map((a) {
              final (color, label) = switch (a['status']) {
                'approved' => (RColors.published, 'Approved'),
                'rejected' => (RColors.needsRevision, 'Rejected'),
                _ => (RColors.underReview, 'Pending'),
              };
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              _verifiedFieldLabels[a['field_name']] ?? a['field_name'].toString(),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600, color: RColors.textPrimary)),
                          Text('→ ${a['new_value']}',
                              style: const TextStyle(fontSize: 12, color: RColors.textSecondary)),
                          if (a['review_note'] != null &&
                              a['review_note'].toString().trim().isNotEmpty)
                            Text('Admin note: ${a['review_note']}',
                                style: const TextStyle(fontSize: 11, color: RColors.textSecondary)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(label,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final ResearcherProfile profile;
  const _ContactCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Contact & Collaboration',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: RColors.textPrimary)),
          const SizedBox(height: 12),
          _InfoRow(icon: Icons.email_outlined, label: 'Email', value: profile.contactEmail),
          const SizedBox(height: 8),
          _InfoRow(icon: Icons.business_outlined, label: 'Institution', value: profile.institution),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Edit profile dialog ──────────────────────────────────────────────────

Future<void> _openEditProfileDialog(BuildContext context, ResearcherProfile profile) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _EditProfileDialog(profile: profile),
  );
}

class _EditProfileDialog extends StatefulWidget {
  final ResearcherProfile profile;
  const _EditProfileDialog({required this.profile});

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late final TextEditingController _cvUrlCtrl;
  late final TextEditingController _portfolioCtrl;
  late final TextEditingController _yearsCtrl;
  late final TextEditingController _refNameCtrl;
  late final TextEditingController _refTitleCtrl;
  late final TextEditingController _refEmailCtrl;
  // Only used pre-verification, when every field is still directly editable.
  late final TextEditingController _institutionCtrl;
  late final TextEditingController _departmentCtrl;
  late final TextEditingController _fieldOfStudyCtrl;
  late final TextEditingController _interestsCtrl;
  late final TextEditingController _bioCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _cvUrlCtrl = TextEditingController(text: p.cvUrl);
    _portfolioCtrl = TextEditingController(text: p.publicationsPortfolioUrl);
    _yearsCtrl = TextEditingController(text: '${p.yearsExperience}');
    _refNameCtrl = TextEditingController(text: p.referenceName);
    _refTitleCtrl = TextEditingController(text: p.referenceTitle);
    _refEmailCtrl = TextEditingController(text: p.referenceEmail);
    _institutionCtrl = TextEditingController(text: p.institution);
    _departmentCtrl = TextEditingController(text: p.department);
    _fieldOfStudyCtrl = TextEditingController(text: p.fieldOfStudy);
    _interestsCtrl = TextEditingController(text: p.researchInterests.join(', '));
    _bioCtrl = TextEditingController(text: p.bio);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final p = widget.profile;
      if (p.fieldsLocked) {
        await ResearchSession.instance.updateProfile(ResearcherProfile(
          id: p.id, name: p.name, email: p.email, institution: p.institution, department: p.department,
          researchInterests: p.researchInterests, bio: p.bio, contactEmail: p.contactEmail, isVerified: p.isVerified,
          cvUrl: _cvUrlCtrl.text.trim(),
          publicationsPortfolioUrl: _portfolioCtrl.text.trim(),
          yearsExperience: int.tryParse(_yearsCtrl.text.trim()) ?? p.yearsExperience,
          referenceName: _refNameCtrl.text.trim(),
          referenceTitle: _refTitleCtrl.text.trim(),
          referenceEmail: _refEmailCtrl.text.trim(),
        ));
      } else {
        await ResearchSession.instance.updateProfile(ResearcherProfile(
          id: p.id, name: p.name, email: p.email, contactEmail: p.contactEmail, isVerified: p.isVerified,
          institution: _institutionCtrl.text.trim(),
          department: _departmentCtrl.text.trim(),
          fieldOfStudy: _fieldOfStudyCtrl.text.trim(),
          researchInterests:
              _interestsCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
          bio: _bioCtrl.text.trim(),
          cvUrl: _cvUrlCtrl.text.trim(),
          publicationsPortfolioUrl: _portfolioCtrl.text.trim(),
          yearsExperience: int.tryParse(_yearsCtrl.text.trim()) ?? p.yearsExperience,
          referenceName: _refNameCtrl.text.trim(),
          referenceTitle: _refTitleCtrl.text.trim(),
          referenceEmail: _refEmailCtrl.text.trim(),
        ), fullUpdate: true);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _requestChange(String fieldName, String currentValue) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _RequestChangeDialog(
        fieldLabel: _verifiedFieldLabels[fieldName] ?? fieldName,
        fieldName: fieldName,
        currentValue: currentValue,
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Change application submitted for admin review.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return AlertDialog(
      title: const Text('Edit Profile'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                const SizedBox(height: 8),
              ],
              if (p.fieldsLocked) ...[
                const Text('Verified fields (locked)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: RColors.textSecondary)),
                const SizedBox(height: 4),
                _LockedField(label: 'Institution', value: p.institution,
                    onRequestChange: () => _requestChange('institution_name', p.institution)),
                _LockedField(label: 'Department', value: p.department,
                    onRequestChange: () => _requestChange('department', p.department)),
                _LockedField(label: 'Field of Study', value: p.fieldOfStudy,
                    onRequestChange: () => _requestChange('field_of_study', p.fieldOfStudy)),
                _LockedField(label: 'Bio / Experience', value: p.bio,
                    onRequestChange: () => _requestChange('poultry_specific_experience', p.bio)),
                _LockedField(
                    label: 'Research Interests', value: p.researchInterests.join(', '),
                    onRequestChange: () =>
                        _requestChange('areas_of_expertise', p.researchInterests.join(', '))),
                const SizedBox(height: 16),
              ] else ...[
                TextField(controller: _institutionCtrl, decoration: const InputDecoration(labelText: 'Institution')),
                TextField(controller: _departmentCtrl, decoration: const InputDecoration(labelText: 'Department')),
                TextField(
                    controller: _fieldOfStudyCtrl,
                    decoration: const InputDecoration(labelText: 'Field of Study')),
                TextField(
                    controller: _interestsCtrl,
                    decoration: const InputDecoration(labelText: 'Research interests (comma separated)')),
                TextField(
                    controller: _bioCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Bio / poultry experience')),
                const SizedBox(height: 12),
              ],
              const Text('Always editable',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: RColors.textSecondary)),
              const SizedBox(height: 4),
              TextField(controller: _cvUrlCtrl, decoration: const InputDecoration(labelText: 'CV URL')),
              TextField(
                  controller: _portfolioCtrl,
                  decoration: const InputDecoration(labelText: 'Publications portfolio URL')),
              TextField(
                controller: _yearsCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Years of research experience'),
              ),
              TextField(controller: _refNameCtrl, decoration: const InputDecoration(labelText: 'Reference name')),
              TextField(controller: _refTitleCtrl, decoration: const InputDecoration(labelText: 'Reference title')),
              TextField(controller: _refEmailCtrl, decoration: const InputDecoration(labelText: 'Reference email')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _LockedField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onRequestChange;

  const _LockedField({required this.label, required this.value, required this.onRequestChange});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: RColors.textSecondary)),
                Text(value.isEmpty ? '—' : value,
                    style: const TextStyle(fontSize: 13, color: RColors.textPrimary)),
              ],
            ),
          ),
          const Icon(Icons.lock_outline, size: 14, color: RColors.grey),
          TextButton(onPressed: onRequestChange, child: const Text('Request Change')),
        ],
      ),
    );
  }
}

class _RequestChangeDialog extends StatefulWidget {
  final String fieldLabel;
  final String fieldName;
  final String currentValue;

  const _RequestChangeDialog({
    required this.fieldLabel,
    required this.fieldName,
    required this.currentValue,
  });

  @override
  State<_RequestChangeDialog> createState() => _RequestChangeDialogState();
}

class _RequestChangeDialogState extends State<_RequestChangeDialog> {
  late final TextEditingController _valueCtrl;
  final _reasonCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _valueCtrl = TextEditingController(text: widget.currentValue);
  }

  Future<void> _submit() async {
    if (_valueCtrl.text.trim().isEmpty || _reasonCtrl.text.trim().isEmpty) {
      setState(() => _error = 'A new value and a reason are both required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ResearchApiService.instance.submitChangeApplication(
        fieldName: widget.fieldName,
        newValue: _valueCtrl.text.trim(),
        reason: _reasonCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Request Change: ${widget.fieldLabel}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _valueCtrl,
              decoration: const InputDecoration(labelText: 'New value'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Reason for this change'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Submit'),
        ),
      ],
    );
  }
}
