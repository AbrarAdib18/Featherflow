import 'package:flutter/material.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/audit_service.dart';
import '../../data/services/admin_api_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/module_activity.dart';
import '../widgets/permission_guard.dart';
import '../widgets/admin_dialogs.dart';

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
  List<_ConsultData> _consultations = [];
  List<_DisputeData> _disputes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _doctors = [];
    _loadData();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        AdminApiService.instance.list('doctors'),
        AdminApiService.instance.list('consultations'),
        AdminApiService.instance.list('consultation-disputes'),
      ]);
      if (!mounted) return;
      setState(() {
        _doctors = results[0].map(_DoctorData.fromJson).toList();
        _consultations = results[1].map(_ConsultData.fromJson).toList();
        _disputes = results[2].map(_DisputeData.fromJson).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _approve(String id) async {
    final doc = _doctors.firstWhere((d) => d.id == id);
    final response = await AdminApiService.instance
        .update('doctors', id, {'status': 'Verified'});
    final updated = _DoctorData.fromJson(response);
    if (!mounted) return;
    setState(() {
      final i = _doctors.indexOf(doc);
      _doctors[i] = updated;
    });
    AuditService.instance.log('Doctor Management', 'Approve', doc.name);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Doctor approved successfully'),
      backgroundColor: AColors.green,
      duration: Duration(seconds: 2),
    ));
  }

  Future<void> _suspend(String id) async {
    final doc = _doctors.firstWhere((d) => d.id == id);
    final response = await AdminApiService.instance
        .update('doctors', id, {'status': 'Suspended'});
    final updated = _DoctorData.fromJson(response);
    if (!mounted) return;
    setState(() {
      final i = _doctors.indexOf(doc);
      _doctors[i] = updated;
    });
    AuditService.instance.log('Doctor Management', 'Suspend', doc.name);
  }

  Future<void> _deny(String id) async {
    final doc = _doctors.firstWhere((d) => d.id == id);
    final response = await AdminApiService.instance
        .update('doctors', id, {'status': 'Rejected'});
    final updated = _DoctorData.fromJson(response);
    if (!mounted) return;
    setState(() {
      final i = _doctors.indexOf(doc);
      _doctors[i] = updated;
    });
    AuditService.instance.log('Doctor Management', 'Reject', doc.name);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Doctor registration rejected'),
        backgroundColor: AColors.red));
  }

  void _showProfile(_DoctorData doctor) => showAdminDetails(context,
          title: doctor.name,
          icon: Icons.medical_services_outlined,
          fields: [
            MapEntry('Doctor ID', doctor.id),
            MapEntry('Specialty', doctor.specialty),
            MapEntry('Verification status', doctor.status),
            MapEntry('License document', doctor.licenseDoc),
            MapEntry('Clinic / hospital', doctor.clinicName),
            MapEntry('Practice address', doctor.practiceAddress),
            MapEntry('District', doctor.district),
            MapEntry('Degree', doctor.degree),
            MapEntry('University', doctor.university),
            MapEntry('Graduation year', doctor.graduationYear),
            MapEntry('License authority', doctor.licenseAuthority),
            MapEntry('License expiry', doctor.licenseExpiry),
            MapEntry('Poultry focus', doctor.focusArea),
            MapEntry('Experience', '${doctor.yearsExperience} years'),
            MapEntry('Consultation mode', doctor.consultationMode),
            MapEntry('Service fee', '৳${doctor.serviceFee.toStringAsFixed(0)}'),
            MapEntry('Rating',
                doctor.rating > 0 ? '${doctor.rating} / 5' : 'Unrated'),
            MapEntry('Consultations', '${doctor.consultations}'),
            MapEntry('Typical response time', doctor.responseTime),
          ]);

  Future<void> _editDoctor(_DoctorData doctor) async {
    final values = await showAdminRecordEditor(context,
        title: 'Edit Doctor Profile',
        fields: {
          'Specialty': doctor.specialty,
          'Clinic': doctor.clinicName,
          'Practice address': doctor.practiceAddress,
          'District': doctor.district,
          'Degree': doctor.degree,
          'University': doctor.university,
          'License number': doctor.licenseDoc,
          'Focus area': doctor.focusArea,
          'Years experience': '${doctor.yearsExperience}',
          'Service fee': '${doctor.serviceFee}',
        });
    if (values == null) return;
    final response =
        await AdminApiService.instance.update('doctors', doctor.id, {
      'specialty': values['Specialty'],
      'clinic_name': values['Clinic'],
      'practice_address': values['Practice address'],
      'district': values['District'],
      'degree': values['Degree'],
      'university': values['University'],
      'license_doc': values['License number'],
      'focus_area': values['Focus area'],
      'years_experience': int.tryParse(values['Years experience'] ?? '') ??
          doctor.yearsExperience,
      'service_fee':
          double.tryParse(values['Service fee'] ?? '') ?? doctor.serviceFee,
    });
    if (!mounted) return;
    setState(() =>
        _doctors[_doctors.indexOf(doctor)] = _DoctorData.fromJson(response));
  }

  void _escalateConsultation(_ConsultData consultation) {
    AuditService.instance.log(
        'Doctor Management', 'Escalate Consultation', consultation.patient,
        details: consultation.topic);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Consultation escalated to the clinical response team'),
        backgroundColor: AColors.orange));
  }

  Future<void> _resolveDispute(_DisputeData dispute, String action) async {
    String resolution = '';
    if (action != 'review') {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(action == 'resolve' ? 'Resolve dispute' : 'Dismiss dispute'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Resolution note (shown to both parties) *'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
          ],
        ),
      );
      if (ok != true || controller.text.trim().isEmpty) return;
      resolution = controller.text.trim();
    }
    try {
      final res = await AdminApiService.instance.update(
          'consultation-disputes', dispute.id,
          {'action': action, if (resolution.isNotEmpty) 'resolution': resolution});
      if (!mounted) return;
      setState(() {
        final i = _disputes.indexWhere((d) => d.id == dispute.id);
        if (i >= 0) _disputes[i] = _DisputeData.fromJson(res);
      });
      AuditService.instance
          .log('Doctor Management', 'Dispute $action', dispute.doctor);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AColors.red));
    }
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
      appBarActions: const [
        ModuleActivityButton(
            title: 'Doctors',
            modules: ['doctors', 'consultations', 'consultation-disputes']),
      ],
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
              tabs: [
                const Tab(text: 'All Doctors'),
                const Tab(text: 'Pending Approval'),
                const Tab(text: 'Consultations'),
                Tab(text: 'Disputes'
                    '${_disputes.where((d) => d.status == 'open' || d.status == 'under_review').isNotEmpty ? ' (${_disputes.where((d) => d.status == 'open' || d.status == 'under_review').length})' : ''}'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 14, color: AColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search doctors…',
                hintStyle: const TextStyle(color: AColors.grey, fontSize: 14),
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
                    borderSide:
                        const BorderSide(color: AColors.secondary, width: 1.5)),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AColors.secondary))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _DoctorList(
                          doctors: _filtered('All'),
                          onApprove: _approve,
                          onDeny: _deny,
                          onSuspend: _suspend,
                          onEdit: _editDoctor,
                          onView: _showProfile),
                      _DoctorList(
                          doctors: _filtered('Pending'),
                          onApprove: _approve,
                          onDeny: _deny,
                          onSuspend: _suspend,
                          onEdit: _editDoctor,
                          onView: _showProfile),
                      _ConsultationList(
                          doctors: _filtered('Verified'),
                          consultations: _consultations,
                          onEscalate: _escalateConsultation),
                      _DisputeList(disputes: _disputes, onResolve: _resolveDispute),
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
  final void Function(String) onDeny;
  final void Function(String) onSuspend;
  final void Function(_DoctorData) onEdit;
  final void Function(_DoctorData) onView;

  const _DoctorList(
      {required this.doctors,
      required this.onApprove,
      required this.onDeny,
      required this.onSuspend,
      required this.onEdit,
      required this.onView});

  @override
  Widget build(BuildContext context) {
    if (doctors.isEmpty) {
      return const Center(
          child: Text('No doctors found.',
              style: TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: doctors.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _DoctorCard(
          doctor: doctors[i],
          onApprove: onApprove,
          onDeny: onDeny,
          onSuspend: onSuspend,
          onEdit: onEdit,
          onView: onView),
    );
  }
}

class _DoctorCard extends StatelessWidget {
  final _DoctorData doctor;
  final void Function(String) onApprove;
  final void Function(String) onDeny;
  final void Function(String) onSuspend;
  final void Function(_DoctorData) onEdit;
  final void Function(_DoctorData) onView;

  const _DoctorCard(
      {required this.doctor,
      required this.onApprove,
      required this.onDeny,
      required this.onSuspend,
      required this.onEdit,
      required this.onView});

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
              if (doctor.openDisputes > 0) ...[
                const SizedBox(width: 6),
                aChip('${doctor.openDisputes} dispute${doctor.openDisputes == 1 ? '' : 's'}',
                    AColors.red, AColors.red, fontSize: 9),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _StatPill(
                  Icons.star_outline,
                  doctor.rating > 0 ? '${doctor.rating}' : 'Unrated',
                  AColors.amber),
              _StatPill(Icons.chat_bubble_outline,
                  '${doctor.consultations} consults', AColors.blue),
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
                      style:
                          const TextStyle(fontSize: 11, color: AColors.orange),
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
                    ? _ActionChip(
                        'Approve', AColors.green, () => onApprove(doctor.id))
                    : const SizedBox.shrink(),
              ),
              if (doctor.status == 'Pending') ...[
                const SizedBox(width: 8),
                PermissionGuard(
                  module: AdminModule.doctorPatient,
                  permission: AdminPermission.suspend,
                  child:
                      _ActionChip('Deny', AColors.red, () => onDeny(doctor.id)),
                ),
              ],
              const SizedBox(width: 8),
              PermissionGuard(
                module: AdminModule.doctorPatient,
                permission: AdminPermission.edit,
                child: _ActionChip(
                    'View Profile', AColors.blue, () => onView(doctor)),
              ),
              const SizedBox(width: 8),
              PermissionGuard(
                module: AdminModule.doctorPatient,
                permission: AdminPermission.edit,
                child: _ActionChip('Edit', AColors.grey, () => onEdit(doctor)),
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
  final List<_ConsultData> consultations;
  final void Function(_ConsultData) onEscalate;

  const _ConsultationList(
      {required this.doctors,
      required this.consultations,
      required this.onEscalate});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: consultations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) =>
          _ConsultationCard(consultations[i], onEscalate: onEscalate),
    );
  }
}

