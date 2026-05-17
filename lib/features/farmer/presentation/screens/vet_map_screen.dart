import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:featherflow/core/theme/theme.dart';

class VetMapScreen extends StatefulWidget {
  const VetMapScreen({super.key});

  @override
  State<VetMapScreen> createState() => _VetMapScreenState();
}

class _VetMapScreenState extends State<VetMapScreen> {
  int _selectedFilter = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Featherflow Vet Map',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white),
            onPressed: () => context.go('/farmer'),
            tooltip: 'Home',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _HeroSection(),
            const SizedBox(height: AppSpacing.md),
            _MapPlaceholder(
              selectedFilter: _selectedFilter,
              onFilterChanged: (i) => setState(() => _selectedFilter = i),
            ),
            const SizedBox(height: AppSpacing.md),
            const _ClosestVetCard(),
            const SizedBox(height: AppSpacing.md),
            const _ConsultationOptionsRow(),
            const SizedBox(height: AppSpacing.md),
            const _RegisteredDoctorsList(),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Get vet help nearby',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Find registered vets and clinics fast',
          style: TextStyle(fontSize: 14, color: AppColors.hint),
        ),
        const SizedBox(height: AppSpacing.md),
        const _StatsRow(),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Find Nearby Vets'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 1.5),
                  shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.video_call_outlined, size: 16),
                label: const Text('Request Consultation'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: _StatChip(
            value: '12',
            label: 'Nearby Doctors',
            icon: Icons.person_outline,
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatChip(
            value: '4',
            label: 'Active Clinics',
            icon: Icons.local_hospital_outlined,
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatChip(
            value: '2 min',
            label: 'Fastest Response',
            icon: Icons.bolt_outlined,
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const _StatChip({required this.value, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.07),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: AppColors.hint),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MapPlaceholder extends StatelessWidget {
  final int selectedFilter;
  final ValueChanged<int> onFilterChanged;

  const _MapPlaceholder({required this.selectedFilter, required this.onFilterChanged});

  static const _filters = ['Distance', 'Specialty', 'Emergency Only'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          height: 200,
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.1),
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: AppColors.secondary.withValues(alpha: 0.18)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on_outlined, size: 40, color: AppColors.primary.withValues(alpha: 0.5)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Map Loading...',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Enable location to see vets near you',
                style: TextStyle(fontSize: 12, color: AppColors.hint),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(_filters.length, (i) {
              final active = i == selectedFilter;
              return Padding(
                padding: EdgeInsets.only(right: i < _filters.length - 1 ? AppSpacing.sm : 0),
                child: GestureDetector(
                  onTap: () => onFilterChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : Colors.white,
                      borderRadius: AppRadius.fullAll,
                      border: Border.all(
                        color: active ? AppColors.primary : AppColors.secondary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      _filters[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: active ? Colors.white : AppColors.hint,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _ClosestVetCard extends StatelessWidget {
  const _ClosestVetCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.15),
                  borderRadius: AppRadius.smAll,
                ),
                child: const Icon(Icons.star_outline, color: AppColors.secondary, size: 16),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Text(
                'Closest Available Vet',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                child: const Text(
                  'R',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dr. Rahman',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primary),
                    ),
                    const Text(
                      'Poultry Disease Specialist',
                      style: TextStyle(fontSize: 12, color: AppColors.hint),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 13, color: AppColors.primary),
                        const SizedBox(width: 2),
                        const Text(
                          '1.4 km away',
                          style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.secondary.withValues(alpha: 0.12),
                            borderRadius: AppRadius.smAll,
                          ),
                          child: const Text(
                            '● Online',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.secondary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('View Profile'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Request'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConsultationOptionsRow extends StatelessWidget {
  const _ConsultationOptionsRow();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Consultation Options',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _ConsultCard(
                icon: Icons.videocam_outlined,
                iconBg: AppColors.secondary.withValues(alpha: 0.12),
                iconColor: AppColors.secondary,
                title: 'Online',
                status: 'Available now',
                statusColor: AppColors.secondary,
                primaryLabel: 'Chat',
                secondaryLabel: 'Book',
                onPrimary: () {},
                onSecondary: () {},
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _ConsultCard(
                icon: Icons.directions_car_outlined,
                iconBg: AppColors.primary.withValues(alpha: 0.1),
                iconColor: AppColors.primary,
                title: 'Offline Visit',
                status: 'Next: Today 4PM',
                statusColor: Colors.orange,
                primaryLabel: 'Directions',
                secondaryLabel: 'Schedule',
                onPrimary: () {},
                onSecondary: () {},
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConsultCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String status;
  final Color statusColor;
  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  const _ConsultCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.status,
    required this.statusColor,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimary,
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(color: iconBg, borderRadius: AppRadius.smAll),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary),
          ),
          const SizedBox(height: 2),
          Text(
            status,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onPrimary,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 32),
                    padding: EdgeInsets.zero,
                    shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  child: Text(primaryLabel),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: OutlinedButton(
                  onPressed: onSecondary,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size(0, 32),
                    padding: EdgeInsets.zero,
                    shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  child: Text(secondaryLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RegisteredDoctorsList extends StatelessWidget {
  const _RegisteredDoctorsList();

  static const _doctors = [
    _DoctorData(
      name: 'Dr. Rahman',
      specialty: 'Poultry Disease',
      distance: '1.4 km',
      status: 'Online',
      statusType: _DoctorStatus.online,
      action: 'Request Consultation',
      isClinic: false,
    ),
    _DoctorData(
      name: 'Dr. Sultana',
      specialty: 'Farm Visit',
      distance: '2.1 km',
      status: 'Available',
      statusType: _DoctorStatus.available,
      action: 'Book Offline',
      isClinic: false,
    ),
    _DoctorData(
      name: 'City Poultry Clinic',
      specialty: 'Clinic',
      distance: '3.8 km',
      status: 'Open',
      statusType: _DoctorStatus.open,
      action: 'Directions',
      isClinic: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Registered Doctors',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: AppColors.secondary.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              const _DoctorTableHeader(),
              Divider(height: 1, color: AppColors.secondary.withValues(alpha: 0.18)),
              ...List.generate(
                _doctors.length,
                (i) => Column(
                  children: [
                    _DoctorTableRow(data: _doctors[i]),
                    if (i < _doctors.length - 1) Divider(height: 1, color: AppColors.secondary.withValues(alpha: 0.18)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _DoctorStatus { online, available, open }

class _DoctorData {
  final String name;
  final String specialty;
  final String distance;
  final String status;
  final _DoctorStatus statusType;
  final String action;
  final bool isClinic;

  const _DoctorData({
    required this.name,
    required this.specialty,
    required this.distance,
    required this.status,
    required this.statusType,
    required this.action,
    required this.isClinic,
  });
}

class _DoctorTableHeader extends StatelessWidget {
  const _DoctorTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.07),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: _HeaderCell('Name')),
          Expanded(flex: 3, child: _HeaderCell('Specialty')),
          Expanded(flex: 2, child: _HeaderCell('Distance')),
          Expanded(flex: 2, child: _HeaderCell('Status')),
          Expanded(flex: 3, child: _HeaderCell('Action')),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;

  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
    );
  }
}

class _DoctorTableRow extends StatelessWidget {
  final _DoctorData data;

  const _DoctorTableRow({required this.data});

  Color get _statusColor {
    switch (data.statusType) {
      case _DoctorStatus.online:
        return AppColors.secondary;
      case _DoctorStatus.available:
        return AppColors.secondaryContainer;
      case _DoctorStatus.open:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: data.isClinic
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : AppColors.secondary.withValues(alpha: 0.15),
                  child: Icon(
                    data.isClinic ? Icons.local_hospital_outlined : Icons.person_outline,
                    size: 14,
                    color: data.isClinic ? AppColors.primary : AppColors.secondary,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    data.name,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              data.specialty,
              style: const TextStyle(fontSize: 11, color: AppColors.hint),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 11, color: AppColors.primary),
                const SizedBox(width: 2),
                Text(
                  data.distance,
                  style: const TextStyle(fontSize: 11, color: AppColors.hint),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: AppRadius.smAll,
              ),
              child: Text(
                data.status,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: () {},
              child: Text(
                data.action,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
