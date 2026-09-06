import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/core/l10n/language_notifier.dart';
import 'package:featherflow/core/l10n/language_dialog.dart';
import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/core/router/app_router.dart';
import '../../data/farmer_profile_service.dart';

const _farmTypes = [
  'broiler', 'layer', 'breeder', 'hatchery', 'mixed', 'backyard',
];
const _experienceLevels = ['beginner', 'intermediate', 'expert'];

class FarmerProfileScreen extends StatefulWidget {
  const FarmerProfileScreen({super.key});

  @override
  State<FarmerProfileScreen> createState() => _FarmerProfileScreenState();
}

class _FarmerProfileScreenState extends State<FarmerProfileScreen> {
  Map<String, dynamic>? _profile;
  String? _error;
  bool _loading = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !_loading) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final p = await FarmerProfileService.get();
      if (mounted) {
        setState(() {
          _profile = p;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _signOut() async {
    await AuthService.instance.clearSession();
    if (mounted) context.go(AppRoutes.login);
  }

  Future<void> _edit() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _EditProfileSheet(profile: _profile!),
      ),
    );
    if (ok == true) {
      _snack('Profile updated');
      _load();
    }
  }

  Future<void> _addPhoto() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    final file = res?.files.firstOrNull;
    if (file?.bytes == null) return;
    try {
      final r = await FarmerProfileService.uploadPhoto(file!.bytes!, file.name);
      if (mounted) {
        setState(() => _profile!['farm_photos'] = r['farm_photos']);
      }
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _removePhoto(String url) async {
    try {
      final r = await FarmerProfileService.deletePhoto(url);
      if (mounted) setState(() => _profile!['farm_photos'] = r['farm_photos']);
    } catch (e) {
      _snack(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final account = (p?['account'] as Map?) ?? const {};
    final photos = (p?['farm_photos'] as List?) ?? const [];
    final name = (account['full_name'] ?? '').toString().isNotEmpty
        ? account['full_name'].toString()
        : (account['email']?.toString().split('@').first ?? 'Farmer');
    final verified = p?['is_verified'] == true;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop()),
        title: const Text('My Profile',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        actions: [
          if (p != null)
            IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.white),
                onPressed: _edit),
          IconButton(
              icon: const Icon(Icons.home, color: Colors.white),
              onPressed: () => context.go('/farmer')),
        ],
      ),
      body: p == null
          ? Center(
              child: _error != null
                  ? Text(_error!)
                  : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(children: [
                Container(
                  width: double.infinity,
                  color: AppColors.primary,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  child: Column(children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundColor: AppColors.secondaryContainer,
                      backgroundImage: (account['profile_photo_url'] ?? '')
                              .toString()
                              .isNotEmpty
                          ? NetworkImage(account['profile_photo_url'].toString())
                          : null,
                      child: (account['profile_photo_url'] ?? '')
                              .toString()
                              .isEmpty
                          ? Text(name[0].toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700))
                          : null,
                    ),
                    const SizedBox(height: 10),
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 3),
                      decoration: BoxDecoration(
                          color: verified
                              ? AppColors.secondary
                              : Colors.orange,
                          borderRadius: AppRadius.fullAll),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                            verified
                                ? Icons.verified
                                : Icons.hourglass_bottom,
                            color: Colors.white,
                            size: 13),
                        const SizedBox(width: 4),
                        Text(
                            verified
                                ? 'Verified farm'
                                : 'Verification pending',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    Text(account['email']?.toString() ?? '',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _card('Farm details', Icons.agriculture, [
                        _row('Farm name', p['farm_name']?.toString() ?? '—'),
                        _row('Owner / manager',
                            p['owner_name']?.toString() ?? '—'),
                        _row('Farm type',
                            (p['farm_type'] ?? '').toString().toUpperCase()),
                        _row('Birds kept', '${p['number_of_birds'] ?? 0}'),
                        _row('Active workers',
                            '${p['number_of_active_workers'] ?? 0}'),
                        _row('Years farming', '${p['years_in_farming'] ?? 0}'),
                        _row('Experience',
                            (p['experience_level'] ?? '—').toString()),
                        _row('Registration no.',
                            p['farm_registration_number']?.toString().isNotEmpty ==
                                    true
                                ? p['farm_registration_number'].toString()
                                : '—'),
                        _row('Location', p['farm_location']?.toString() ?? '—'),
                      ]),
                      const SizedBox(height: 12),
                      _card('Operations', Icons.healing_outlined, [
                        _row('Primary diseases',
                            p['primary_diseases_faced']?.toString().isNotEmpty ==
                                    true
                                ? p['primary_diseases_faced'].toString()
                                : '—'),
                        _row('Feed type',
                            p['feed_type']?.toString().isNotEmpty == true
                                ? p['feed_type'].toString()
                                : '—'),
                        _row('Feed sourcing',
                            p['feed_sourcing_method']?.toString().isNotEmpty ==
                                    true
                                ? p['feed_sourcing_method'].toString()
                                : '—'),
                        _row('Vet / consultant',
                            p['existing_vet_consultant']?.toString().isNotEmpty ==
                                    true
                                ? p['existing_vet_consultant'].toString()
                                : '—'),
                        _row('Data-collection consent',
                            p['consent_data_collection'] == true ? 'Yes' : 'No'),
                      ]),
                      const SizedBox(height: 12),
                      _photoSection(photos),
                      const SizedBox(height: 12),
                      _card('Account', Icons.manage_accounts_outlined, [
                        _row('Phone', account['phone']?.toString() ?? '—'),
                        _row('Emergency contact',
                            (account['emergency_contact_name'] ?? '')
                                        .toString()
                                        .isNotEmpty ==
                                    true
                                ? '${account['emergency_contact_name']} • ${account['emergency_contact_phone']}'
                                : '—'),
                        _row('Status',
                            (account['account_status'] ?? '').toString().toUpperCase()),
                      ]),
                      const SizedBox(height: 12),
                      ListTile(
                        tileColor: Colors.white,
                        shape: const RoundedRectangleBorder(
                            borderRadius: AppRadius.mdAll,
                            side: BorderSide(color: Color(0xFFDEEAE5))),
                        leading: const Icon(Icons.workspace_premium_outlined,
                            color: AppColors.primary),
                        title: const Text('Subscription',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.black87)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go('/subscription'),
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        tileColor: Colors.white,
                        shape: const RoundedRectangleBorder(
                            borderRadius: AppRadius.mdAll,
                            side: BorderSide(color: Color(0xFFDEEAE5))),
                        leading: const Icon(Icons.language_outlined,
                            color: AppColors.primary),
                        title: const Text('Language',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.black87)),
                        trailing: Text(
                            LanguageNotifier.instance.isBengali
                                ? 'বাংলা'
                                : 'English',
                            style: const TextStyle(
                                color: AppColors.secondary,
                                fontWeight: FontWeight.w600)),
                        onTap: () =>
                            showLanguageDialog(context, dismissible: true),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _signOut,
                          icon: const Icon(Icons.logout, size: 18),
                          label: const Text('Sign out'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(
                                color: AppColors.error, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ]),
            ),
    );
  }

  Widget _photoSection(List photos) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: const Color(0xFFDEEAE5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.photo_library_outlined,
              size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          const Text('Farm photos',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: Colors.black87)),
          const Spacer(),
          TextButton.icon(
              onPressed: _addPhoto,
              icon: const Icon(Icons.add_a_photo_outlined, size: 16),
              label: const Text('Add')),
        ]),
        const SizedBox(height: 8),
        if (photos.isEmpty)
          const Text('No photos yet. Add photos of the farm, sheds and birds.',
              style: TextStyle(fontSize: 12, color: Colors.black54))
        else
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final url = photos[i].toString();
                return Stack(children: [
                  ClipRRect(
                    borderRadius: AppRadius.smAll,
                    child: Image.network(url,
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            width: 90,
                            height: 90,
                            color: const Color(0xFFF0F7F4),
                            child: const Icon(Icons.broken_image_outlined))),
                  ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: GestureDetector(
                      onTap: () => _removePhoto(url),
                      child: Container(
                        decoration: const BoxDecoration(
                            color: Colors.black54, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(Icons.close,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ]);
              },
            ),
          ),
      ]),
    );
  }

  Widget _card(String title, IconData icon, List<Widget> rows) => Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: const Color(0xFFDEEAE5))),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: Colors.black87)),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFFDEEAE5)),
          ...rows,
          const SizedBox(height: 6),
        ]),
      );

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 2,
            child: Text(k,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          Expanded(
            flex: 3,
            child: Text(v,
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87)),
          ),
        ]),
      );
}

