import 'package:flutter/material.dart';
import '../../data/models/doctor_models.dart';
import '../../data/services/doctor_session.dart';
import '../doctor_theme.dart';
import 'doctor_case_notes_screen.dart';

class DoctorPrescriptionsScreen extends StatelessWidget {
  const DoctorPrescriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DoctorSession.instance,
      builder: (context, _) {
        final prescriptions = DoctorSession.instance.cases
            .where((c) => c.prescription != null)
            .map((c) => (c, c.prescription!))
            .toList();

        prescriptions.sort(
            (a, b) => b.$2.createdAt.compareTo(a.$2.createdAt));

        return Scaffold(
          backgroundColor: VetColors.bg,
          appBar: AppBar(
            backgroundColor: VetColors.appBar,
            foregroundColor: Colors.white,
            title: const Text(
              'Prescriptions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          body: prescriptions.isEmpty
              ? const _EmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: prescriptions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _PrescriptionCard(
                    doctorCase: prescriptions[i].$1,
                    prescription: prescriptions[i].$2,
                  ),
                ),
        );
      },
    );
  }
}

// ── Prescription Card ─────────────────────────────────────────────────────────

class _PrescriptionCard extends StatelessWidget {
  final DoctorCase doctorCase;
  final DoctorPrescription prescription;
  const _PrescriptionCard({required this.doctorCase, required this.prescription});

  String _formatDate(DateTime d) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final p = prescription;
    final c = doctorCase;
    return Container(
      decoration: vetCard(highlight: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: VetColors.secondary.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.medication_outlined, color: VetColors.secondary, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.farmName,
                        style: const TextStyle(
                          color: VetColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Case #${c.id} · ${c.farmerName}',
                        style: const TextStyle(color: VetColors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Text(
                  _formatDate(p.createdAt),
                  style: const TextStyle(color: VetColors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          // Medicines
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...p.medicines.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _MedicineRow(
                        index: e.key + 1,
                        medicine: e.value,
                      ),
                    )),
                if (p.dosageNotes != null) ...[
                  const Divider(height: 1, color: VetColors.divider),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 14, color: VetColors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          p.dosageNotes!,
                          style: const TextStyle(
                            color: VetColors.textSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (p.followUpInstructions != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: VetColors.followUpLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.event_repeat, size: 14, color: VetColors.followUpColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            p.followUpInstructions!,
                            style: const TextStyle(
                              color: VetColors.followUpColor,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (p.referredTo != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: VetColors.openLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: VetColors.open.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_search_outlined, size: 14, color: VetColors.open),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Referred to: ${p.referredTo}',
                            style: const TextStyle(
                              color: VetColors.open,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1, color: VetColors.divider),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CaseDetailScreen(caseId: c.id),
                          ),
                        ),
                        icon: const Icon(Icons.folder_open_outlined, size: 14),
                        label: const Text('View Case'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: VetColors.primary,
                          side: const BorderSide(color: VetColors.cardBorder),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _sharePrescription(context),
                        icon: const Icon(Icons.share_outlined, size: 14),
                        label: const Text('Share Rx'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: VetColors.secondary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _sharePrescription(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PDF export — connect to your backend to enable.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _MedicineRow extends StatelessWidget {
  final int index;
  final MedicineSuggestion medicine;
  const _MedicineRow({required this.index, required this.medicine});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: VetColors.secondary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$index',
              style: const TextStyle(
                color: VetColors.secondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                medicine.name,
                style: const TextStyle(
                  color: VetColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  _pill('Dose: ${medicine.dosage}', VetColors.openLight, VetColors.open),
                  const SizedBox(width: 6),
                  _pill(medicine.duration, VetColors.closedLight, VetColors.closed),
                ],
              ),
              if (medicine.notes != null) ...[
                const SizedBox(height: 4),
                Text(
                  medicine.notes!,
                  style: const TextStyle(
                    color: VetColors.grey,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _pill(String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w500)),
      );
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.medication_outlined,
            size: 52,
            color: VetColors.grey.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          const Text(
            'No prescriptions yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: VetColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Prescriptions will appear here once added to a case.',
            style: TextStyle(fontSize: 13, color: VetColors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
