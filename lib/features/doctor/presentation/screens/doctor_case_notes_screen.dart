import 'package:flutter/material.dart';
import '../../../../core/network/auth_service.dart' show AuthException;
import '../../data/models/doctor_models.dart';
import '../../data/services/doctor_session.dart';
import '../doctor_theme.dart';

class DoctorCaseNotesScreen extends StatefulWidget {
  const DoctorCaseNotesScreen({super.key});

  @override
  State<DoctorCaseNotesScreen> createState() => _DoctorCaseNotesScreenState();
}

class _DoctorCaseNotesScreenState extends State<DoctorCaseNotesScreen> {
  CaseStatus? _filter;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<DoctorCase> get _filtered {
    final session = DoctorSession.instance;
    List<DoctorCase> list = _search.isNotEmpty
        ? session.searchCases(_search)
        : session.cases.toList();
    if (_filter != null) list = list.where((c) => c.status == _filter).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DoctorSession.instance,
      builder: (context, _) => Scaffold(
        backgroundColor: VetColors.bg,
        appBar: AppBar(
          backgroundColor: VetColors.appBar,
          automaticallyImplyLeading: false,
          title: const Text(
            'Case Notes',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search, color: Colors.white),
              onPressed: () => setState(() {
                _search = '';
                _searchCtrl.clear();
              }),
            ),
          ],
        ),
        body: Column(
          children: [
            _SearchBar(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
            ),
            _FilterBar(
              selected: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
            Expanded(
              child: _filtered.isEmpty
                  ? _EmptyState(hasSearch: _search.isNotEmpty)
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _CaseCard(
                        doctorCase: _filtered[i],
                        onTap: () => _openDetail(context, _filtered[i]),
                      ),
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openNewCaseSheet(context),
          backgroundColor: VetColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('New Case'),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, DoctorCase c) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CaseDetailScreen(caseId: c.id)),
    );
  }

