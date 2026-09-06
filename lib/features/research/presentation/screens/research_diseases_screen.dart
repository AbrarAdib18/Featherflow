import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/disease_update.dart';
import '../../data/models/research_paper.dart' show PaperStatus, PaperStatusLabel;
import '../../data/services/research_session.dart';
import '../research_theme.dart';
import '../widgets/research_scaffold.dart';
import '../widgets/research_sidebar.dart';

class ResearchDiseasesScreen extends StatefulWidget {
  const ResearchDiseasesScreen({super.key});

  @override
  State<ResearchDiseasesScreen> createState() =>
      _ResearchDiseasesScreenState();
}

class _ResearchDiseasesScreenState
    extends State<ResearchDiseasesScreen> {
  String? _expandedId;
  DiseaseSeverity? _severityFilter;

  List<DiseaseUpdate> get _filtered {
    final all = ResearchSession.instance.diseaseUpdates;
    if (_severityFilter == null) return all;
    return all.where((d) => d.severity == _severityFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ResearchScaffold(
      title: 'Disease & Cure Updates',
      module: ResearchModule.diseases,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/research/new-disease-update'),
        icon: const Icon(Icons.add),
        label: const Text('New Update'),
        backgroundColor: RColors.secondary,
      ),
      child: Column(
        children: [
          _SeverityFilterBar(
            selected: _severityFilter,
            onChanged: (s) => setState(() => _severityFilter = s),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: ResearchSession.instance,
              builder: (context, _) => _filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No disease updates found.',
                        style: TextStyle(color: RColors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final d = _filtered[i];
                        return _DiseaseCard(
                          update: d,
                          expanded: _expandedId == d.id,
                          onToggle: () => setState(() {
                            _expandedId =
                                _expandedId == d.id ? null : d.id;
                          }),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeverityFilterBar extends StatelessWidget {
  final DiseaseSeverity? selected;
  final ValueChanged<DiseaseSeverity?> onChanged;

  const _SeverityFilterBar(
      {required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: RColors.bg,
        border: Border(bottom: BorderSide(color: RColors.divider)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _SevChip(
              label: 'All',
              selected: selected == null,
              color: RColors.textPrimary,
              onTap: () => onChanged(null),
            ),
            const SizedBox(width: 8),
            ...DiseaseSeverity.values.map((s) {
              final (_, fg, label) = severityColors(s);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _SevChip(
                  label: label,
                  selected: selected == s,
                  color: fg,
                  onTap: () => onChanged(s),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _SevChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _SevChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : RColors.cardBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? color : RColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _DiseaseCard extends StatelessWidget {
  final DiseaseUpdate update;
  final bool expanded;
  final VoidCallback onToggle;

  const _DiseaseCard({
    required this.update,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final (sevBg, sevFg, sevLabel) = severityColors(update.severity);
    return Container(
      decoration: rCard(
          highlight: update.severity == DiseaseSeverity.critical),
      child: Column(
        children: [
          _DiseaseHeader(
            update: update,
            expanded: expanded,
            onToggle: onToggle,
            sevBg: sevBg,
            sevFg: sevFg,
            sevLabel: sevLabel,
          ),
          if (expanded) ...[
            const Divider(height: 1, color: RColors.divider),
            _DiseaseBody(update: update),
          ],
        ],
      ),
    );
  }
}

class _DiseaseHeader extends StatelessWidget {
  final DiseaseUpdate update;
  final bool expanded;
  final VoidCallback onToggle;
  final Color sevBg;
  final Color sevFg;
  final String sevLabel;

  const _DiseaseHeader({
    required this.update,
    required this.expanded,
    required this.onToggle,
    required this.sevBg,
    required this.sevFg,
    required this.sevLabel,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: expanded
          ? const BorderRadius.vertical(top: Radius.circular(12))
          : BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: sevBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.health_and_safety_outlined,
                color: sevFg,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          update.diseaseName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: RColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: sevBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: sevFg.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          sevLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: sevFg,
                          ),
                        ),
                      ),
                      if (update.status != PaperStatus.published) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: RColors.surface2,
                            borderRadius: BorderRadius.circular(12),
                            border: const Border.fromBorderSide(BorderSide(color: RColors.cardBorder)),
                          ),
                          child: Text(update.status.label,
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600, color: RColors.textSecondary)),
                        ),
                      ],
                      if (update.status == PaperStatus.draft ||
                          update.status == PaperStatus.needsRevision) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 16, color: RColors.secondary),
                          tooltip: 'Edit',
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          padding: EdgeInsets.zero,
                          onPressed: () =>
                              context.push('/research/new-disease-update', extra: update.id),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    update.causativeAgent,
                    style: const TextStyle(
                      fontSize: 12,
                      color: RColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F9F5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: RColors.secondary
                              .withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.agriculture_outlined,
                            size: 14, color: RColors.secondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            update.farmerSummary,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF1B5E20),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        update.authorName,
                        style: const TextStyle(
                          fontSize: 11,
                          color: RColors.textSecondary,
                        ),
                      ),
                      const Text(' · ',
                          style:
                              TextStyle(color: RColors.grey)),
                      Text(
                        _formatDate(update.publishedAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: RColors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.visibility_outlined,
                          size: 12, color: RColors.grey),
                      const SizedBox(width: 3),
                      Text(
                        '${update.views}',
                        style: const TextStyle(
                            fontSize: 11, color: RColors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(
                Icons.keyboard_arrow_down,
                color: RColors.textSecondary,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

class _DiseaseBody extends StatelessWidget {
  final DiseaseUpdate update;
  const _DiseaseBody({required this.update});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (update.reviewNotes?.trim().isNotEmpty == true) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: RColors.needsRevisionLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: RColors.needsRevision.withValues(alpha: 0.3)),
              ),
              child: Text('Reviewer note: ${update.reviewNotes}',
                  style: const TextStyle(fontSize: 12, color: RColors.needsRevision)),
            ),
          ],
          if (update.affectedBreeds.isNotEmpty) ...[
            _DetailSection(
              icon: Icons.pets_outlined,
              title: 'Affected Breeds',
              color: RColors.textSecondary,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: update.affectedBreeds
                    .map((b) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: RColors.surface2,
                            borderRadius: BorderRadius.circular(6),
                            border: const Border.fromBorderSide(
                                BorderSide(color: RColors.cardBorder)),
                          ),
                          child: Text(
                            b,
                            style: const TextStyle(
                              fontSize: 11,
                              color: RColors.textSecondary,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 14),
          ],
          _DetailSection(
            icon: Icons.warning_amber_outlined,
            title: 'Clinical Signs & Symptoms',
            color: RColors.high,
            child: _DetailText(update.symptoms),
          ),
          const SizedBox(height: 14),
          _DetailSection(
            icon: Icons.medical_services_outlined,
            title: 'Treatment',
            color: RColors.accepted,
            child: _DetailText(update.treatments),
          ),
          const SizedBox(height: 14),
          _DetailSection(
            icon: Icons.shield_outlined,
            title: 'Prevention',
            color: RColors.published,
            child: _DetailText(update.preventionMethods),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final Widget child;

  const _DetailSection({
    required this.icon,
    required this.title,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _DetailText extends StatelessWidget {
  final String text;
  const _DetailText(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RColors.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: RColors.textPrimary,
          height: 1.5,
        ),
      ),
    );
  }
}
