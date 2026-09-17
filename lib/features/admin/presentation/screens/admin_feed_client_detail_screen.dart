import 'package:flutter/material.dart';

import '../../../../core/widgets/catalogue_image_picker.dart';
import '../../../../core/widgets/error_state.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/admin_api_service.dart';
import '../admin_theme.dart';
import '../widgets/permission_guard.dart';
import 'admin_feed_product_form_screen.dart';

/// Feed client (company) profile — contact details, logo/cover, products,
/// and status controls (pending/active/suspended/rejected). Every status
/// change goes through `updateFeedCompany`, which is itself audited the
/// same way every other admin PATCH in this backend is (ActivityLog via
/// admin_rbac's request logging), so no separate audit wiring was needed
/// here.
class AdminFeedClientDetailScreen extends StatefulWidget {
  const AdminFeedClientDetailScreen({super.key, required this.clientId});
  final String clientId;

  @override
  State<AdminFeedClientDetailScreen> createState() => _AdminFeedClientDetailScreenState();
}

class _AdminFeedClientDetailScreenState extends State<AdminFeedClientDetailScreen> {
  final _api = AdminApiService.instance;
  Map<String, dynamic>? _client;
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;
  String? _error;
  bool _changed = false;
  bool _editing = false;

  late final _name = TextEditingController();
  late final _contactPerson = TextEditingController();
  late final _phone = TextEditingController();
  late final _email = TextEditingController();
  late final _address = TextEditingController();
  late final _district = TextEditingController();
  late final _upazila = TextEditingController();
  late final _description = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.feedCompanyDetail(widget.clientId),
        _api.feedProducts(filters: {'company_id': widget.clientId}),
      ]);
      if (!mounted) return;
      final client = results[0] as Map<String, dynamic>;
      _name.text = client['name'] ?? '';
      _contactPerson.text = client['contact_person'] ?? '';
      _phone.text = client['contact_phone'] ?? '';
      _email.text = client['contact_email'] ?? '';
      _address.text = client['address'] ?? '';
      _district.text = client['district'] ?? '';
      _upazila.text = client['upazila'] ?? '';
      _description.text = client['description'] ?? '';
      setState(() {
        _client = client;
        _products = results[1] as List<Map<String, dynamic>>;
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

  void _toast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Future<void> _save() async {
    try {
      final updated = await _api.updateFeedCompany(widget.clientId, {
        'name': _name.text.trim(), 'contact_person': _contactPerson.text.trim(),
        'contact_phone': _phone.text.trim(), 'contact_email': _email.text.trim(),
        'address': _address.text.trim(), 'district': _district.text.trim(),
        'upazila': _upazila.text.trim(), 'description': _description.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _client = updated;
        _editing = false;
        _changed = true;
      });
      _toast('Client updated', AColors.green);
    } catch (e) {
      _toast(ErrorStateView.humanize(e), AColors.red);
    }
  }

  Future<void> _setStatus(String status) async {
    try {
      final updated = await _api.updateFeedCompany(widget.clientId, {'status': status});
      if (!mounted) return;
      setState(() {
        _client = updated;
        _changed = true;
      });
      _toast('Client marked $status', AColors.green);
    } catch (e) {
      _toast(ErrorStateView.humanize(e), AColors.red);
    }
  }

  Color _statusColor(String status) => switch (status) {
        'active' => AColors.green,
        'pending' => Colors.orange,
        'suspended' || 'rejected' => AColors.red,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AColors.appBar,
        foregroundColor: Colors.white,
        leading: BackButton(onPressed: () => Navigator.pop(context, _changed)),
        title: Text(_client?['name'] ?? 'Client', style: const TextStyle(color: Colors.white)),
        actions: [
          if (!_loading && _error == null)
            PermissionGuard(
              module: AdminModule.feedClients,
              permission: AdminPermission.edit,
              child: IconButton(
                icon: Icon(_editing ? Icons.close : Icons.edit, color: Colors.white),
                onPressed: () => setState(() => _editing = !_editing),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorStateView(message: _error!, onRetry: _load)
              : _body(),
    );
  }

  Widget _body() {
    final client = _client!;
    final status = client['status']?.toString() ?? 'active';
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(
            child: CatalogueImagePicker(
              currentUrl: client['logo_url'],
              aspectRatio: 1,
              label: 'Add logo',
              fallbackIcon: Icons.storefront,
              onUpload: (bytes, filename) async {
                final url = await _api.uploadFeedCompanyLogo(widget.clientId, bytes, filename);
                setState(() => _changed = true);
                return url;
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: CatalogueImagePicker(
              currentUrl: client['cover_url'],
              aspectRatio: 2,
              label: 'Add cover image',
              fallbackIcon: Icons.image_outlined,
              onUpload: (bytes, filename) async {
                final url = await _api.uploadFeedCompanyCover(widget.clientId, bytes, filename);
                setState(() => _changed = true);
                return url;
              },
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: _statusColor(status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
          child: Text(status.toUpperCase(),
              style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        const SizedBox(height: 16),
        if (_editing) ..._editForm() else ..._readOnlyDetails(client),
        const SizedBox(height: 20),
        PermissionGuard(
          module: AdminModule.feedClients,
          permission: AdminPermission.suspend,
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in const ['active', 'pending', 'suspended', 'rejected'])
              if (s != status)
                OutlinedButton(onPressed: () => _setStatus(s), child: Text('Mark ${s[0].toUpperCase()}${s.substring(1)}')),
          ]),
        ),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Products', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          PermissionGuard(
            module: AdminModule.feedClients,
            permission: AdminPermission.create,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add product'),
              onPressed: () async {
                final created = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => AdminFeedProductFormScreen(fixedCompanyId: widget.clientId)),
                );
                if (created == true) {
                  _changed = true;
                  _load();
                }
              },
            ),
          ),
        ]),
        if (_products.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No products from this client yet.'),
          )
        else
          for (final p in _products)
            Card(
              child: ListTile(
                title: Text(p['product_name'] ?? ''),
                subtitle: Text('${p['bird_type']}/${p['feed_type']} · ৳${p['price']} · stock ${p['stock_quantity']} · ${p['approval_status']}'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () async {
                  final edited = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => AdminFeedProductFormScreen(productId: p['id'].toString())),
                  );
                  if (edited == true) {
                    _changed = true;
                    _load();
                  }
                },
              ),
            ),
      ]),
    );
  }

  List<Widget> _readOnlyDetails(Map<String, dynamic> client) => [
        _row('Contact person', client['contact_person']),
        _row('Phone', client['contact_phone']),
        _row('Email', client['contact_email']),
        _row('Address', client['address']),
        _row('District / Upazila', [client['district'], client['upazila']].where((v) => (v ?? '').toString().isNotEmpty).join(' / ')),
        if ((client['description'] ?? '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(client['description'], style: const TextStyle(color: Colors.black87)),
          ),
        _row('Products', '${client['product_count'] ?? 0}'),
        _row('Joined', (client['created_at'] ?? '').toString().split('T').first),
      ];

  Widget _row(String label, dynamic value) {
    final v = (value ?? '').toString();
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12))),
        Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
    );
  }

  List<Widget> _editForm() => [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Company name')),
        TextField(controller: _contactPerson, decoration: const InputDecoration(labelText: 'Contact person')),
        TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Contact phone')),
        TextField(controller: _email, decoration: const InputDecoration(labelText: 'Contact email')),
        TextField(controller: _address, decoration: const InputDecoration(labelText: 'Address')),
        Row(children: [
          Expanded(child: TextField(controller: _district, decoration: const InputDecoration(labelText: 'District'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _upazila, decoration: const InputDecoration(labelText: 'Upazila'))),
        ]),
        TextField(controller: _description, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(onPressed: _save, child: const Text('Save changes')),
        ),
      ];
}
