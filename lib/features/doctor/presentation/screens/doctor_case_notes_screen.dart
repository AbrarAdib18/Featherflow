import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/chat/chat_core.dart';
import '../../../../core/documents/prescription_pdf_viewer.dart';
import '../../../../core/network/auth_service.dart';
import '../../data/models/doctor_models.dart';
import '../../data/services/doctor_session.dart';
import '../doctor_theme.dart';

// All case work happens on the individual Case page (DOCTOR_CASE_PAGE_FIX.md):
//
//   open      → edit diagnosis / treatment / … → Save → Close case
//   closed    → Mark as Complete (or Reopen to edit)
//   completed → Issue prescription & advice
//   prescribed→ the issued prescription (a revision may be issued)
//
// The stage comes from the server, which also enforces it.

class DoctorCaseNotesScreen extends StatefulWidget {
  const DoctorCaseNotesScreen({super.key});

  @override
  State<DoctorCaseNotesScreen> createState() => _DoctorCaseNotesScreenState();
}

/// Case list filter: null = all.
enum _CaseFilter { open, closed, completed, awaiting, ended }

class _DoctorCaseNotesScreenState extends State<DoctorCaseNotesScreen> {
  _CaseFilter? _filter;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static bool _matches(_CaseFilter? f, DoctorCase c) => switch (f) {
        null => true,
        _CaseFilter.open => c.stage == CaseStage.open,
        _CaseFilter.closed => c.stage == CaseStage.closed,
        _CaseFilter.completed =>
          c.stage == CaseStage.completed || c.stage == CaseStage.prescribed,
        _CaseFilter.awaiting => c.stage == CaseStage.awaitingAcceptance,
        _CaseFilter.ended => c.stage == CaseStage.ended,
      };

