import 'package:flutter/material.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/audit_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/permission_guard.dart';

class AdminDoctorsScreen extends StatefulWidget {
  const AdminDoctorsScreen({super.key});

  @override
  State<AdminDoctorsScreen> createState() => _AdminDoctorsScreenState();
}

class _AdminDoctorsScreenState extends State<AdminDoctorsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _search = TextEditingController();
  late List<_DoctorData> _doctors;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _doctors = List.of(_kDoctors);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  void _approve(String id) {
    final doc = _doctors.firstWhere((d) => d.id == id);
    setState(() {
      final i = _doctors.indexOf(doc);
      _doctors[i] = doc.copyWith(status: 'Verified');
    });
    AuditService.instance.log('Doctor Management', 'Approve', doc.name);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Doctor approved successfully'),
      backgroundColor: AColors.green,
      duration: Duration(seconds: 2),
    ));
  }

  void _suspend(String id) {
    final doc = _doctors.firstWhere((d) => d.id == id);
    setState(() {
      final i = _doctors.indexOf(doc);
      _doctors[i] = doc.copyWith(status: 'Suspended');
    });
    AuditService.instance.log('Doctor Management', 'Suspend', doc.name);
  }

  List<_DoctorData> _filtered(String tab) {
    final q = _search.text.toLowerCase();
    return _doctors.where((d) {
      final matchTab = tab == 'All' ||
          (tab == 'Pending' && d.status == 'Pending') ||
          (tab == 'Verified' && d.status == 'Verified');
      final matchSearch = q.isEmpty ||
          d.name.toLowerCase().contains(q) ||
          d.specialty.toLowerCase().contains(q);
      return matchTab && matchSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Doctors & Patients',
      module: AdminModule.doctorPatient,
      child: Column(
        children: [
          Container(
            color: AColors.appBar,
            child: TabBar(
              controller: _tabs,
              indicatorColor: AColors.secondary,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'All Doctors'),
                Tab(text: 'Pending Approval'),
                Tab(text: 'Consultations'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style:
                  const TextStyle(fontSize: 14, color: AColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search doctors…',
                hintStyle:
                    const TextStyle(color: AColors.grey, fontSize: 14),
                prefixIcon:
                    const Icon(Icons.search, color: AColors.grey, size: 20),
                filled: true,
                fillColor: AColors.surface2,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AColors.cardBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AColors.cardBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: AColors.secondary, width: 1.5)),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _DoctorList(
                    doctors: _filtered('All'),
                    onApprove: _approve,
                    onSuspend: _suspend),
                _DoctorList(
                    doctors: _filtered('Pending'),
                    onApprove: _approve,
                    onSuspend: _suspend),
                _ConsultationList(doctors: _filtered('Verified')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Doctor list ───────────────────────────────────────────────────────────────

class _DoctorList extends StatelessWidget {
  final List<_DoctorData> doctors;
  final void Function(String) onApprove;
  final void Function(String) onSuspend;

  const _DoctorList(
      {required this.doctors,
      required this.onApprove,
      required this.onSuspend});

  @override
  Widget build(BuildContext context) {
    if (doctors.isEmpty) {
      return const Center(
          child: Text('No doctors found.',
              style:
                  TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: doctors.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _DoctorCard(
          doctor: doctors[i],
          onApprove: onApprove,
          onSuspend: onSuspend),
    );
  }
}

class _DoctorCard extends StatelessWidget {
  final _DoctorData doctor;
  final void Function(String) onApprove;
  final void Function(String) onSuspend;

  const _DoctorCard(
      {required this.doctor,
      required this.onApprove,
      required this.onSuspend});

  @override
  Widget build(BuildContext context) {
    final statusColor = doctor.status == 'Verified'
        ? AColors.green
        : doctor.status == 'Pending'
            ? AColors.amber
            : AColors.red;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(highlight: doctor.status == 'Pending'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AColors.primary.withValues(alpha: 0.1),
                child: Text(doctor.name.split(' ').last[0],
                    style: const TextStyle(
                        color: AColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doctor.name,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AColors.textPrimary)),
                    Text(doctor.specialty,
                        style: const TextStyle(
                            fontSize: 12, color: AColors.textSecondary)),
                  ],
                ),
              ),
              aChip(doctor.status, statusColor, statusColor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatPill(Icons.star_outline,
                  doctor.rating > 0 ? '${doctor.rating}' : 'Unrated',
                  AColors.amber),
              const SizedBox(width: 10),
              _StatPill(Icons.chat_bubble_outline,
                  '${doctor.consultations} consults', AColors.blue),
              const SizedBox(width: 10),
              _StatPill(Icons.access_time, doctor.responseTime, AColors.grey),
            ],
          ),
          if (doctor.status == 'Pending') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AColors.amberLight,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.upload_file_outlined,
                      size: 14, color: AColors.amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Document: ${doctor.licenseDoc} — awaiting review',
                      style: const TextStyle(
                          fontSize: 11, color: AColors.orange),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              PermissionGuard(
                module: AdminModule.doctorPatient,
                permission: AdminPermission.approve,
                child: doctor.status == 'Pending'
                    ? _ActionChip('Approve', AColors.green,
                        () => onApprove(doctor.id))
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
              PermissionGuard(
                module: AdminModule.doctorPatient,
                permission: AdminPermission.edit,
                child: _ActionChip('View Profile', AColors.blue, () {}),
              ),
              const SizedBox(width: 8),
              if (doctor.status == 'Verified')
                PermissionGuard(
                  module: AdminModule.doctorPatient,
                  permission: AdminPermission.suspend,
                  child: _ActionChip(
                      'Suspend', AColors.red, () => onSuspend(doctor.id)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Consultations tab ─────────────────────────────────────────────────────────

class _ConsultationList extends StatelessWidget {
  final List<_DoctorData> doctors;

  const _ConsultationList({required this.doctors});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _kConsultations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _ConsultationCard(_kConsultations[i]),
    );
  }
}

class _ConsultationCard extends StatelessWidget {
  final _ConsultData c;
  const _ConsultationCard(this.c);

  @override
  Widget build(BuildContext context) {
    final urgentColor = c.urgent ? AColors.red : AColors.secondary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(highlight: c.urgent),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: urgentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.medical_services_outlined,
                color: urgentColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(c.patient,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AColors.textPrimary)),
                    ),
                    if (c.urgent) ...[
                      const SizedBox(width: 6),
                      aChip('URGENT', AColors.red, AColors.red,
                          fontSize: 9),
                    ],
                  ],
                ),
                Text('Dr. ${c.doctor} · ${c.topic}',
                    style: const TextStyle(
                        fontSize: 11, color: AColors.textSecondary)),
                Text(c.time,
                    style: const TextStyle(
                        fontSize: 10, color: AColors.grey)),
              ],
            ),
          ),
          PermissionGuard(
            module: AdminModule.doctorPatient,
            permission: AdminPermission.edit,
            child: _ActionChip('Escalate', AColors.orange, () {}),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatPill(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip(this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ── Mock data ─────────────────────────────────────────────────────────────────

class _DoctorData {
  final String id, name, specialty, status, responseTime, licenseDoc;
  final double rating;
  final int consultations;

  const _DoctorData({
    required this.id,
    required this.name,
    required this.specialty,
    required this.status,
    required this.rating,
    required this.consultations,
    required this.responseTime,
    required this.licenseDoc,
  });

  _DoctorData copyWith({String? status}) => _DoctorData(
        id: id,
        name: name,
        specialty: specialty,
        status: status ?? this.status,
        rating: rating,
        consultations: consultations,
        responseTime: responseTime,
        licenseDoc: licenseDoc,
      );
}

const _kDoctors = [
  _DoctorData(
      id: 'D001',
      name: 'Dr. Kamrul Islam',
      specialty: 'Avian Disease Specialist',
      status: 'Verified',
      rating: 4.8,
      consultations: 312,
      responseTime: '~15 min',
      licenseDoc: 'BVSc License'),
  _DoctorData(
      id: 'D002',
      name: 'Dr. Rina Begum',
      specialty: 'Poultry Nutrition Expert',
      status: 'Pending',
      rating: 0.0,
      consultations: 0,
      responseTime: 'N/A',
      licenseDoc: 'DVM Certificate'),
  _DoctorData(
      id: 'D003',
      name: 'Dr. Shahid Hossain',
      specialty: 'Broiler Pathology',
      status: 'Verified',
      rating: 4.5,
      consultations: 187,
      responseTime: '~30 min',
      licenseDoc: 'MVSc License'),
  _DoctorData(
      id: 'D004',
      name: 'Dr. Fatema Akhter',
      specialty: 'Layer Hen Management',
      status: 'Pending',
      rating: 0.0,
      consultations: 0,
      responseTime: 'N/A',
      licenseDoc: 'BVSc License'),
];

class _ConsultData {
  final String patient, doctor, topic, time;
  final bool urgent;

  const _ConsultData(
      this.patient, this.doctor, this.topic, this.time, this.urgent);
}

const _kConsultations = [
  _ConsultData('Karim Hossain Farm', 'Kamrul Islam',
      'Newcastle Disease outbreak', 'Today 09:30', true),
  _ConsultData('Comilla Poultry Co.', 'Shahid Hossain',
      'Feed conversion ratio', 'Today 10:15', false),
  _ConsultData('Rahim Broiler Farm', 'Kamrul Islam',
      'Coccidiosis treatment', 'Today 11:00', true),
  _ConsultData('Green Valley Farm', 'Shahid Hossain',
      'Layer productivity drop', 'Yesterday 16:45', false),
];
