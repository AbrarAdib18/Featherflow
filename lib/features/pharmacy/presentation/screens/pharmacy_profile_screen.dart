import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/auth_service.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/profile_photo_field.dart';
import '../../data/services/pharmacy_catalogue_service.dart';
import '../../data/services/pharmacy_session.dart';
import '../pharmacy_theme.dart';

/// Every field collected on the pharmacy signup form
/// (pharmacy_signup_screen.dart) is visible and editable here — the
/// dashboard's small `_profile()` subset (name/license/location/phone) is
/// display-only summary data, this is the real "edit my profile" surface.
class PharmacyProfileScreen extends StatefulWidget {
  final bool embedded;
  const PharmacyProfileScreen({super.key, this.embedded = false});

  @override
  State<PharmacyProfileScreen> createState() => _PharmacyProfileScreenState();
}

// Field key -> label, grouped for display.
const _kAccountFields = [
  ('full_name', 'Full name'),
  ('phone', 'Phone'),
  ('present_address', 'Present address'),
];
const _kBusinessFields = [
  ('business_name', 'Business / pharmacy name'),
  ('contact_person', 'Contact person'),
  ('business_reg_number', 'Business registration number'),
  ('trade_license_number', 'Trade license number'),
  ('tax_number', 'Tax number'),
  ('business_address', 'Business address'),
  ('warehouse_address', 'Warehouse address'),
];
const _kComplianceFields = [
  ('responsible_pharmacist', 'Responsible pharmacist'),
  ('pharmacy_license_number', 'Pharmacy license number'),
  ('council_registration', 'Pharmacy council registration'),
  ('number_of_pharmacists', 'Number of pharmacists'),
  ('license_expiry', 'License expiry (YYYY-MM-DD)'),
  ('permitted_products', 'Permitted products'),
  ('storage_requirements', 'Storage requirements'),
];
const _kOperationsFields = [
  ('delivery_coverage', 'Delivery coverage area'),
  ('returns_policy', 'Returns policy'),
];
const _kFinancialFields = [
  ('bank_account', 'Bank account'),
  ('signatory', 'Authorized signatory'),
];
const _kDocFields = [
  ('trade_license', 'Pharmacy license document'),
  ('business_registration_cert_url', 'Business registration certificate'),
  ('responsible_pharmacist_cert_url', 'Pharmacist certificate'),
];

class _PharmacyProfileScreenState extends State<PharmacyProfileScreen> {
  final _controllers = <String, TextEditingController>{
    for (final f in [..._kAccountFields, ..._kBusinessFields, ..._kComplianceFields,
        ..._kOperationsFields, ..._kFinancialFields])
      f.$1: TextEditingController(),
  };
  final _docs = <String, String>{};

  bool _editing = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _email = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await PharmacyCatalogueService.instance.fullProfile();
      if (!mounted) return;
      setState(() {
        for (final entry in _controllers.entries) {
          entry.value.text = data[entry.key]?.toString() ?? '';
        }
        for (final f in _kDocFields) {
          _docs[f.$1] = data[f.$1]?.toString() ?? '';
        }
        _email = data['email']?.toString() ?? '';
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ErrorStateView.humanize(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final body = {for (final entry in _controllers.entries) entry.key: entry.value.text.trim()};
      await PharmacyCatalogueService.instance.updateProfile(body);
      await PharmacySession.instance.refresh(silent: true);
      if (!mounted) return;
      setState(() {
        _editing = false;
        _saving = false;
      });
      showPharmacyNotice(context, 'Profile updated.', PhColors.green, Icons.check_circle_outline);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showPharmacyNotice(context, ErrorStateView.humanize(e), PhColors.red, Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _body(context);
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: PhColors.bg,
      appBar: AppBar(
        backgroundColor: PhColors.appBar,
        foregroundColor: Colors.white,
        leading: phBackLeading(context, embedded: false),
        title: const Text('Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: body,
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: PhColors.secondary));
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.cloud_off_outlined, size: 42, color: PhColors.grey.withValues(alpha: .5)),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: PhColors.textSecondary), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
    }
    return ListenableBuilder(
      listenable: AuthService.instance,
      builder: (context, _) {
        final user = AuthService.instance.currentSession?.user;
        return RefreshIndicator(
          onRefresh: _load,
          color: PhColors.secondary,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Center(
                child: ProfilePhotoField(
                  radius: 48,
                  currentUrl: user?.profilePhotoUrl ?? '',
                  fallbackIcon: Icons.local_pharmacy_outlined,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(_controllers['business_name']!.text.isNotEmpty
                        ? _controllers['business_name']!.text
                        : PharmacySession.instance.profile.name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: PhColors.textPrimary)),
              ),
              Center(
                child: Text(_email, style: const TextStyle(fontSize: 12, color: PhColors.textSecondary)),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: _editing
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton(
                          onPressed: _saving ? null : () => setState(() { _editing = false; _load(); }),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 4),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: PhColors.secondary),
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Save'),
                        ),
                      ])
                    : TextButton.icon(
                        onPressed: () => setState(() => _editing = true),
                        icon: const Icon(Icons.edit_outlined, size: 16, color: PhColors.secondary),
                        label: const Text('Edit profile', style: TextStyle(color: PhColors.secondary)),
                      ),
              ),
              _section('Account', _kAccountFields),
              _section('Business information', _kBusinessFields),
              _section('Pharmacist & compliance', _kComplianceFields),
              _section('Operations', _kOperationsFields),
              _section('Financial', _kFinancialFields),
              _docsSection(),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await AuthService.instance.clearSession();
                    if (context.mounted) context.go(AppRoutes.login);
                  },
                  style: OutlinedButton.styleFrom(
                      foregroundColor: PhColors.red,
                      side: const BorderSide(color: PhColors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Sign out'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _section(String title, List<(String, String)> fields) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: PhColors.textSecondary)),
          const SizedBox(height: 8),
          for (final f in fields) _fieldRow(f.$1, f.$2),
        ],
      ),
    );
  }

  Widget _fieldRow(String key, String label) {
    final ctrl = _controllers[key]!;
    if (_editing) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: ctrl,
          style: phFieldText,
          minLines: 1,
          maxLines: label.toLowerCase().contains('address') ||
                  label.toLowerCase().contains('policy') ||
                  label.toLowerCase().contains('products') ||
                  label.toLowerCase().contains('requirements')
              ? 2
              : 1,
          decoration: phInput(label, Icons.edit_outlined),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: phCard(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: PhColors.textSecondary)),
        const SizedBox(height: 2),
        Text(ctrl.text.isEmpty ? '—' : ctrl.text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: PhColors.textPrimary)),
      ]),
    );
  }

  Widget _docsSection() {
    final hasAny = _kDocFields.any((f) => (_docs[f.$1] ?? '').isNotEmpty);
    if (!hasAny) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Verification documents',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: PhColors.textSecondary)),
          const SizedBox(height: 4),
          const Text('Uploaded at signup. Contact support to replace a document.',
              style: TextStyle(fontSize: 10.5, color: PhColors.grey)),
          const SizedBox(height: 8),
          for (final f in _kDocFields)
            if ((_docs[f.$1] ?? '').isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: phCard(),
                child: Row(children: [
                  const Icon(Icons.description_outlined, color: PhColors.medicines, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(f.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: PhColors.textPrimary)),
                  ),
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse(_docs[f.$1]!), mode: LaunchMode.externalApplication),
                    child: const Text('View'),
                  ),
                ]),
              ),
        ],
      ),
    );
  }
}