  List<DoctorCase> get _filtered {
    final session = DoctorSession.instance;
    final list = (_search.isNotEmpty
            ? session.searchCases(_search)
            : session.cases.toList())
        .where((c) => _matches(_filter, c))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DoctorSession.instance,
      builder: (context, _) {
        final session = DoctorSession.instance;
        final cases = _filtered;
        return Scaffold(
          backgroundColor: VetColors.bg,
          appBar: AppBar(
            backgroundColor: VetColors.appBar,
            automaticallyImplyLeading: false,
            title: const Text(
              'Cases',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: session.refresh,
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
                count: (f) => session.cases.where((c) => _matches(f, c)).length,
                onChanged: (f) => setState(() => _filter = f),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: session.refresh,
                  child: cases.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: 320,
                              child: _EmptyState(
                                hasSearch: _search.isNotEmpty,
                                error: session.cases.isEmpty ? session.error : null,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          key: const Key('doctorCaseList'),
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: cases.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _CaseCard(
                            doctorCase: cases[i],
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      CaseDetailScreen(caseId: cases[i].id)),
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Stage presentation ────────────────────────────────────────────────────────

/// (label, foreground, background) — every pair is ≥4.5:1 contrast.
(String, Color, Color) caseStageStyle(DoctorCase c) => switch (c.stage) {
      CaseStage.awaitingAcceptance => (
          'Awaiting acceptance',
          VetColors.amberText,
          VetColors.amberLight
        ),
      CaseStage.open => ('Open', VetColors.open, VetColors.openLight),
      CaseStage.closed => (
          'Closed · awaiting completion',
          VetColors.followUpColor,
          VetColors.followUpLight
        ),
      CaseStage.completed => (
          'Completed',
          VetColors.available,
          VetColors.availableLight
        ),
      CaseStage.prescribed => (
          'Prescription issued',
          VetColors.available,
          VetColors.availableLight
        ),
      CaseStage.ended => (
          switch (c.consultationStatus) {
            'rejected' => 'Rejected',
            'cancelled' => 'Cancelled',
            'no_show' => 'No-show',
            _ => 'Ended',
          },
          VetColors.textSecondary,
          VetColors.surface2
        ),
    };

class CaseStageChip extends StatelessWidget {
  const CaseStageChip({super.key, required this.doctorCase});
  final DoctorCase doctorCase;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = caseStageStyle(doctorCase);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Text(label,
          style:
              TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w700)),
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
  final _CaseFilter? selected;
  final int Function(_CaseFilter?) count;
  final ValueChanged<_CaseFilter?> onChanged;
  const _FilterBar(
      {required this.selected, required this.count, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final filters = <(_CaseFilter?, String, Color)>[
      (null, 'All', VetColors.primary),
      (_CaseFilter.open, 'Open', VetColors.open),
      (_CaseFilter.closed, 'Closed', VetColors.followUpColor),
      (_CaseFilter.completed, 'Completed', VetColors.available),
      (_CaseFilter.awaiting, 'Awaiting acceptance', VetColors.amberText),
      (_CaseFilter.ended, 'Ended', VetColors.textSecondary),
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
            final (filter, label, color) = f;
            final isSel = selected == filter;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onChanged(filter),
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
                          '${count(filter)}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isSel ? color : VetColors.textSecondary,
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
        CaseUrgency.moderate => (VetColors.busy, 'Moderate'),
        CaseUrgency.urgent => (VetColors.urgent, 'Urgent'),
        CaseUrgency.emergency => (VetColors.emergency, 'Emergency'),
      };

  @override
  Widget build(BuildContext context) {
    final c = doctorCase;
    final (urgColor, urgLabel) = _urgencyAttrs;
    final isEmergency = c.urgency == CaseUrgency.emergency;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
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
                        c.farmName.isEmpty ? c.farmerName : c.farmName,
                        style: const TextStyle(
                          color: VetColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        c.farmerName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: VetColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                CaseStageChip(doctorCase: c),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _infoChip(Icons.egg_outlined, '${c.flockSize} birds',
                    VetColors.textSecondary),
                _infoChip(Icons.calendar_today_outlined,
                    '${c.birdAgeWeeks}w old', VetColors.textSecondary),
                if (c.breed.isNotEmpty)
                  _infoChip(Icons.pets, c.breed, VetColors.textSecondary),
                if (c.mortalityCount > 0)
                  _infoChip(Icons.warning_amber, '${c.mortalityCount} dead',
                      VetColors.red),
              ],
            ),
            if (c.diagnosis != null && c.diagnosis!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Diagnosis: ${c.diagnosis}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: VetColors.textPrimary, fontSize: 12, height: 1.4),
              ),
            ],
            if (c.diseaseTags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: c.diseaseTags.map(_tag).toList(),
              ),
            ],
            const SizedBox(height: 10),
            const Divider(height: 1, color: VetColors.divider),
            const SizedBox(height: 8),
            Row(
              children: [
                vetChip(urgLabel, urgColor, urgColor, fontSize: 10),
                const SizedBox(width: 8),
                if (c.prescription != null)
                  _infoChip(Icons.medication_outlined, 'Rx', VetColors.available),
                const Spacer(),
                Text(
                  DateFormat('d MMM yyyy').format(c.createdAt.toLocal()),
                  style: const TextStyle(
                      color: VetColors.textSecondary, fontSize: 11),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_ios,
                    size: 12, color: VetColors.textSecondary),
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
}

Widget _tag(String tag) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: VetColors.surface2,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(tag,
          style: const TextStyle(
              color: VetColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500)),
    );

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasSearch;
  final String? error;
  const _EmptyState({required this.hasSearch, this.error});

  @override
  Widget build(BuildContext context) {
    final failed = error != null && !hasSearch;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              failed
                  ? Icons.cloud_off_outlined
                  : hasSearch
                      ? Icons.search_off
                      : Icons.folder_open_outlined,
              size: 52,
              color: VetColors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              failed
                  ? 'Could not load your cases'
                  : hasSearch
                      ? 'No matching cases found'
                      : 'No cases here',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: VetColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              failed
                  ? error!.split('\n').first
                  : hasSearch
                      ? 'Try a different search term.'
                      : 'A case is created when a farmer books a consultation.',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 13, color: VetColors.textSecondary),
            ),
            if (failed) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: DoctorSession.instance.refresh,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Case page ─────────────────────────────────────────────────────────────────

/// One editable case field, keyed by its API name.
class _Field {
  const _Field(this.key, this.label, this.icon, this.color,
      {this.multiline = true, this.requiredToClose = false, this.hint = ''});
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  final bool multiline;
  final bool requiredToClose;
  final String hint;
}

const _diagnosis = _Field('diagnosis', 'Diagnosis', Icons.biotech_outlined,
    VetColors.open,
    requiredToClose: true, hint: 'Your clinical diagnosis');
const _treatment = _Field('treatment_plan', 'Treatment Plan',
    Icons.healing_outlined, VetColors.available,
    requiredToClose: true, hint: 'Medication, dosing, management changes…');
const _warnings = _Field('warnings', 'Warning',
    Icons.warning_amber_rounded, VetColors.emergency,
    hint: 'Withdrawal periods, risks, things to avoid');
const _tags = _Field('disease_tags', 'Disease Tags', Icons.sell_outlined,
    VetColors.textSecondary,
    multiline: false, hint: 'e.g. coccidiosis, enteritis (comma-separated)');
const _feed = _Field('feed_notes', 'Feed Notes', Icons.restaurant_outlined,
    VetColors.available);
const _vaccine = _Field('vaccine_history', 'Vaccine History',
    Icons.vaccines_outlined, VetColors.routine);
const _biosecurity = _Field('biosecurity_notes', 'Biosecurity',
    Icons.security_outlined, VetColors.open);
const _nextSteps = _Field('next_steps', 'Next Steps', Icons.checklist_outlined,
    VetColors.followUpColor,
    hint: 'What the farmer should do next');

const _allFields = [
  _diagnosis,
  _treatment,
  _warnings,
  _tags,
  _feed,
  _vaccine,
  _biosecurity,
  _nextSteps,
];

enum _SaveState { idle, saving, saved, failed }

class CaseDetailScreen extends StatefulWidget {
  final String caseId;
  const CaseDetailScreen({super.key, required this.caseId});

  @override
  State<CaseDetailScreen> createState() => _CaseDetailScreenState();
}

class _CaseDetailScreenState extends State<CaseDetailScreen> {
  final _session = DoctorSession.instance;
  final Map<String, TextEditingController> _ctrl = {
    for (final f in _allFields) f.key: TextEditingController(),
  };

  /// Last server value of each field; a field is dirty when its text differs.
  final Map<String, String> _baseline = {};
  bool _seeded = false;

  _SaveState _saveState = _SaveState.idle;
  String? _saveError;
  Map<String, String> _fieldErrors = const {};

  bool _loading = false;
  String? _loadError;
  bool _prescribing = false;

  @override
  void initState() {
    super.initState();
    for (final c in _ctrl.values) {
      c.addListener(_onEdit);
    }
    final known = _session.findCase(widget.caseId);
    if (known != null) _absorb(known);
    _session.addListener(_onSession);
    // Always re-read on open: the list may be up to a poll interval old.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  DoctorCase? get _case => _session.findCase(widget.caseId);

  void _onEdit() {
    if (!mounted) return;
    setState(() {
      if (_saveState == _SaveState.saved && _dirty.isNotEmpty) {
        _saveState = _SaveState.idle;
      }
    });
  }

  void _onSession() {
    final c = _case;
    if (c != null && mounted) _absorb(c);
  }

  /// Takes the server's values. Fields the doctor is editing keep their text
  /// (a background refresh never overwrites unsaved typing).
  void _absorb(DoctorCase c) {
    for (final f in _allFields) {
      final server = c.fieldValue(f.key);
      final ctrl = _ctrl[f.key]!;
      if (!_seeded || ctrl.text == (_baseline[f.key] ?? '')) {
        if (ctrl.text != server) ctrl.text = server;
      }
      _baseline[f.key] = server;
    }
    _seeded = true;
  }

  static List<String> _splitTags(String text) => text
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  String _normalized(String key, String text) =>
      key == 'disease_tags' ? _splitTags(text).join(', ') : text.trim();

  /// API name → value for every field whose text differs from the server.
  Map<String, dynamic> get _dirty => {
        for (final f in _allFields)
          if (_normalized(f.key, _ctrl[f.key]!.text) !=
              _normalized(f.key, _baseline[f.key] ?? ''))
            f.key: f.key == 'disease_tags'
                ? _splitTags(_ctrl[f.key]!.text)
                : _ctrl[f.key]!.text.trim(),
      };

  Future<void> _reload() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _session.loadCase(widget.caseId);
    } catch (e) {
      _loadError = _message(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _message(Object e) =>
      e is AuthException ? e.message : e.toString().replaceFirst('Exception: ', '');

  Future<void> _save() async {
    final changes = _dirty;
    if (changes.isEmpty || _session.isCaseBusy(widget.caseId)) return;
    setState(() {
      _saveState = _SaveState.saving;
      _saveError = null;
      _fieldErrors = const {};
    });
    try {
      await _session.saveCaseFields(widget.caseId, changes);
      if (mounted) setState(() => _saveState = _SaveState.saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saveState = _SaveState.failed;
        _saveError = _message(e);
        _fieldErrors = e is AuthException ? e.fieldErrors : const {};
      });
    }
  }

  Future<void> _closeCase() async {
    final missing = {
      for (final f in [_diagnosis, _treatment])
        if (_ctrl[f.key]!.text.trim().isEmpty)
          f.key: 'Required before the case can be closed.',
    };
    if (missing.isNotEmpty) {
      setState(() => _fieldErrors = missing);
      _snack('Enter a diagnosis and treatment plan before closing the case.',
          VetColors.red);
      return;
    }
    final ok = await _confirm(
      title: 'Close this case?',
      body: 'Unsaved changes are saved with it. You can reopen the case '
          'until the consultation is marked as complete.',
      action: 'Close case',
      key: const Key('caseConfirmClose'),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _saveState = _SaveState.saving;
      _saveError = null;
      _fieldErrors = const {};
    });
    try {
      await _session.closeCase(widget.caseId, _dirty);
      if (!mounted) return;
      setState(() => _saveState = _SaveState.saved);
      _snack('Case closed. Mark the consultation as complete when ready.',
          VetColors.available);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saveState = _SaveState.failed;
        _saveError = _message(e);
        _fieldErrors = e is AuthException ? e.fieldErrors : const {};
      });
    }
  }

  Future<void> _reopen() async {
    try {
      await _session.reopenCase(widget.caseId);
      if (mounted) _snack('Case reopened for editing.', VetColors.open);
    } catch (e) {
      if (mounted) _snack(_message(e), VetColors.red);
    }
  }

  Future<void> _markComplete() async {
    final ok = await _confirm(
      title: 'Mark consultation as complete?',
      body: 'This releases the diagnosis and treatment plan to the farmer, '
          'generates the consultation receipt and notifies them. '
          'It cannot be undone.',
      action: 'Mark as Complete',
      key: const Key('caseConfirmComplete'),
    );
    if (ok != true || !mounted) return;
    try {
      await _session.completeCase(widget.caseId);
      if (mounted) {
        _snack('Consultation marked as complete. You can now issue the '
            'prescription.', VetColors.available);
      }
    } catch (e) {
      if (mounted) _snack(_message(e), VetColors.red);
    }
  }

  Future<String?> _issuePrescription(_PrescriptionDraft draft) async {
    try {
      final updated = await _session.issueCasePrescription(
        widget.caseId,
        medicines: draft.medicines,
        caseAdvice: draft.caseAdvice,
        dosageNotes: draft.dosageNotes,
        followUpInstructions: draft.followUpInstructions,
        referredTo: draft.referredTo,
        followUpAt: draft.followUpAt,
      );
      if (mounted) {
        setState(() => _prescribing = false);
        final rx = updated.prescription;
        if (rx?.emailFailed == true) {
          _snack('Prescription ${rx!.referenceNumber ?? ''} issued. The email could '
              'not be sent; retry it from the prescription card.', VetColors.busy);
        } else {
          _snack('Prescription ${rx?.referenceNumber ?? ''} issued. PDF '
              '${rx?.emailStatus == 'sent' ? 'emailed' : 'is being emailed'} to the farmer.',
              VetColors.available);
        }
      }
      return null;
    } catch (e) {
      return _message(e);
    }
  }

  Future<void> _retryEmail(String prescriptionId) async {
    try {
      final updated =
          await _session.retryPrescriptionEmail(widget.caseId, prescriptionId);
      if (!mounted) return;
      final sent = updated.prescription?.emailStatus == 'sent';
      _snack(sent ? 'Prescription PDF emailed to the farmer.' : 'The email still could not be sent.',
          sent ? VetColors.available : VetColors.red);
    } catch (e) {
      if (mounted) _snack(_message(e), VetColors.red);
    }
  }

  Future<bool?> _confirm(
          {required String title,
          required String body,
          required String action,
          Key? key}) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              key: key,
              style:
                  FilledButton.styleFrom(backgroundColor: VetColors.primary),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action),
            ),
          ],
        ),
      );

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  Future<void> _onBlockedPop() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text('Your edits to this case have not been saved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep editing')),
          TextButton(
              key: const Key('caseDiscardChanges'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard',
                  style: TextStyle(color: VetColors.red))),
        ],
      ),
    );
    if (discard == true && mounted) {
      for (final f in _allFields) {
        _ctrl[f.key]!.text = _baseline[f.key] ?? '';
      }
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final c = _case;
        if (c == null) return _missing();
        final editable = c.editable;
        final dirty = editable && _dirty.isNotEmpty;
        final busy = _session.isCaseBusy(c.id);
        return PopScope(
          canPop: !dirty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _onBlockedPop();
          },
          child: Scaffold(
            backgroundColor: VetColors.surface2,
            appBar: AppBar(
              backgroundColor: VetColors.appBar,
              foregroundColor: Colors.white,
              iconTheme: const IconThemeData(color: Colors.white),
              title: Text(
                c.farmName.isEmpty ? 'Case' : c.farmName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
              actions: [
                IconButton(
                  key: const Key('caseRefresh'),
                  tooltip: 'Reload case',
                  onPressed: _loading ? null : _reload,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                ),
              ],
            ),
            bottomNavigationBar: editable
                ? _SaveBar(
                    state: _saveState,
                    dirty: dirty,
                    busy: busy,
                    error: _saveError,
                    updatedAt: c.updatedAt,
                    onSave: _save,
                  )
                : null,
            body: RefreshIndicator(
              onRefresh: _reload,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_loadError != null)
                          _InlineError(
                            message:
                                'Could not refresh — showing the last loaded '
                                'case. ${_loadError!}',
                            onRetry: _reload,
                          ),
                        _CaseHeader(doctorCase: c),
                        const SizedBox(height: 12),
                        _StageBanner(doctorCase: c),
                        const SizedBox(height: 12),
                        _FlockInfo(doctorCase: c),
                        const SizedBox(height: 12),
                        _SymptomsSection(symptoms: c.symptoms),
                        const SizedBox(height: 12),
                        ..._clinicalSection(c, editable && !busy),
                        if (c.prescription != null) ...[
                          _PrescriptionCard(
                            doctorCase: c,
                            busy: busy,
                            onViewPdf: () => showPrescriptionPdf(context,
                                prescriptionId: c.prescription!.id,
                                reference: c.prescription!.referenceNumber),
                            onRetryEmail: () => _retryEmail(c.prescription!.id),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _actions(c, busy, dirty),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _missing() => Scaffold(
        appBar: AppBar(
          backgroundColor: VetColors.appBar,
          foregroundColor: Colors.white,
          title: const Text('Case',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ),
        body: Center(
          child: _loading || (_loadError == null && !_seeded)
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.folder_off_outlined,
                          size: 48, color: VetColors.grey),
                      const SizedBox(height: 12),
                      Text(
                        _loadError ?? 'Case not found.',
                        key: const Key('caseLoadError'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: VetColors.textPrimary),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const Key('caseRetryLoad'),
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
        ),
      );

  List<Widget> _clinicalSection(DoctorCase c, bool enabled) {
    Widget field(_Field f, {bool inset = false}) => _ClinicalField(
          field: f,
          controller: _ctrl[f.key]!,
          editable: c.editable,
          enabled: enabled,
          inset: inset,
          error: _fieldErrors[f.key],
          savedValue: c.fieldValue(f.key),
        );
    return [
      field(_diagnosis),
      const SizedBox(height: 12),
      field(_treatment),
      const SizedBox(height: 12),
      field(_warnings),
      const SizedBox(height: 12),
      field(_tags),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: vetCard(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle(
                icon: Icons.agriculture_outlined,
                title: 'Farm Management Notes'),
            const SizedBox(height: 10),
            field(_feed, inset: true),
            const SizedBox(height: 10),
            field(_vaccine, inset: true),
            const SizedBox(height: 10),
            field(_biosecurity, inset: true),
          ],
        ),
      ),
      const SizedBox(height: 12),
      field(_nextSteps),
      const SizedBox(height: 12),
    ];
  }

  Widget _actions(DoctorCase c, bool busy, bool dirty) {
    switch (c.stage) {
      case CaseStage.open:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              key: const Key('caseCloseButton'),
              onPressed: busy ? null : _closeCase,
              icon: const Icon(Icons.task_alt, size: 18),
              label: Text(dirty ? 'Save and close case' : 'Close case'),
              style: _primaryButton,
            ),
            if (c.followUpDate == null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: busy ? null : () => _setFollowUp(c),
                icon: const Icon(Icons.event_outlined, size: 16),
                label: const Text('Set follow-up date'),
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
          ],
        );
      case CaseStage.closed:
        return _ActionPanel(
          key: const Key('caseMarkCompletePanel'),
          icon: Icons.check_circle_outline,
          title: 'Mark as Complete',
          body: 'The case is closed. Completing the consultation releases '
              'the clinical results to the farmer, generates the receipt '
              'and lets you issue the prescription and advice.',
          children: [
            ElevatedButton.icon(
              key: const Key('caseMarkCompleteButton'),
              onPressed: busy ? null : _markComplete,
              icon: busy
                  ? const _ButtonSpinner()
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Mark as Complete'),
              style: _primaryButton,
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              key: const Key('caseReopenButton'),
              onPressed: busy ? null : _reopen,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Reopen case to edit'),
              style: TextButton.styleFrom(foregroundColor: VetColors.open),
            ),
          ],
        );
      case CaseStage.completed:
      case CaseStage.prescribed:
        final first = c.stage == CaseStage.completed;
        return _ActionPanel(
          key: const Key('caseIssuePrescriptionPanel'),
          icon: Icons.medication_outlined,
          title: 'Issue Prescription and Advice',
          body: first
              ? 'The consultation is complete. Issue the prescription, '
                  'advice and follow-up for the farmer.'
              : 'A prescription has been issued. You can issue a revised '
                  'one; the farmer sees every prescription.',
          children: [
            if (_prescribing)
              _PrescriptionForm(
                key: const Key('casePrescriptionForm'),
                busy: busy,
                onCancel: () => setState(() => _prescribing = false),
                onSubmit: _issuePrescription,
              )
            else if (first)
              ElevatedButton.icon(
                key: const Key('caseIssuePrescriptionButton'),
                onPressed: () => setState(() => _prescribing = true),
                icon: const Icon(Icons.medication_outlined, size: 18),
                label: const Text('Issue prescription & advice'),
                style: _primaryButton,
              )
            else
              OutlinedButton.icon(
                key: const Key('caseIssueRevisedButton'),
                onPressed: () => setState(() => _prescribing = true),
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text('Issue revised prescription'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: VetColors.primary,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
          ],
        );
      case CaseStage.awaitingAcceptance:
      case CaseStage.ended:
        return const SizedBox.shrink();
    }
  }

  Future<void> _setFollowUp(DoctorCase c) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 5)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 10, minute: 0));
    if (time == null) return;
    final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    _session.setFollowUpDate(c.id, at);
    if (mounted) {
      _snack('Follow-up set for ${DateFormat('d MMM yyyy, h:mm a').format(at)}.',
          VetColors.followUpColor);
    }
  }
}