class _ConsultationCard extends StatelessWidget {
  final _ConsultData c;
  final void Function(_ConsultData) onEscalate;
  const _ConsultationCard(this.c, {required this.onEscalate});

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
                      aChip('URGENT', AColors.red, AColors.red, fontSize: 9),
                    ],
                  ],
                ),
                Text('Dr. ${c.doctor} · ${c.topic}',
                    style: const TextStyle(
                        fontSize: 11, color: AColors.textSecondary)),
                Text(c.time,
                    style: const TextStyle(fontSize: 10, color: AColors.grey)),
              ],
            ),
          ),
          PermissionGuard(
            module: AdminModule.doctorPatient,
            permission: AdminPermission.edit,
            child: _ActionChip('Escalate', AColors.orange, () => onEscalate(c)),
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
                fontSize: 11, color: color, fontWeight: FontWeight.w500)),
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

// ── Disputes tab ──────────────────────────────────────────────────────────────

class _DisputeList extends StatelessWidget {
  final List<_DisputeData> disputes;
  final Future<void> Function(_DisputeData, String) onResolve;

  const _DisputeList({required this.disputes, required this.onResolve});

  @override
  Widget build(BuildContext context) {
    final open = disputes
        .where((d) => d.status == 'open' || d.status == 'under_review')
        .toList();
    final closed = disputes
        .where((d) => d.status == 'resolved' || d.status == 'dismissed')
        .toList();
    if (disputes.isEmpty) {
      return const Center(
          child: Text('No consultation disputes.',
              style: TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      for (final d in [...open, ...closed])
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: aCard(
                highlight: d.status == 'open' || d.status == 'under_review'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                aChip(d.category.replaceAll('_', ' '), AColors.purple, AColors.purple),
                const SizedBox(width: 6),
                aChip('by ${d.raisedByRole}', AColors.grey, AColors.grey, fontSize: 10),
                const Spacer(),
                aChip(d.status.replaceAll('_', ' '),
                    d.status == 'resolved'
                        ? AColors.green
                        : d.status == 'dismissed'
                            ? AColors.grey
                            : AColors.orange,
                    d.status == 'resolved'
                        ? AColors.green
                        : d.status == 'dismissed'
                            ? AColors.grey
                            : AColors.orange,
                    fontSize: 10),
              ]),
              const SizedBox(height: 8),
              Text('${d.farmer}  ·  Dr. ${d.doctor}',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
              Text('Consultation ${d.consultationStatus} · ${d.appointment}',
                  style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
              const SizedBox(height: 4),
              Text(d.description,
                  style: const TextStyle(fontSize: 12, color: AColors.grey, height: 1.4)),
              if (d.resolution != null && d.resolution!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Resolution: ${d.resolution}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AColors.green, fontStyle: FontStyle.italic)),
              ],
              if (d.status == 'open' || d.status == 'under_review') ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  if (d.status == 'open')
                    _ActionChip('Mark reviewing', AColors.blue, () => onResolve(d, 'review')),
                  _ActionChip('Resolve', AColors.green, () => onResolve(d, 'resolve')),
                  _ActionChip('Dismiss', AColors.grey, () => onResolve(d, 'dismiss')),
                ]),
              ],
            ]),
          ),
        ),
    ]);
  }
}

