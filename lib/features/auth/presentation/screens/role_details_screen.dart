import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/theme.dart';
import '../../../../core/router/app_router.dart';

class RoleDetailsScreen extends StatefulWidget {
  final String role;

  const RoleDetailsScreen({super.key, required this.role});

  @override
  State<RoleDetailsScreen> createState() => _RoleDetailsScreenState();
}

class _RoleDetailsScreenState extends State<RoleDetailsScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final AnimationController _waveController;

  // Farmer
  final _farmNameCtrl = TextEditingController();
  final _farmOwnerCtrl = TextEditingController();
  final _farmLocationCtrl = TextEditingController();
  final _farmRegCtrl = TextEditingController();
  final _farmYearsCtrl = TextEditingController();
  final _farmBirdsCtrl = TextEditingController();
  final _farmDiseaseCtrl = TextEditingController();
  final _farmFeedCtrl = TextEditingController();
  final _farmWorkersCtrl = TextEditingController();
  String _farmType = 'Broiler';
  String _experienceLevel = 'Beginner';
  bool _farmConsent = false;

  // Doctor
  final _clinicCtrl = TextEditingController();
  final _practiceAddrCtrl = TextEditingController();
  final _vetDegreeCtrl = TextEditingController();
  final _vetUniCtrl = TextEditingController();
  final _vetGradYearCtrl = TextEditingController();
  final _vetLicenseCtrl = TextEditingController();
  final _vetAuthorityCtrl = TextEditingController();
  final _vetSpecialtyCtrl = TextEditingController();
  final _vetYearsCtrl = TextEditingController();
  final _vetWorkplaceCtrl = TextEditingController();
  final _vetFeesCtrl = TextEditingController();
  DateTime? _vetLicenseExpiry;
  String _consultMode = 'Online';

  // Pharmacy
  final _bizNameCtrl = TextEditingController();
  final _bizContactCtrl = TextEditingController();
  final _bizRegCtrl = TextEditingController();
  final _tradeLicCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _bizAddrCtrl = TextEditingController();
  final _warehouseAddrCtrl = TextEditingController();
  final _pharLicCtrl = TextEditingController();
  final _pharCouncilCtrl = TextEditingController();
  final _storageCtrl = TextEditingController();
  final _deliveryCovCtrl = TextEditingController();
  DateTime? _pharLicExpiry;

  // Delivery
  final _driverLicCtrl = TextEditingController();
  final _licClassCtrl = TextEditingController();
  final _vehicleRegCtrl = TextEditingController();
  final _vehicleInsCtrl = TextEditingController();
  final _priorDelivCtrl = TextEditingController();
  final _areaCovCtrl = TextEditingController();
  final _availCtrl = TextEditingController();
  DateTime? _driverLicExpiry;
  String _vehicleType = 'Motorcycle';

  // Researcher
  final _institutionCtrl = TextEditingController();
  final _instEmailCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _degreeCtrl = TextEditingController();
  final _fieldStudyCtrl = TextEditingController();
  final _resUniCtrl = TextEditingController();
  final _gradYearCtrl = TextEditingController();
  final _expertiseCtrl = TextEditingController();
  final _resYearsCtrl = TextEditingController();
  String _researchRole = 'Disease';
  bool _conflictDeclaration = false;

  static const List<String> _farmTypes = [
    'Broiler', 'Layer', 'Breeder', 'Hatchery', 'Mixed', 'Backyard'
  ];
  static const List<String> _expLevels = [
    'Beginner', 'Intermediate', 'Experienced', 'Expert'
  ];
  static const List<String> _consultModes = ['Online', 'Field Visit', 'Both'];
  static const List<String> _vehicleTypes = [
    'Bike', 'Motorcycle', 'Van', 'Pickup'
  ];
  static const List<String> _researchRoles = [
    'Nutrition', 'Disease', 'Genetics', 'Welfare', 'Growth', 'Economics'
  ];

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _farmNameCtrl.dispose(); _farmOwnerCtrl.dispose();
    _farmLocationCtrl.dispose(); _farmRegCtrl.dispose();
    _farmYearsCtrl.dispose(); _farmBirdsCtrl.dispose();
    _farmDiseaseCtrl.dispose(); _farmFeedCtrl.dispose();
    _farmWorkersCtrl.dispose();
    _clinicCtrl.dispose(); _practiceAddrCtrl.dispose();
    _vetDegreeCtrl.dispose(); _vetUniCtrl.dispose();
    _vetGradYearCtrl.dispose(); _vetLicenseCtrl.dispose();
    _vetAuthorityCtrl.dispose(); _vetSpecialtyCtrl.dispose();
    _vetYearsCtrl.dispose(); _vetWorkplaceCtrl.dispose();
    _vetFeesCtrl.dispose();
    _bizNameCtrl.dispose(); _bizContactCtrl.dispose();
    _bizRegCtrl.dispose(); _tradeLicCtrl.dispose();
    _taxCtrl.dispose(); _bizAddrCtrl.dispose();
    _warehouseAddrCtrl.dispose(); _pharLicCtrl.dispose();
    _pharCouncilCtrl.dispose(); _storageCtrl.dispose();
    _deliveryCovCtrl.dispose();
    _driverLicCtrl.dispose(); _licClassCtrl.dispose();
    _vehicleRegCtrl.dispose(); _vehicleInsCtrl.dispose();
    _priorDelivCtrl.dispose(); _areaCovCtrl.dispose();
    _availCtrl.dispose();
    _institutionCtrl.dispose(); _instEmailCtrl.dispose();
    _deptCtrl.dispose(); _degreeCtrl.dispose();
    _fieldStudyCtrl.dispose(); _resUniCtrl.dispose();
    _gradYearCtrl.dispose(); _expertiseCtrl.dispose();
    _resYearsCtrl.dispose();
    _waveController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(
    DateTime? current,
    void Function(DateTime) onPicked, {
    DateTime? firstDate,
    DateTime? lastDate,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: firstDate ?? DateTime(2000),
      lastDate: lastDate ?? DateTime(2050),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.secondary,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: AppColors.primary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) onPicked(picked);
  }

  void _onSubmit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final destinations = {
      'farmer': AppRoutes.farmerDashboard,
      'doctor': AppRoutes.doctorDashboard,
      'pharmacy': AppRoutes.pharmacyDashboard,
      'delivery': AppRoutes.deliveryDashboard,
      'researcher': AppRoutes.researchDashboard,
    };
    context.go(destinations[widget.role] ?? AppRoutes.farmerDashboard);
  }

  String get _roleLabel {
    const labels = {
      'farmer': 'Farmer',
      'doctor': 'Veterinarian',
      'pharmacy': 'Pharmacy',
      'delivery': 'Delivery Agent',
      'researcher': 'Researcher',
    };
    return labels[widget.role] ?? 'User';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double topHeight = constraints.maxHeight * 0.26;
          const double waveOverlap = 28.0;

          return Stack(
            children: [
              Positioned(
                top: 0, left: 0, right: 0,
                height: topHeight + waveOverlap,
                child: AnimatedBuilder(
                  animation: _waveController,
                  builder: (context, _) => CustomPaint(
                    painter: _WavePainter(
                      progress: _waveController.value,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0, left: 0, right: 0,
                height: topHeight,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.egg_alt, color: Colors.white, size: 20),
                          SizedBox(width: AppSpacing.xs),
                          Text(
                            'Featherflow',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _roleLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const _StepIndicator(
                          current: 3, total: 3, label: 'Complete Profile'),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: topHeight + waveOverlap,
                left: 0, right: 0, bottom: 0,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xl,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_roleLabel Details',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Complete your profile to get full access.',
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 13),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ..._buildRoleFields(),
                        const SizedBox(height: AppSpacing.xl),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _onSubmit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.secondary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: const RoundedRectangleBorder(
                                  borderRadius: AppRadius.lgAll),
                            ),
                            child: const Text(
                              'Create Account',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Center(
                          child: GestureDetector(
                            onTap: () => context.go(AppRoutes.roleSelection),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.arrow_back,
                                    color: AppColors.secondary, size: 15),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  'Back to Role Selection',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildRoleFields() {
    switch (widget.role) {
      case 'farmer':
        return _farmerFields();
      case 'doctor':
        return _doctorFields();
      case 'pharmacy':
        return _pharmacyFields();
      case 'delivery':
        return _deliveryFields();
      case 'researcher':
        return _researcherFields();
      default:
        return _farmerFields();
    }
  }

  List<Widget> _farmerFields() => [
        const _FieldLabel('Farm Name', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _farmNameCtrl,
          hint: 'Name of your farm',
          icon: Icons.home_outlined,
          action: TextInputAction.next,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Farm name is required' : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Farm Owner / Manager Name', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _farmOwnerCtrl,
          hint: 'Full name',
          icon: Icons.person_outline,
          action: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Owner name is required'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Farm Location & Address', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _farmLocationCtrl,
          hint: 'Village, Upazila, District',
          icon: Icons.location_on_outlined,
          action: TextInputAction.next,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Farm location is required' : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Farm Type', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightDropdown<String>(
          value: _farmType,
          items: _farmTypes,
          icon: Icons.category_outlined,
          onChanged: (v) => setState(() => _farmType = v ?? _farmType),
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Number of Birds Currently Kept'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _farmBirdsCtrl,
          hint: 'e.g. 500',
          icon: Icons.egg_outlined,
          keyboard: TextInputType.number,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Farm Registration / License Number'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _farmRegCtrl,
          hint: 'If available',
          icon: Icons.badge_outlined,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Years in Poultry Farming'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _farmYearsCtrl,
          hint: 'e.g. 5',
          icon: Icons.timeline_outlined,
          keyboard: TextInputType.number,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Experience Level'),
        const SizedBox(height: AppSpacing.xs),
        _LightDropdown<String>(
          value: _experienceLevel,
          items: _expLevels,
          icon: Icons.star_outline,
          onChanged: (v) =>
              setState(() => _experienceLevel = v ?? _experienceLevel),
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Primary Disease / Issues Faced'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _farmDiseaseCtrl,
          hint: 'e.g. Newcastle, Coccidiosis',
          icon: Icons.coronavirus_outlined,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Feed Type & Sourcing Method'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _farmFeedCtrl,
          hint: 'e.g. Commercial pellet, local supplier',
          icon: Icons.grass_outlined,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Number of Active Workers'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _farmWorkersCtrl,
          hint: 'e.g. 3',
          icon: Icons.people_outline,
          keyboard: TextInputType.number,
          action: TextInputAction.done,
        ),
        const SizedBox(height: AppSpacing.md),
        _ConsentRow(
          value: _farmConsent,
          label: 'I consent to data collection for flock health and performance tracking.',
          onChanged: (v) => setState(() => _farmConsent = v ?? false),
        ),
      ];

  List<Widget> _doctorFields() => [
        const _FieldLabel('Clinic / Hospital Name', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _clinicCtrl,
          hint: 'Name of your clinic or hospital',
          icon: Icons.local_hospital_outlined,
          action: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Clinic name is required'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Practice Address', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _practiceAddrCtrl,
          hint: 'Street, City, District',
          icon: Icons.location_on_outlined,
          action: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Practice address is required'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Veterinary Degree', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _vetDegreeCtrl,
          hint: 'e.g. DVM, BVSc',
          icon: Icons.school_outlined,
          action: TextInputAction.next,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Degree is required' : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('University Name', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _vetUniCtrl,
          hint: 'University or college name',
          icon: Icons.account_balance_outlined,
          action: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'University name is required'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Graduation Year', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _vetGradYearCtrl,
          hint: 'e.g. 2015',
          icon: Icons.calendar_today_outlined,
          keyboard: TextInputType.number,
          action: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Graduation year is required'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('License / Registration Number', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _vetLicenseCtrl,
          hint: 'Your license number',
          icon: Icons.badge_outlined,
          action: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'License number is required'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('License Issuing Authority', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _vetAuthorityCtrl,
          hint: 'e.g. Bangladesh Veterinary Council',
          icon: Icons.verified_outlined,
          action: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Issuing authority is required'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('License Expiry Date', required: true),
        const SizedBox(height: AppSpacing.xs),
        _DatePickerField(
          value: _vetLicenseExpiry,
          hint: 'DD / MM / YYYY',
          onTap: () => _pickDate(
            _vetLicenseExpiry,
            (d) => setState(() => _vetLicenseExpiry = d),
            firstDate: DateTime.now(),
            lastDate: DateTime(2060),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Specialty / Poultry Focus Area'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _vetSpecialtyCtrl,
          hint: 'e.g. Broiler disease, Layer health',
          icon: Icons.biotech_outlined,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Years of Experience'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _vetYearsCtrl,
          hint: 'e.g. 10',
          icon: Icons.timeline_outlined,
          keyboard: TextInputType.number,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Current Workplace'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _vetWorkplaceCtrl,
          hint: 'Hospital, clinic, or organization',
          icon: Icons.business_outlined,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Consultation Mode', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightDropdown<String>(
          value: _consultMode,
          items: _consultModes,
          icon: Icons.videocam_outlined,
          onChanged: (v) => setState(() => _consultMode = v ?? _consultMode),
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Service Fees / Consultation Rate'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _vetFeesCtrl,
          hint: 'e.g. ৳ 500 per consultation',
          icon: Icons.payments_outlined,
          keyboard: TextInputType.number,
          action: TextInputAction.done,
        ),
      ];

  List<Widget> _pharmacyFields() => [
        const _FieldLabel('Business / Organization Name', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _bizNameCtrl,
          hint: 'Registered business name',
          icon: Icons.store_outlined,
          action: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Business name is required'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Authorized Contact Person', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _bizContactCtrl,
          hint: 'Full name of authorized person',
          icon: Icons.person_outline,
          action: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Contact person is required'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Business Registration Number', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _bizRegCtrl,
          hint: 'Company registration number',
          icon: Icons.badge_outlined,
          action: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Registration number is required'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Trade License', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _tradeLicCtrl,
          hint: 'Trade license number',
          icon: Icons.description_outlined,
          action: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Trade license is required'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Tax / VAT / TIN Number'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _taxCtrl,
          hint: 'Tax identification number',
          icon: Icons.receipt_long_outlined,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Business Address', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _bizAddrCtrl,
          hint: 'Street, City, District',
          icon: Icons.location_on_outlined,
          action: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Business address is required'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Warehouse Address'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _warehouseAddrCtrl,
          hint: 'If different from business address',
          icon: Icons.warehouse_outlined,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Pharmacist License Number', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _pharLicCtrl,
          hint: 'Pharmacy license / registration number',
          icon: Icons.local_pharmacy_outlined,
          action: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Pharmacist license is required'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Pharmacy Council / Board Registration Number'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _pharCouncilCtrl,
          hint: 'Council registration number',
          icon: Icons.verified_outlined,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Professional License Expiry Date', required: true),
        const SizedBox(height: AppSpacing.xs),
        _DatePickerField(
          value: _pharLicExpiry,
          hint: 'DD / MM / YYYY',
          onTap: () => _pickDate(
            _pharLicExpiry,
            (d) => setState(() => _pharLicExpiry = d),
            firstDate: DateTime.now(),
            lastDate: DateTime(2060),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Storage / Cold-Chain Capability'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _storageCtrl,
          hint: 'e.g. Refrigerated storage, -20°C',
          icon: Icons.kitchen_outlined,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Delivery Coverage Area'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _deliveryCovCtrl,
          hint: 'Districts or areas covered',
          icon: Icons.map_outlined,
          action: TextInputAction.done,
        ),
      ];

  List<Widget> _deliveryFields() => [
        const _FieldLabel("Driver's License Number", required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _driverLicCtrl,
          hint: 'Your driving license number',
          icon: Icons.badge_outlined,
          action: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? "Driver's license number is required"
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('License Class'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _licClassCtrl,
          hint: 'e.g. Class A, B',
          icon: Icons.class_outlined,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('License Expiry Date', required: true),
        const SizedBox(height: AppSpacing.xs),
        _DatePickerField(
          value: _driverLicExpiry,
          hint: 'DD / MM / YYYY',
          onTap: () => _pickDate(
            _driverLicExpiry,
            (d) => setState(() => _driverLicExpiry = d),
            firstDate: DateTime.now(),
            lastDate: DateTime(2060),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Vehicle Type', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightDropdown<String>(
          value: _vehicleType,
          items: _vehicleTypes,
          icon: Icons.two_wheeler_outlined,
          onChanged: (v) =>
              setState(() => _vehicleType = v ?? _vehicleType),
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Vehicle Registration Number', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _vehicleRegCtrl,
          hint: 'Vehicle plate number',
          icon: Icons.directions_car_outlined,
          action: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Vehicle registration is required'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Vehicle Insurance Details'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _vehicleInsCtrl,
          hint: 'Insurance policy number, if applicable',
          icon: Icons.shield_outlined,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Prior Delivery Experience'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _priorDelivCtrl,
          hint: 'e.g. 2 years with Pathao',
          icon: Icons.history_outlined,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Area Coverage', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _areaCovCtrl,
          hint: 'Districts or zones you can cover',
          icon: Icons.map_outlined,
          action: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Area coverage is required'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Availability / Schedule'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _availCtrl,
          hint: 'e.g. Weekdays 8am–6pm',
          icon: Icons.schedule_outlined,
          action: TextInputAction.done,
        ),
      ];

  List<Widget> _researcherFields() => [
        const _FieldLabel('Institution / Company Name', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _institutionCtrl,
          hint: 'University, research institute, or company',
          icon: Icons.account_balance_outlined,
          action: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Institution name is required'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Institutional Email', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _instEmailCtrl,
          hint: 'you@institution.edu',
          icon: Icons.email_outlined,
          keyboard: TextInputType.emailAddress,
          action: TextInputAction.next,
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return 'Institutional email is required';
            }
            if (!v.contains('@')) return 'Enter a valid email';
            return null;
          },
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Department', required: true),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _deptCtrl,
          hint: 'e.g. Poultry Science, Animal Health',
          icon: Icons.domain_outlined,
          action: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Department is required'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Highest Academic Degree'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _degreeCtrl,
          hint: 'e.g. PhD, MSc, BSc',
          icon: Icons.school_outlined,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Field of Study'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _fieldStudyCtrl,
          hint: 'e.g. Veterinary Medicine, Animal Nutrition',
          icon: Icons.biotech_outlined,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('University / College Name'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _resUniCtrl,
          hint: 'Where you studied',
          icon: Icons.account_balance_outlined,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Year of Graduation'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _gradYearCtrl,
          hint: 'e.g. 2018',
          icon: Icons.calendar_today_outlined,
          keyboard: TextInputType.number,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Areas of Expertise'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _expertiseCtrl,
          hint: 'e.g. Avian pathology, Feed formulation',
          icon: Icons.psychology_outlined,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Years of Research Experience'),
        const SizedBox(height: AppSpacing.xs),
        _LightField(
          controller: _resYearsCtrl,
          hint: 'e.g. 7',
          icon: Icons.timeline_outlined,
          keyboard: TextInputType.number,
          action: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel('Research Role Type'),
        const SizedBox(height: AppSpacing.xs),
        _LightDropdown<String>(
          value: _researchRole,
          items: _researchRoles,
          icon: Icons.science_outlined,
          onChanged: (v) =>
              setState(() => _researchRole = v ?? _researchRole),
        ),
        const SizedBox(height: AppSpacing.md),
        _ConsentRow(
          value: _conflictDeclaration,
          label: 'I declare that I have no conflict of interest that could affect my research integrity.',
          onChanged: (v) =>
              setState(() => _conflictDeclaration = v ?? false),
        ),
      ];
}

class _StepIndicator extends StatelessWidget {
  final int current;
  final int total;
  final String label;

  const _StepIndicator(
      {required this.current, required this.total, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(total * 2 - 1, (i) {
            if (i.isOdd) {
              return Container(
                width: 24,
                height: 2,
                color: Colors.white.withValues(alpha: 0.35),
              );
            }
            final step = i ~/ 2 + 1;
            final isActive = step == current;
            final isDone = step < current;
            return Container(
              width: isActive ? 26 : 22,
              height: isActive ? 26 : 22,
              decoration: BoxDecoration(
                color: isActive || isDone
                    ? AppColors.secondary
                    : Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check, color: Colors.white, size: 13)
                    : Text(
                        '$step',
                        style: TextStyle(
                          color: isActive
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.6),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            );
          }),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final bool required;

  const _FieldLabel(this.text, {this.required = false});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: text,
            style: const TextStyle(
              color: Color(0xFF2A2A2A),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(
                color: Color(0xFFFF5C6A),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _LightField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboard;
  final TextInputAction? action;
  final String? Function(String?)? validator;

  const _LightField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboard,
    this.action,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      textInputAction: action,
      style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        errorStyle: const TextStyle(color: Color(0xFFFF5C6A), fontSize: 12),
        filled: true,
        fillColor: const Color(0xFFF7F7F7),
        prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),

        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: AppColors.secondary, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: Color(0xFFFF5C6A)),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: Color(0xFFFF5C6A), width: 1.5),
        ),
      ),
      validator: validator,
    );
  }
}

class _LightDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final IconData icon;
  final void Function(T?)? onChanged;

  const _LightDropdown({
    required this.value,
    required this.items,
    required this.icon,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade400),
          style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 14),
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Row(
                      children: [
                        Icon(icon, color: Colors.grey.shade400, size: 20),
                        const SizedBox(width: AppSpacing.sm),
                        Text('$item'),
                      ],
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final DateTime? value;
  final String hint;
  final VoidCallback onTap;

  const _DatePickerField({
    required this.value,
    required this.hint,
    required this.onTap,
  });

  String _format(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                color: Colors.grey.shade400, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Text(
              value != null ? _format(value!) : hint,
              style: TextStyle(
                color: value != null
                    ? const Color(0xFF1A1A1A)
                    : Colors.grey.shade400,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsentRow extends StatelessWidget {
  final bool value;
  final String label;
  final void Function(bool?)? onChanged;

  const _ConsentRow({
    required this.value,
    required this.label,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.secondary,
            shape:
                RoundedRectangleBorder(borderRadius: AppRadius.xsAll),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _WavePainter extends CustomPainter {
  final double progress;
  final Color color;

  _WavePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const double amplitude = 14.0;
    const double waveOverlap = 28.0;
    final double baseline = size.height - waveOverlap;
    final double phase = progress * 2 * math.pi;

    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, baseline);

    for (double x = size.width; x >= 0; x -= 2) {
      final double y = baseline +
          amplitude * math.sin((x / size.width * 2 * math.pi) - phase);
      path.lineTo(x, y);
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.progress != progress;
}