final _primaryButton = ElevatedButton.styleFrom(
  backgroundColor: VetColors.primary,
  foregroundColor: Colors.white,
  disabledBackgroundColor: VetColors.greyDark,
  disabledForegroundColor: Colors.white,
  minimumSize: const Size.fromHeight(48),
  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
);

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        decoration: BoxDecoration(
          color: VetColors.redLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, color: VetColors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: VetColors.red, fontSize: 12)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      );
}

// ── Save bar ──────────────────────────────────────────────────────────────────

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.state,
    required this.dirty,
    required this.busy,
    required this.error,
    required this.updatedAt,
    required this.onSave,
  });
  final _SaveState state;
  final bool dirty;
  final bool busy;
  final String? error;
  final DateTime? updatedAt;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final saving = state == _SaveState.saving || busy;
    final (String text, Color color) = switch (state) {
      _ when saving => ('Saving…', VetColors.textSecondary),
      _SaveState.failed => ('Not saved: ${error ?? 'please try again.'}', VetColors.red),
      _ when dirty => ('Unsaved changes', VetColors.amberText),
      _SaveState.saved => ('All changes saved', VetColors.available),
      _ => (
          updatedAt == null
              ? 'No changes yet'
              : 'Last saved ${ChatTime.format(updatedAt!)}',
          VetColors.textSecondary
        ),
    };
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              if (saving) ...[
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  text,
                  key: const Key('caseSaveStatus'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: color, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              if (state == _SaveState.failed && !saving && dirty)
                TextButton(
                  key: const Key('caseSaveRetry'),
                  onPressed: onSave,
                  child: const Text('Retry'),
                )
              else
                ElevatedButton.icon(
                  key: const Key('caseSaveButton'),
                  onPressed: dirty && !saving ? onSave : null,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Save changes'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VetColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: VetColors.surface2,
                    disabledForegroundColor: VetColors.textSecondary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sections ──────────────────────────────────────────────────────────────────

class _CaseHeader extends StatelessWidget {
  final DoctorCase doctorCase;
  const _CaseHeader({required this.doctorCase});

  @override
  Widget build(BuildContext context) {
    final c = doctorCase;
    final (urgFg, urgLabel) = switch (c.urgency) {
      CaseUrgency.routine => (VetColors.routine, 'Routine'),
      CaseUrgency.moderate => (VetColors.busy, 'Moderate'),
      CaseUrgency.urgent => (VetColors.urgent, 'Urgent'),
      CaseUrgency.emergency => (VetColors.emergency, 'Emergency'),
    };
    final slot = c.scheduledAt == null
        ? 'No appointment time set'
        : DateFormat('EEE, d MMM yyyy · h:mm a').format(c.scheduledAt!);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: vetCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              KeyedSubtree(
                  key: const Key('caseStageChip'),
                  child: CaseStageChip(doctorCase: c)),
              vetChip(urgLabel, urgFg, urgFg, fontSize: 10),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            c.farmName.isEmpty ? c.farmerName : c.farmName,
            style: const TextStyle(
                color: VetColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700),
          ),
          Text('Farmer: ${c.farmerName}',
              style: const TextStyle(
                  color: VetColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.access_time,
                size: 14, color: VetColors.textSecondary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '$slot · ${c.mode == AppointmentMode.online ? 'Online' : 'In-person'}',
                style: const TextStyle(
                    color: VetColors.textSecondary, fontSize: 12),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          SelectableText('Case #${c.id}',
              style: const TextStyle(
                  color: VetColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _StageBanner extends StatelessWidget {
  const _StageBanner({required this.doctorCase});
  final DoctorCase doctorCase;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String text) = switch (doctorCase.stage) {
      CaseStage.awaitingAcceptance => (
          Icons.hourglass_top,
          'This consultation request has not been accepted yet. Accept it on '
              'the Schedule page to start case work.'
        ),
      CaseStage.open => (
          Icons.edit_note,
          'Record your findings below and save. Close the case when the '
              'diagnosis and treatment plan are final.'
        ),
      CaseStage.closed => (
          Icons.lock_outline,
          'Case closed. Mark the consultation as complete below, or reopen '
              'the case to edit.'
        ),
      CaseStage.completed => (
          Icons.verified_outlined,
          'Consultation completed. The farmer can see the clinical results. '
              'Issue the prescription and advice below.'
        ),
      CaseStage.prescribed => (
          Icons.verified_outlined,
          'Consultation completed and prescription issued.'
        ),
      CaseStage.ended => (
          Icons.block,
          'This consultation did not go ahead. The case is read-only.'
        ),
    };
    final (_, fg, bg) = caseStageStyle(doctorCase);
    return Container(
      key: const Key('caseStageBanner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: VetColors.textPrimary, fontSize: 13, height: 1.4)),
          ),
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
          _infoRow('Farm Name', c.farmName.isEmpty ? '—' : c.farmName),
          _infoRow('Flock Size', '${c.flockSize} birds'),
          _infoRow('Bird Age', '${c.birdAgeWeeks} weeks'),
          _infoRow('Breed', c.breed.isEmpty ? '—' : c.breed),
          _infoRow('Mortality Count', '${c.mortalityCount} birds',
              color: c.mortalityCount > 0 ? VetColors.red : null),
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
              child: Text(label,
                  style: const TextStyle(
                      color: VetColors.textSecondary, fontSize: 12)),
            ),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                    color: color ?? VetColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  )),
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
          if (symptoms.isEmpty)
            const Text('No symptoms reported by the farmer.',
                style: TextStyle(color: VetColors.textSecondary, fontSize: 13)),
          ...symptoms.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: VetColors.urgent, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(s,
                          style: const TextStyle(
                              color: VetColors.textPrimary, fontSize: 13)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

/// A clinical field card: a real text input while the case is open, the
/// saved text (or "Not recorded") once it isn't.
class _ClinicalField extends StatelessWidget {
  const _ClinicalField({
    required this.field,
    required this.controller,
    required this.editable,
    required this.enabled,
    required this.savedValue,
    this.inset = false,
    this.error,
  });
  final _Field field;
  final TextEditingController controller;
  final bool editable;
  final bool enabled;
  final bool inset;
  final String savedValue;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final f = field;
    final isWarning = f.key == 'warnings';
    final title = Row(
      children: [
        Icon(f.icon, size: inset ? 15 : 16, color: f.color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            f.label,
            style: TextStyle(
                color: f.color,
                fontSize: inset ? 12 : 13,
                fontWeight: FontWeight.w700),
          ),
        ),
        if (editable && f.requiredToClose) ...[
          const SizedBox(width: 6),
          const Text('Required to close',
              style: TextStyle(color: VetColors.textSecondary, fontSize: 11)),
        ],
      ],
    );
    final Widget content;
    if (editable) {
      content = TextField(
        key: Key('caseField_${f.key}'),
        controller: controller,
        enabled: enabled,
        minLines: f.multiline ? 3 : 1,
        maxLines: f.multiline ? 8 : 1,
        maxLength: f.multiline ? 5000 : 600,
        keyboardType: f.multiline ? TextInputType.multiline : TextInputType.text,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(color: VetColors.textPrimary, fontSize: 14, height: 1.4),
        decoration: InputDecoration(
          hintText: f.hint.isEmpty ? 'Add ${f.label.toLowerCase()}' : f.hint,
          hintStyle: const TextStyle(color: VetColors.textSecondary, fontSize: 13),
          errorText: error,
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.all(12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: VetColors.cardBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: VetColors.cardBorder)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: f.color, width: 1.5)),
        ),
      );
    } else if (f.key == 'disease_tags' && savedValue.isNotEmpty) {
      content = Wrap(
        key: Key('caseReadOnly_${f.key}'),
        spacing: 6,
        runSpacing: 4,
        children: savedValue.split(', ').map(_tag).toList(),
      );
    } else {
      content = Text(
        savedValue.trim().isEmpty ? 'Not recorded' : savedValue,
        key: Key('caseReadOnly_${f.key}'),
        style: TextStyle(
          color: savedValue.trim().isEmpty
              ? VetColors.textSecondary
              : VetColors.textPrimary,
          fontStyle: savedValue.trim().isEmpty ? FontStyle.italic : null,
          fontSize: 13,
          height: 1.5,
        ),
      );
    }
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [title, SizedBox(height: inset ? 8 : 10), content],
    );
    if (inset) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: f.color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: f.color.withValues(alpha: 0.25)),
        ),
        child: body,
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: vetCard(
          borderColor:
              isWarning ? VetColors.emergency.withValues(alpha: 0.4) : null),
      child: body,
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.children,
  });
  final IconData icon;
  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: vetCard(
            borderColor: VetColors.primary.withValues(alpha: 0.35)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionTitle(icon: icon, title: title),
            const SizedBox(height: 8),
            Text(body,
                style: const TextStyle(
                    color: VetColors.textPrimary, fontSize: 13, height: 1.4)),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );
}