class _DisputeData {
  final String id, category, raisedByRole, farmer, doctor, consultationStatus;
  final String appointment, description, status;
  final String? resolution;

  const _DisputeData({
    required this.id,
    required this.category,
    required this.raisedByRole,
    required this.farmer,
    required this.doctor,
    required this.consultationStatus,
    required this.appointment,
    required this.description,
    required this.status,
    this.resolution,
  });

  factory _DisputeData.fromJson(Map<String, dynamic> j) => _DisputeData(
        id: j['id'].toString(),
        category: j['category']?.toString() ?? 'other',
        raisedByRole: j['raised_by_role']?.toString() ?? 'farmer',
        farmer: j['farmer']?.toString() ?? '',
        doctor: j['doctor']?.toString() ?? '',
        consultationStatus: j['consultation_status']?.toString() ?? '',
        appointment: j['appointment']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        status: j['status']?.toString() ?? 'open',
        resolution: j['resolution']?.toString(),
      );
}

// ── Mock data ─────────────────────────────────────────────────────────────────

class _DoctorData {
  final String id, name, specialty, status, responseTime, licenseDoc;
  final String clinicName, practiceAddress, district, degree, university;
  final String graduationYear, licenseAuthority, licenseExpiry, focusArea;
  final String consultationMode;
  final double rating;
  final double serviceFee;
  final int consultations, yearsExperience, openDisputes;