  void _openNewCaseSheet(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('New case form — connect to your backend to enable.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ── Search Bar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: VetColors.bg,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: VetColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search cases, farms, diseases…',
          hintStyle: const TextStyle(color: VetColors.grey, fontSize: 13),
          prefixIcon: const Icon(Icons.search, color: VetColors.grey, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon:
                      const Icon(Icons.clear, size: 18, color: VetColors.grey),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: VetColors.surface2,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: VetColors.secondary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

// ── Filter Bar ────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final CaseStatus? selected;
  final ValueChanged<CaseStatus?> onChanged;
  const _FilterBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final session = DoctorSession.instance;
    int count(CaseStatus? s) => s == null
        ? session.cases.length
        : session.cases.where((c) => c.status == s).length;

    final filters = <(CaseStatus?, String, Color)>[
      (null, 'All', VetColors.primary),
      (CaseStatus.open, 'Open', VetColors.open),
      (CaseStatus.inProgress, 'In Progress', VetColors.inProgress),
      (CaseStatus.followUp, 'Follow-Up', VetColors.followUpColor),
      (CaseStatus.closed, 'Closed', VetColors.closed),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: VetColors.bg,
        border: Border(bottom: BorderSide(color: VetColors.divider)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: filters.map((f) {
            final (status, label, color) = f;
            final isSel = selected == status;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onChanged(status),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSel
                        ? color.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSel ? color : VetColors.cardBorder,
                      width: isSel ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                          color: isSel ? color : VetColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isSel
                              ? color.withValues(alpha: 0.15)
                              : VetColors.surface2,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${count(status)}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isSel ? color : VetColors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Case Card ─────────────────────────────────────────────────────────────────

class _CaseCard extends StatelessWidget {
  final DoctorCase doctorCase;
  final VoidCallback onTap;
  const _CaseCard({required this.doctorCase, required this.onTap});

  (Color, String) get _urgencyAttrs => switch (doctorCase.urgency) {
        CaseUrgency.routine => (VetColors.routine, 'Routine'),
        CaseUrgency.moderate => (VetColors.moderate, 'Moderate'),
        CaseUrgency.urgent => (VetColors.urgent, 'Urgent'),
        CaseUrgency.emergency => (VetColors.emergency, 'Emergency'),
      };

  (Color, Color, String) get _statusAttrs => switch (doctorCase.status) {
        CaseStatus.open => (VetColors.openLight, VetColors.open, 'Open'),
        CaseStatus.inProgress => (
            VetColors.inProgressLight,
            VetColors.inProgress,
            'In Progress'
          ),
        CaseStatus.followUp => (
            VetColors.followUpLight,
            VetColors.followUpColor,
            'Follow-Up'
          ),
        CaseStatus.closed => (
            VetColors.closedLight,
            VetColors.closed,
            'Closed'
          ),
      };

  @override
  Widget build(BuildContext context) {
    final c = doctorCase;
    final (urgColor, urgLabel) = _urgencyAttrs;
    final (statusBg, statusFg, statusLabel) = _statusAttrs;
    final isEmergency = c.urgency == CaseUrgency.emergency;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: vetCard(
          highlight: isEmergency,
          borderColor:
              isEmergency ? VetColors.emergency.withValues(alpha: 0.5) : null,
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.farmName,
                        style: const TextStyle(
                          color: VetColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        c.farmerName,
                        style: const TextStyle(
                            color: VetColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusFg.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                        color: statusFg,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Flock info row
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _infoChip(Icons.egg_outlined, '${c.flockSize.toString()} birds',
                    VetColors.textSecondary),
                _infoChip(Icons.calendar_today_outlined,
                    '${c.birdAgeWeeks}w old', VetColors.textSecondary),
                _infoChip(Icons.pets, c.breed, VetColors.textSecondary),
                if (c.mortalityCount > 0)
                  _infoChip(
                    Icons.warning_amber,
                    '${c.mortalityCount} dead',
                    VetColors.red,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // Disease tags
            if (c.diseaseTags.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: c.diseaseTags
                    .map((tag) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: VetColors.surface2,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(
                              color: VetColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: VetColors.divider),
            const SizedBox(height: 8),
            Row(
              children: [
                vetChip(urgLabel, urgColor, urgColor, fontSize: 10),
                const SizedBox(width: 8),
                if (c.prescription != null)
                  _infoChip(
                      Icons.medication_outlined, 'Rx', VetColors.secondary),
                const Spacer(),
                Text(
                  _formatDate(c.createdAt),
                  style: const TextStyle(color: VetColors.grey, fontSize: 11),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_ios,
                    size: 12, color: VetColors.grey),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      );

  String _formatDate(DateTime d) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasSearch;
  const _EmptyState({required this.hasSearch});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasSearch ? Icons.search_off : Icons.folder_open_outlined,
            size: 52,
            color: VetColors.grey.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            hasSearch ? 'No matching cases found' : 'No cases yet',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: VetColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasSearch
                ? 'Try a different search term.'
                : 'Case notes from consultations will appear here.',
            style: const TextStyle(fontSize: 13, color: VetColors.grey),
          ),
        ],
      ),
    );
  }
}

// ── Case Detail Screen ────────────────────────────────────────────────────────

class CaseDetailScreen extends StatelessWidget {
  final String caseId;
  const CaseDetailScreen({super.key, required this.caseId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DoctorSession.instance,
      builder: (context, _) {
        final c = DoctorSession.instance.findCase(caseId);
        if (c == null) {
          return const Scaffold(body: Center(child: Text('Case not found.')));
        }
        return Scaffold(
          backgroundColor: VetColors.bg,
          appBar: AppBar(
            backgroundColor: VetColors.appBar,
            foregroundColor: Colors.white,
            title: Text(
              c.farmName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            actions: [
              _StatusUpdateMenu(doctorCase: c),
              const SizedBox(width: 8),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CaseHeader(doctorCase: c),
                const SizedBox(height: 16),
                _FlockInfo(doctorCase: c),
                const SizedBox(height: 16),
                _SymptomsSection(symptoms: c.symptoms),
                const SizedBox(height: 16),
                if (true) ...[
                  _DetailSection(
                    icon: Icons.biotech_outlined,
                    title: 'Diagnosis',
                    content: _noteText(c.diagnosis),
                    color: VetColors.open,
                  ),
                  const SizedBox(height: 12),
                ],
                if (true) ...[
                  _DetailSection(
                    icon: Icons.healing_outlined,
                    title: 'Treatment Plan',
                    content: _noteText(c.treatmentPlan),
                    color: VetColors.available,
                  ),
                  const SizedBox(height: 12),
                ],
                if ((c.warnings ?? '').trim().isNotEmpty) ...[
                  _WarningSection(warning: c.warnings!),
                  const SizedBox(height: 12),
                ],
                _FarmNotes(doctorCase: c),
                const SizedBox(height: 16),
                if (c.prescription != null) ...[
                  _PrescriptionPreview(prescription: c.prescription!),
                  const SizedBox(height: 16),
                ],
                if (true) ...[
                  _DetailSection(
                    icon: Icons.checklist_outlined,
                    title: 'Next Steps',
                    content: _noteText(c.nextSteps),
                    color: VetColors.followUpColor,
                  ),
                  const SizedBox(height: 16),
                ],
                _NotesToolbar(doctorCase: c),
                const SizedBox(height: 16),
                _CaseActions(doctorCase: c),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CaseHeader extends StatelessWidget {
  final DoctorCase doctorCase;
  const _CaseHeader({required this.doctorCase});

  @override
  Widget build(BuildContext context) {
    final c = doctorCase;
    final (urgBg, urgFg, urgLabel) = switch (c.urgency) {
      CaseUrgency.routine => (
          VetColors.routineLight,
          VetColors.routine,
          'Routine'
        ),
      CaseUrgency.moderate => (
          VetColors.moderateLight,
          VetColors.moderate,
          'Moderate'
        ),
      CaseUrgency.urgent => (VetColors.urgentLight, VetColors.urgent, 'Urgent'),
      CaseUrgency.emergency => (
          VetColors.emergencyLight,
          VetColors.emergency,
          'Emergency'
        ),
    };
    final (statusBg, statusFg, statusLabel) = switch (c.status) {
      CaseStatus.open => (VetColors.openLight, VetColors.open, 'Open'),
      CaseStatus.inProgress => (
          VetColors.inProgressLight,
          VetColors.inProgress,
          'In Progress'
        ),
      CaseStatus.followUp => (
          VetColors.followUpLight,
          VetColors.followUpColor,
          'Follow-Up'
        ),
      CaseStatus.closed => (VetColors.closedLight, VetColors.closed, 'Closed'),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: vetCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.farmName,
                      style: const TextStyle(
                        color: VetColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Farmer: ${c.farmerName}',
                      style: const TextStyle(
                          color: VetColors.textSecondary, fontSize: 13),
                    ),
                    Text(
                      'Case #${c.id}',
                      style:
                          const TextStyle(color: VetColors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: urgBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: urgFg.withValues(alpha: 0.35)),
                    ),
                    child: Text(urgLabel,
                        style: TextStyle(
                            color: urgFg,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: statusFg.withValues(alpha: 0.35)),
                    ),
                    child: Text(statusLabel,
                        style: TextStyle(
                            color: statusFg,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
          if (c.diseaseTags.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: VetColors.divider),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: c.diseaseTags
                  .map((tag) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: VetColors.surface2,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(tag,
                            style: const TextStyle(
                                color: VetColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500)),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _FlockInfo extends StatelessWidget {
  final DoctorCase doctorCase;
  const _FlockInfo({required this.doctorCase});

  @override
  Widget build(BuildContext context) {
    final c = doctorCase;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: vetCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
              icon: Icons.egg_outlined, title: 'Flock Information'),
          const SizedBox(height: 12),
          _infoRow('Farm Name', c.farmName),
          _infoRow('Flock Size', '${c.flockSize.toString()} birds'),
          _infoRow('Bird Age', '${c.birdAgeWeeks} weeks'),
          _infoRow('Breed', c.breed),
          _infoRow('Mortality Count', '${c.mortalityCount} birds',
              color: c.mortalityCount > 0 ? VetColors.red : null),
          if (c.vaccineHistory != null)
            _infoRow('Vaccine History', c.vaccineHistory!),
          if (c.feedNotes != null) _infoRow('Feed Notes', c.feedNotes!),
          if (c.biosecurityNotes != null)
            _infoRow('Biosecurity', c.biosecurityNotes!),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: const TextStyle(
                    color: VetColors.textSecondary, fontSize: 12),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  color: color ?? VetColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
}

class _SymptomsSection extends StatelessWidget {
  final List<String> symptoms;
  const _SymptomsSection({required this.symptoms});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: vetCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
              icon: Icons.sick_outlined, title: 'Observed Symptoms'),
          const SizedBox(height: 12),
          ...symptoms.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: VetColors.urgent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s,
                        style: const TextStyle(
                            color: VetColors.textPrimary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;
  final Color color;
  const _DetailSection({
    required this.icon,
    required this.title,
    required this.content,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: vetCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(icon: icon, title: title, color: color),
          const SizedBox(height: 10),
          Text(
            content,
            style: const TextStyle(
              color: VetColors.textPrimary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningSection extends StatelessWidget {
  final String warning;
  const _WarningSection({required this.warning});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration:
          vetCard(borderColor: VetColors.emergency.withValues(alpha: 0.4)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: VetColors.emergency, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Warning',
                  style: TextStyle(
                    color: VetColors.emergency,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  warning,
                  style: const TextStyle(
                    color: VetColors.textPrimary,
                    fontSize: 13,
                    height: 1.4,
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

class _FarmNotes extends StatelessWidget {
  final DoctorCase doctorCase;
  const _FarmNotes({required this.doctorCase});

  @override
  Widget build(BuildContext context) {
    final c = doctorCase;
    final hasNotes = c.feedNotes != null ||
        c.vaccineHistory != null ||
        c.biosecurityNotes != null;
    if (!hasNotes) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: vetCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
              icon: Icons.agriculture_outlined, title: 'Farm Management Notes'),
          const SizedBox(height: 10),
          if (c.feedNotes != null) ...[
            _noteBlock('Feed Notes', c.feedNotes!, Icons.restaurant_outlined,
                VetColors.available),
            const SizedBox(height: 10),
          ],
          if (c.vaccineHistory != null) ...[
            _noteBlock('Vaccine History', c.vaccineHistory!,
                Icons.vaccines_outlined, VetColors.secondary),
            const SizedBox(height: 10),
          ],
          if (c.biosecurityNotes != null)
            _noteBlock('Biosecurity', c.biosecurityNotes!,
                Icons.security_outlined, VetColors.open),
        ],
      ),
    );
  }

  Widget _noteBlock(String title, String content, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(content,
                      style: const TextStyle(
                          color: VetColors.textPrimary,
                          fontSize: 12,
                          height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _PrescriptionPreview extends StatelessWidget {
  final DoctorPrescription prescription;
  const _PrescriptionPreview({required this.prescription});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration:
          vetCard(borderColor: VetColors.secondary.withValues(alpha: 0.4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _SectionTitle(
                  icon: Icons.medication_outlined,
                  title: 'Prescription',
                  color: VetColors.secondary),
              const Spacer(),
              Text(
                '#${prescription.id}',
                style: const TextStyle(color: VetColors.grey, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...prescription.medicines.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: const BoxDecoration(
                        color: VetColors.secondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.name,
                            style: const TextStyle(
                              color: VetColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${m.dosage} · ${m.duration}',
                            style: const TextStyle(
                                color: VetColors.textSecondary, fontSize: 12),
                          ),
                          if (m.notes != null)
                            Text(
                              m.notes!,
                              style: const TextStyle(
                                  color: VetColors.grey, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          if (prescription.dosageNotes != null) ...[
            const Divider(height: 16, color: VetColors.divider),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 14, color: VetColors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    prescription.dosageNotes!,
                    style: const TextStyle(
                        color: VetColors.textSecondary,
                        fontSize: 12,
                        height: 1.4),
                  ),
                ),
              ],
            ),
          ],
          if (prescription.referredTo != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: VetColors.followUpLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.open_in_new,
                      size: 14, color: VetColors.followUpColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Referred to: ${prescription.referredTo}',
                      style: const TextStyle(
                        color: VetColors.followUpColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CaseActions extends StatelessWidget {
  final DoctorCase doctorCase;
  const _CaseActions({required this.doctorCase});

  @override
  Widget build(BuildContext context) {
    final c = doctorCase;
    return Column(
      children: [
        if (c.status != CaseStatus.closed) _actionRow(context),
        const SizedBox(height: 10),
        if (c.status == CaseStatus.inProgress && c.followUpDate == null)
          OutlinedButton.icon(
            onPressed: () => _setFollowUp(context),
            icon: const Icon(Icons.event_outlined, size: 16),
            label: const Text('Set Follow-Up Date'),
            style: OutlinedButton.styleFrom(
              foregroundColor: VetColors.followUpColor,
              side: BorderSide(
                  color: VetColors.followUpColor.withValues(alpha: 0.5)),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
      ],
    );
  }

  Widget _actionRow(BuildContext context) {
    final c = doctorCase;
    return Row(
      children: [
        if (c.status == CaseStatus.open)
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                DoctorSession.instance
                    .updateCaseStatus(c.id, CaseStatus.inProgress);
                _snack(context, 'Case moved to In Progress.',
                    VetColors.inProgress);
              },
              icon: const Icon(Icons.play_arrow_outlined, size: 16),
              label: const Text('Start Case'),
              style: ElevatedButton.styleFrom(
                backgroundColor: VetColors.inProgress,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        if (c.status == CaseStatus.inProgress) ...[
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                DoctorSession.instance
                    .updateCaseStatus(c.id, CaseStatus.followUp);
                _snack(context, 'Case moved to Follow-Up.',
                    VetColors.followUpColor);
              },
              icon: const Icon(Icons.event_repeat, size: 16),
              label: const Text('Follow-Up'),
              style: ElevatedButton.styleFrom(
                backgroundColor: VetColors.followUpColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                DoctorSession.instance
                    .updateCaseStatus(c.id, CaseStatus.closed);
                _snack(context, 'Case closed.', VetColors.available);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('Close Case'),
              style: ElevatedButton.styleFrom(
                backgroundColor: VetColors.available,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
        if (c.status == CaseStatus.followUp)
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                DoctorSession.instance
                    .updateCaseStatus(c.id, CaseStatus.closed);
                _snack(
                    context, 'Case closed successfully.', VetColors.available);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('Close Case'),
              style: ElevatedButton.styleFrom(
                backgroundColor: VetColors.available,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _setFollowUp(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 5)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (date != null && context.mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 10, minute: 0),
      );
      if (time == null) return;
      final scheduled =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
      DoctorSession.instance.setFollowUpDate(doctorCase.id, scheduled);
      if (context.mounted) {
        _snack(
            context,
            'Follow-up set for ${_fmt(scheduled)} at ${time.format(context)}.',
            VetColors.followUpColor);
      }
    }
  }

  String _fmt(DateTime d) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  void _snack(BuildContext context, String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }
}

class _StatusUpdateMenu extends StatelessWidget {
  final DoctorCase doctorCase;
  const _StatusUpdateMenu({required this.doctorCase});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<CaseStatus>(
      onSelected: (s) {
        DoctorSession.instance.updateCaseStatus(doctorCase.id, s);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Status updated to ${_label(s)}.'),
          backgroundColor: VetColors.secondary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ));
      },
      icon: const Icon(Icons.more_vert, color: Colors.white),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      itemBuilder: (_) => CaseStatus.values
          .where((s) => s != doctorCase.status)
          .map((s) => PopupMenuItem(
                value: s,
                child: Text(_label(s), style: TextStyle(color: _color(s))),
              ))
          .toList(),
    );
  }

  String _label(CaseStatus s) => switch (s) {
        CaseStatus.open => 'Mark Open',
        CaseStatus.inProgress => 'Mark In Progress',
        CaseStatus.followUp => 'Move to Follow-Up',
        CaseStatus.closed => 'Close Case',
      };

  Color _color(CaseStatus s) => switch (s) {
        CaseStatus.open => VetColors.open,
        CaseStatus.inProgress => VetColors.inProgress,
        CaseStatus.followUp => VetColors.followUpColor,
        CaseStatus.closed => VetColors.closed,
      };
}

// ── Shared Section Title ──────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  const _SectionTitle({
    required this.icon,
    required this.title,
    this.color = VetColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
              color: color, fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}


String _noteText(String? v) =>
    (v == null || v.trim().isEmpty) ? 'Not recorded yet.' : v;

/// Edit / history controls for the case notes (NF-6). Only the case's own
/// doctor sees this screen; the server enforces ownership, the consultation
/// state and the closed-case lock, and records every edit.
class _NotesToolbar extends StatelessWidget {
  final DoctorCase doctorCase;
  const _NotesToolbar({required this.doctorCase});

  @override
  Widget build(BuildContext context) {
    final closed = doctorCase.status == CaseStatus.closed;
    return Wrap(spacing: 10, runSpacing: 8, children: [
      FilledButton.icon(
        key: const Key('editNotesButton'),
        onPressed: closed
            ? null
            : () async {
                final saved = await showDialog<bool>(
                  context: context,
                  builder: (_) => NotesEditorDialog(doctorCase: doctorCase),
                );
                if (saved == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      key: Key('notesSavedSnack'),
                      content: Text('Case notes saved'),
                      duration: Duration(seconds: 2)));
                }
              },
        icon: const Icon(Icons.edit_note, size: 18),
        label: Text(closed ? 'Closed - reopen to edit notes' : 'Edit notes'),
      ),
      OutlinedButton.icon(
        key: const Key('notesHistoryButton'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => NotesHistoryDialog(caseId: doctorCase.id),
        ),
        icon: const Icon(Icons.history, size: 18),
        label: const Text('Notes history'),
      ),
    ]);
  }
}

class NotesEditorDialog extends StatefulWidget {
  final DoctorCase doctorCase;
  const NotesEditorDialog({super.key, required this.doctorCase});

  @override
  State<NotesEditorDialog> createState() => _NotesEditorDialogState();
}

class _NotesEditorDialogState extends State<NotesEditorDialog> {
  late DoctorCase _case;
  late Map<String, TextEditingController> _c;
  late Map<String, String> _initial;
  bool _saving = false;
  bool _conflict = false;
  String? _error;

  static const _labels = {
    'diagnosis': 'Diagnosis',
    'treatment_plan': 'Treatment plan',
    'warnings': 'Warnings',
    'next_steps': 'Next steps',
    'feed_notes': 'Feed notes',
    'vaccine_history': 'Vaccine history',
    'biosecurity_notes': 'Biosecurity notes',
  };
  // Once recorded, these two must be edited, never blanked (the server enforces it too).
  static const _required = {'diagnosis', 'treatment_plan'};
  static const _maxLen = 5000;

  @override
  void initState() {
    super.initState();
    _case = widget.doctorCase;
    _load(_case);
  }

  void _load(DoctorCase d) {
    final initial = {
      'diagnosis': d.diagnosis,
      'treatment_plan': d.treatmentPlan,
      'warnings': d.warnings,
      'next_steps': d.nextSteps,
      'feed_notes': d.feedNotes,
      'vaccine_history': d.vaccineHistory,
      'biosecurity_notes': d.biosecurityNotes,
    };
    _initial = {for (final k in _labels.keys) k: (initial[k] ?? '').trim()};
    _c = {for (final k in _labels.keys) k: TextEditingController(text: _initial[k])};
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Only the fields the doctor actually changed are sent, so untouched notes
  /// can never be replaced by a stale copy.
  Map<String, String> get _changed => {
        for (final e in _c.entries)
          if (e.value.text.trim() != _initial[e.key]) e.key: e.value.text.trim(),
      };

  String? _fieldError(String key) {
    final v = _c[key]!.text.trim();
    if (v.length > _maxLen) return 'Too long ($_maxLen characters maximum).';
    if (_required.contains(key) && v.isEmpty && (_initial[key] ?? '').isNotEmpty) {
      return '${_labels[key]} cannot be emptied once recorded - edit it instead.';
    }
    return null;
  }

  bool get _valid => _labels.keys.every((k) => _fieldError(k) == null);

  Future<void> _save() async {
    final changed = _changed;
    if (changed.isEmpty || !_valid || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
      _conflict = false;
    });
    try {
      await DoctorSession.instance.saveCaseNotes(_case, changed);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final conflict = e is AuthException && e.statusCode == 409 && e.data['code'] == 'note_conflict';
      setState(() {
        _saving = false;
        _conflict = conflict;
        _error = e is AuthException ? e.message : e.toString();
      });
    }
  }

  Future<void> _reloadLatest() async {
    setState(() => _saving = true);
    try {
      await DoctorSession.instance.refresh();
    } catch (_) {/* shown below if the case is gone */}
    final latest = DoctorSession.instance.findCase(_case.id);
    if (!mounted) return;
    if (latest == null) {
      setState(() {
        _saving = false;
        _error = 'Could not reload the case.';
      });
      return;
    }
    for (final c in _c.values) {
      c.dispose();
    }
    setState(() {
      _case = latest;
      _load(latest);
      _saving = false;
      _conflict = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final changed = _changed;
    return AlertDialog(
      title: const Text('Edit case notes'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in _labels.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  key: Key('note_${e.key}'),
                  controller: _c[e.key],
                  enabled: !_saving,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: _maxLen,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: e.value,
                    border: const OutlineInputBorder(),
                    errorText: _fieldError(e.key),
                  ),
                ),
              ),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_error!,
                      key: Key(_conflict ? 'notesConflict' : 'notesError'),
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                  if (_conflict)
                    TextButton(
                      key: const Key('reloadLatestNotes'),
                      onPressed: _saving ? null : _reloadLatest,
                      child: const Text('Reload the latest notes (discard my edits)'),
                    ),
                ]),
              ),
            if (changed.isEmpty && _error == null)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('No changes yet.',
                    key: Key('notesNoChanges'), style: TextStyle(color: Colors.black54, fontSize: 12)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('saveNotesButton'),
          onPressed: (_saving || changed.isEmpty || !_valid || _conflict) ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(changed.isEmpty ? 'Save notes' : 'Save ${changed.length} change${changed.length == 1 ? '' : 's'}'),
        ),
      ],
    );
  }
}

class NotesHistoryDialog extends StatefulWidget {
  final String caseId;
  const NotesHistoryDialog({super.key, required this.caseId});

  @override
  State<NotesHistoryDialog> createState() => _NotesHistoryDialogState();
}

class _NotesHistoryDialogState extends State<NotesHistoryDialog> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = DoctorSession.instance.caseHistory(widget.caseId);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Case notes history'),
      content: SizedBox(
        width: 460,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                  height: 60, child: Center(child: CircularProgressIndicator(key: Key('notesHistoryLoading'))));
            }
            if (snap.hasError) {
              final e = snap.error;
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Text(e is AuthException ? e.message : '$e',
                    key: const Key('notesHistoryError'), style: const TextStyle(color: Colors.red)),
                TextButton(
                  key: const Key('notesHistoryRetry'),
                  onPressed: () {
                    final next = DoctorSession.instance.caseHistory(widget.caseId);
                    setState(() {
                      _future = next;
                    });
                  },
                  child: const Text('Retry'),
                ),
              ]);
            }
            final rows = snap.data ?? const [];
            if (rows.isEmpty) {
              return const Text('No edits recorded yet.', key: Key('notesHistoryEmpty'));
            }
            return SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Revision ${r['revision'] ?? ''} - ${r['editor'] ?? 'Unknown'} - ${r['created_at']}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      for (final ch in ((r['changes'] as Map?) ?? const {}).entries)
                        Text('${ch.key}: "${(ch.value as Map)['from'] ?? ''}" -> "${(ch.value as Map)['to'] ?? ''}"',
                            style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
              ]),
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