class _PrescriptionCard extends StatelessWidget {
  final DoctorCase doctorCase;
  final bool busy;
  final VoidCallback onViewPdf;
  final VoidCallback onRetryEmail;
  const _PrescriptionCard({
    required this.doctorCase,
    required this.busy,
    required this.onViewPdf,
    required this.onRetryEmail,
  });

  /// (icon, colour, text) for the PDF email delivery state.
  static (IconData, Color, String) delivery(DoctorPrescription p) =>
      switch (p.emailStatus) {
        'sent' => (
            Icons.mark_email_read_outlined,
            VetColors.available,
            'PDF emailed to ${p.emailRecipient ?? 'the farmer'}'
          ),
        'failed' => (
            Icons.error_outline,
            VetColors.red,
            'Email not delivered${p.emailError == null ? '' : ': ${p.emailError}'}'
          ),
        _ => (
            Icons.schedule_send_outlined,
            VetColors.textSecondary,
            'Email delivery in progress'
          ),
      };

  @override
  Widget build(BuildContext context) {
    final p = doctorCase.prescription!;
    Widget labelled(String label, String? value) => value == null ||
            value.trim().isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: VetColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        color: VetColors.textPrimary, fontSize: 13, height: 1.4)),
              ],
            ),
          );
    return Container(
      key: const Key('casePrescriptionCard'),
      padding: const EdgeInsets.all(14),
      decoration:
          vetCard(borderColor: VetColors.available.withValues(alpha: 0.4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _SectionTitle(
                    icon: Icons.medication_outlined,
                    title: 'Prescription & Advice',
                    color: VetColors.available),
              ),
              if (doctorCase.prescriptionCount > 1)
                Text('Latest of ${doctorCase.prescriptionCount}',
                    style: const TextStyle(
                        color: VetColors.textSecondary, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (p.referenceNumber != null) p.referenceNumber!,
              'Issued ${DateFormat('d MMM yyyy, h:mm a').format(p.createdAt.toLocal())}',
            ].join(' · '),
            key: const Key('casePrescriptionReference'),
            style: const TextStyle(color: VetColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ...p.medicines.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: const BoxDecoration(
                          color: VetColors.available, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.name,
                              style: const TextStyle(
                                  color: VetColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          Text('${m.dosage} · ${m.duration}',
                              style: const TextStyle(
                                  color: VetColors.textSecondary, fontSize: 12)),
                          if (m.notes != null && m.notes!.isNotEmpty)
                            Text(m.notes!,
                                style: const TextStyle(
                                    color: VetColors.textSecondary,
                                    fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          labelled('Case advice', p.caseAdvice),
          labelled('Dosage notes', p.dosageNotes),
          labelled('Follow-up instructions', p.followUpInstructions),
          if (doctorCase.followUpDate != null)
            labelled(
                'Follow-up',
                DateFormat('EEE, d MMM yyyy · h:mm a')
                    .format(doctorCase.followUpDate!)),
          labelled('Referred to', p.referredTo),
          const Divider(height: 24, color: VetColors.divider),
          Builder(builder: (context) {
            final (icon, color, text) = delivery(p);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(text,
                      key: const Key('casePrescriptionEmailStatus'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            );
          }),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('casePrescriptionViewPdf'),
                onPressed: onViewPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('View PDF'),
                style: OutlinedButton.styleFrom(foregroundColor: VetColors.primary),
              ),
              // Only a failed delivery can be retried — re-sends the same
              // prescription's stored PDF, never creates a new prescription.
              if (p.emailFailed)
                OutlinedButton.icon(
                  key: const Key('casePrescriptionRetryEmail'),
                  onPressed: busy ? null : onRetryEmail,
                  icon: const Icon(Icons.forward_to_inbox_outlined, size: 18),
                  label: const Text('Retry email'),
                  style: OutlinedButton.styleFrom(foregroundColor: VetColors.red),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Prescription form ─────────────────────────────────────────────────────────

class _PrescriptionDraft {
  _PrescriptionDraft({
    required this.medicines,
    required this.caseAdvice,
    required this.dosageNotes,
    required this.followUpInstructions,
    required this.referredTo,
    required this.followUpAt,
  });
  final List<MedicineSuggestion> medicines;
  final String caseAdvice;
  final String dosageNotes;
  final String followUpInstructions;
  final String referredTo;
  final DateTime? followUpAt;
}

class _MedicineControllers {
  final name = TextEditingController();
  final dosage = TextEditingController();
  final duration = TextEditingController();
  final notes = TextEditingController();
  void dispose() {
    for (final c in [name, dosage, duration, notes]) {
      c.dispose();
    }
  }
}

class _PrescriptionForm extends StatefulWidget {
  const _PrescriptionForm({
    super.key,
    required this.busy,
    required this.onSubmit,
    required this.onCancel,
  });
  final bool busy;
  final Future<String?> Function(_PrescriptionDraft) onSubmit;
  final VoidCallback onCancel;

  @override
  State<_PrescriptionForm> createState() => _PrescriptionFormState();
}

class _PrescriptionFormState extends State<_PrescriptionForm> {
  final _medicines = [_MedicineControllers()];
  final _advice = TextEditingController();
  final _dosageNotes = TextEditingController();
  final _followUp = TextEditingController();
  final _referral = TextEditingController();
  DateTime? _followUpDate;
  TimeOfDay _followUpTime = const TimeOfDay(hour: 10, minute: 0);
  bool _submitting = false;
  String? _error;
  bool _showErrors = false;

  @override
  void dispose() {
    for (final m in _medicines) {
      m.dispose();
    }
    for (final c in [_advice, _dosageNotes, _followUp, _referral]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime? get _followUpAt => _followUpDate == null
      ? null
      : DateTime(_followUpDate!.year, _followUpDate!.month, _followUpDate!.day,
          _followUpTime.hour, _followUpTime.minute);

  String? _validate() {
    final complete = _medicines.where((m) =>
        m.name.text.trim().isNotEmpty &&
        m.dosage.text.trim().isNotEmpty &&
        m.duration.text.trim().isNotEmpty);
    if (complete.isEmpty) {
      return 'Add at least one medicine with name, dosage and duration.';
    }
    final partial = _medicines.any((m) =>
        [m.name, m.dosage, m.duration].any((c) => c.text.trim().isNotEmpty) &&
        [m.name, m.dosage, m.duration].any((c) => c.text.trim().isEmpty));
    if (partial) return 'Each medicine needs a name, dosage and duration.';
    if (_advice.text.trim().isEmpty) return 'Case advice is required.';
    if (_followUpAt != null && !_followUpAt!.isAfter(DateTime.now())) {
      return 'The follow-up time must be in the future.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting || widget.busy) return;
    final invalid = _validate();
    if (invalid != null) {
      setState(() {
        _error = invalid;
        _showErrors = true;
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await widget.onSubmit(_PrescriptionDraft(
      medicines: [
        for (final m in _medicines)
          if (m.name.text.trim().isNotEmpty)
            MedicineSuggestion(
              name: m.name.text.trim(),
              dosage: m.dosage.text.trim(),
              duration: m.duration.text.trim(),
              notes: m.notes.text.trim(),
            ),
      ],
      caseAdvice: _advice.text.trim(),
      dosageNotes: _dosageNotes.text.trim(),
      followUpInstructions: _followUp.text.trim(),
      referredTo: _referral.text.trim(),
      followUpAt: _followUpAt,
    ));
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  InputDecoration _decoration(String label, {String? error}) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: VetColors.textSecondary),
        errorText: error,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      );

  Widget _medicineRow(int i, bool wide) {
    final m = _medicines[i];
    String? need(TextEditingController c) =>
        _showErrors && c.text.trim().isEmpty && i == 0 ? 'Required' : null;
    final name = TextField(
        key: Key('rxMedicineName_$i'),
        controller: m.name,
        decoration: _decoration('Medicine *', error: need(m.name)));
    final dosage = TextField(
        key: Key('rxMedicineDosage_$i'),
        controller: m.dosage,
        decoration: _decoration('Dosage *', error: need(m.dosage)));
    final duration = TextField(
        key: Key('rxMedicineDuration_$i'),
        controller: m.duration,
        decoration: _decoration('Duration *', error: need(m.duration)));
    final notes = TextField(
        controller: m.notes, decoration: _decoration('Instructions'));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: VetColors.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text('Medicine ${i + 1}',
                style: const TextStyle(
                    color: VetColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            if (_medicines.length > 1)
              IconButton(
                tooltip: 'Remove medicine',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _medicines.removeAt(i).dispose()),
                icon: const Icon(Icons.close, size: 18, color: VetColors.red),
              ),
          ]),
          const SizedBox(height: 6),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 2, child: name),
              const SizedBox(width: 8),
              Expanded(child: dosage),
              const SizedBox(width: 8),
              Expanded(child: duration),
            ])
          else ...[
            name,
            const SizedBox(height: 8),
            dosage,
            const SizedBox(height: 8),
            duration,
          ],
          const SizedBox(height: 8),
          notes,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _submitting || widget.busy;
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 520;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _medicines.length; i++) _medicineRow(i, wide),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy
                  ? null
                  : () => setState(() => _medicines.add(_MedicineControllers())),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add medicine'),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const Key('rxCaseAdvice'),
            controller: _advice,
            minLines: 3,
            maxLines: 6,
            decoration: _decoration('Case advice *',
                error: _showErrors && _advice.text.trim().isEmpty
                    ? 'Required'
                    : null),
          ),
          const SizedBox(height: 10),
          TextField(
              controller: _dosageNotes,
              maxLines: 3,
              minLines: 1,
              decoration: _decoration('Dosage notes')),
          const SizedBox(height: 10),
          TextField(
              controller: _followUp,
              maxLines: 3,
              minLines: 1,
              decoration: _decoration('Follow-up instructions')),
          const SizedBox(height: 10),
          TextField(
              controller: _referral,
              decoration: _decoration('Referred to (optional)')),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _followUpDate ??
                              DateTime.now().add(const Duration(days: 7)),
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setState(() => _followUpDate = picked);
                        }
                      },
                icon: const Icon(Icons.event, size: 16),
                label: Text(_followUpDate == null
                    ? 'Optional follow-up date'
                    : DateFormat('d MMM yyyy').format(_followUpDate!)),
              ),
              if (_followUpDate != null) ...[
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final picked = await showTimePicker(
                              context: context, initialTime: _followUpTime);
                          if (picked != null) {
                            setState(() => _followUpTime = picked);
                          }
                        },
                  icon: const Icon(Icons.schedule, size: 16),
                  label: Text(_followUpTime.format(context)),
                ),
                TextButton(
                  onPressed:
                      busy ? null : () => setState(() => _followUpDate = null),
                  child: const Text('Remove follow-up'),
                ),
              ],
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                key: const Key('rxError'),
                style: const TextStyle(color: VetColors.red, fontSize: 13)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton(
                onPressed: busy ? null : widget.onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  key: const Key('casePrescriptionSubmit'),
                  onPressed: busy ? null : _submit,
                  icon: busy
                      ? const _ButtonSpinner()
                      : const Icon(Icons.send_outlined, size: 18),
                  label: Text(busy ? 'Saving…' : 'Save and email PDF'),
                  style: _primaryButton,
                ),
              ),
            ],
          ),
        ],
      );
    });
  }
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
        Flexible(
          child: Text(
            title,
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