  const _DoctorData({
    required this.id,
    required this.name,
    required this.specialty,
    required this.status,
    required this.rating,
    required this.consultations,
    required this.responseTime,
    required this.licenseDoc,
    this.clinicName = '',
    this.practiceAddress = '',
    this.district = '',
    this.degree = '',
    this.university = '',
    this.graduationYear = '',
    this.licenseAuthority = '',
    this.licenseExpiry = '',
    this.focusArea = '',
    this.consultationMode = '',
    this.serviceFee = 0,
    this.yearsExperience = 0,
    this.openDisputes = 0,
  });

  factory _DoctorData.fromJson(Map<String, dynamic> json) => _DoctorData(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        specialty: json['specialty']?.toString() ?? '',
        status: json['status']?.toString() ?? 'Pending',
        rating: (json['rating'] as num?)?.toDouble() ?? 0,
        consultations: (json['consultations'] as num?)?.toInt() ?? 0,
        responseTime: json['response_time']?.toString() ?? 'N/A',
        licenseDoc: json['license_doc']?.toString() ?? '',
        clinicName: json['clinic_name']?.toString() ?? '',
        practiceAddress: json['practice_address']?.toString() ?? '',
        district: json['district']?.toString() ?? '',
        degree: json['degree']?.toString() ?? '',
        university: json['university']?.toString() ?? '',
        graduationYear: json['graduation_year']?.toString() ?? '',
        licenseAuthority: json['license_authority']?.toString() ?? '',
        licenseExpiry: json['license_expiry']?.toString() ?? '',
        focusArea: json['focus_area']?.toString() ?? '',
        yearsExperience: (json['years_experience'] as num?)?.toInt() ?? 0,
        consultationMode: json['consultation_mode']?.toString() ?? '',
        serviceFee: (json['service_fee'] as num?)?.toDouble() ?? 0,
        openDisputes: (json['open_disputes'] as num?)?.toInt() ?? 0,
      );

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


class _ConsultData {
  final String patient, doctor, topic, time;
  final bool urgent;

  const _ConsultData(
      this.patient, this.doctor, this.topic, this.time, this.urgent);

  factory _ConsultData.fromJson(Map<String, dynamic> json) => _ConsultData(
        json['patient']?.toString() ?? '',
        json['doctor']?.toString() ?? '',
        json['topic']?.toString() ?? '',
        json['time']?.toString() ?? '',
        json['urgent'] == true,
      );
}