class _EditProfileSheet extends StatefulWidget {
  final Map<String, dynamic> profile;
  const _EditProfileSheet({required this.profile});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final _farmName = TextEditingController(
      text: widget.profile['farm_name']?.toString());
  late final _ownerName = TextEditingController(
      text: widget.profile['owner_name']?.toString());
  late final _location = TextEditingController(
      text: widget.profile['farm_location']?.toString());
  late final _address = TextEditingController(
      text: widget.profile['farm_address']?.toString());
  late final _birds = TextEditingController(
      text: '${widget.profile['number_of_birds'] ?? ''}');
  late final _workers = TextEditingController(
      text: '${widget.profile['number_of_active_workers'] ?? ''}');
  late final _years = TextEditingController(
      text: '${widget.profile['years_in_farming'] ?? ''}');
  late final _reg = TextEditingController(
      text: widget.profile['farm_registration_number']?.toString());
  late final _diseases = TextEditingController(
      text: widget.profile['primary_diseases_faced']?.toString());
  late final _feedType = TextEditingController(
      text: widget.profile['feed_type']?.toString());
  late final _feedSourcing = TextEditingController(
      text: widget.profile['feed_sourcing_method']?.toString());
  late final _vet = TextEditingController(
      text: widget.profile['existing_vet_consultant']?.toString());
  late String _farmType = _farmTypes.contains(widget.profile['farm_type'])
      ? widget.profile['farm_type'].toString()
      : 'mixed';
  late String _experience =
      _experienceLevels.contains(widget.profile['experience_level'])
          ? widget.profile['experience_level'].toString()
          : 'beginner';
  late bool _consent = widget.profile['consent_data_collection'] == true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _farmName, _ownerName, _location, _address, _birds, _workers, _years,
      _reg, _diseases, _feedType, _feedSourcing, _vet,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FarmerProfileService.update({
        'farm_name': _farmName.text.trim(),
        'owner_name': _ownerName.text.trim(),
        'farm_location': _location.text.trim(),
        'farm_address': _address.text.trim(),
        'farm_type': _farmType,
        'experience_level': _experience,
        if (_birds.text.trim().isNotEmpty) 'number_of_birds': _birds.text.trim(),
        if (_workers.text.trim().isNotEmpty)
          'number_of_active_workers': _workers.text.trim(),
        if (_years.text.trim().isNotEmpty)
          'years_in_farming': _years.text.trim(),
        'farm_registration_number': _reg.text.trim(),
        'primary_diseases_faced': _diseases.text.trim(),
        'feed_type': _feedType.text.trim(),
        'feed_sourcing_method': _feedSourcing.text.trim(),
        'existing_vet_consultant': _vet.text.trim(),
        'consent_data_collection': _consent,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Text('Edit farm profile',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Colors.black87)),
            const Spacer(),
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close)),
          ]),
          _f(_farmName, 'Farm name'),
          _f(_ownerName, 'Farm owner / manager'),
          _f(_location, 'Farm location'),
          _f(_address, 'Exact address'),
          DropdownButtonFormField<String>(
            initialValue: _farmType,
            decoration:
                const InputDecoration(labelText: 'Farm type', filled: true),
            items: [
              for (final t in _farmTypes)
                DropdownMenuItem(
                    value: t,
                    child: Text(t[0].toUpperCase() + t.substring(1))),
            ],
            onChanged: (v) => setState(() => _farmType = v ?? _farmType),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _f(_birds, 'Birds kept', number: true)),
            const SizedBox(width: 8),
            Expanded(child: _f(_workers, 'Active workers', number: true)),
          ]),
          Row(children: [
            Expanded(child: _f(_years, 'Years farming', number: true)),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _experience,
                decoration: const InputDecoration(
                    labelText: 'Experience', filled: true),
                items: [
                  for (final e in _experienceLevels)
                    DropdownMenuItem(
                        value: e,
                        child: Text(e[0].toUpperCase() + e.substring(1))),
                ],
                onChanged: (v) =>
                    setState(() => _experience = v ?? _experience),
              ),
            ),
          ]),
          _f(_reg, 'Farm registration number'),
          _f(_diseases, 'Primary diseases / issues'),
          _f(_feedType, 'Feed type'),
          _f(_feedSourcing, 'Feed sourcing method'),
          _f(_vet, 'Vet / consultant you work with'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Consent to flock-health data collection',
                style: TextStyle(fontSize: 13, color: Colors.black87)),
            value: _consent,
            activeThumbColor: AppColors.secondary,
            onChanged: (v) => setState(() => _consent = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.error)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _save,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save changes'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _f(TextEditingController c, String label, {bool number = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(labelText: label, filled: true),
        ),
      );
}
