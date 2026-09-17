import 'package:flutter/material.dart';

import '../../../../core/widgets/catalogue_image.dart';
import '../../../../core/widgets/error_state.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/admin_api_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/permission_guard.dart';
import 'admin_feed_client_detail_screen.dart';

/// Feed Admin → Clients (feed companies/brands working with FeatherFlow).
///
/// "Client" here always means a `FeedCompany` row — a supplier brand, never
/// a farmer. Farmers place orders as customers and never appear in this
/// screen; see FEED_MARKETPLACE_UX_AUDIT.md for why this distinction needed
/// stating explicitly (the existing code used "company"/"supplier" in
/// different places for the same model).
class AdminFeedClientsScreen extends StatefulWidget {
  const AdminFeedClientsScreen({super.key});

  @override
  State<AdminFeedClientsScreen> createState() => _AdminFeedClientsScreenState();
}

class _AdminFeedClientsScreenState extends State<AdminFeedClientsScreen> {
  final _api = AdminApiService.instance;
  final _search = TextEditingController();
  List<Map<String, dynamic>> _clients = [];
  bool _loading = true;
  String? _error;
  String? _statusFilter;

  static const _statuses = [null, 'pending', 'active', 'suspended', 'rejected'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final filters = <String, String>{
        if (_statusFilter != null) 'status': _statusFilter!,
        if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
      };
      final clients = await _api.feedCompanies(filters: filters);
      if (!mounted) return;
      setState(() {
        _clients = clients;
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

  Future<void> _addClient() async {
    final name = TextEditingController();
    final contactPerson = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final address = TextEditingController();
    final district = TextEditingController();
    final upazila = TextEditingController();
    final description = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add feed client'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Company name *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                TextFormField(controller: contactPerson,
                    decoration: const InputDecoration(labelText: 'Contact person')),
                TextFormField(controller: phone,
                    decoration: const InputDecoration(labelText: 'Contact phone')),
                TextFormField(controller: email,
                    decoration: const InputDecoration(labelText: 'Contact email')),
                TextFormField(controller: address,
                    decoration: const InputDecoration(labelText: 'Address')),
                Row(children: [
                  Expanded(
                      child: TextFormField(controller: district,
                          decoration: const InputDecoration(labelText: 'District'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextFormField(controller: upazila,
                          decoration: const InputDecoration(labelText: 'Upazila'))),
                ]),
                TextFormField(controller: description, maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Description')),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) Navigator.pop(ctx, true);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.createFeedCompany({
        'name': name.text.trim(), 'contact_person': contactPerson.text.trim(),
        'contact_phone': phone.text.trim(), 'contact_email': email.text.trim(),
        'address': address.text.trim(), 'district': district.text.trim(),
        'upazila': upazila.text.trim(), 'description': description.text.trim(),
      });
      await _load();
      _toast('Client added', AColors.green);
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
    return AdminScaffold(
      title: 'Clients',
      module: AdminModule.feedClients,
      appBarActions: [
        PermissionGuard(
          module: AdminModule.feedClients,
          permission: AdminPermission.create,
          child: IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add client',
            onPressed: _addClient,
          ),
        ),
      ],
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search clients…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              suffixIcon: _search.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        _load();
                      })
                  : null,
            ),
            onSubmitted: (_) => _load(),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final s in _statuses)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s == null ? 'All' : s[0].toUpperCase() + s.substring(1)),
                    selected: _statusFilter == s,
                    onSelected: (_) {
                      setState(() => _statusFilter = s);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorStateView(message: _error!, onRetry: _load)
                  : _clients.isEmpty
                      ? const Center(child: Text('No clients yet. Add one to get started.'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 340, mainAxisExtent: 168,
                                mainAxisSpacing: 10, crossAxisSpacing: 10),
                            itemCount: _clients.length,
                            itemBuilder: (context, i) {
                              final c = _clients[i];
                              final status = c['status']?.toString() ?? 'active';
                              return Card(
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () async {
                                    final changed = await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => AdminFeedClientDetailScreen(clientId: c['id'].toString())),
                                    );
                                    if (changed == true) _load();
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      SizedBox(
                                        width: 56, height: 56,
                                        child: CatalogueImage(
                                            url: c['logo_url'], fallbackIcon: Icons.storefront,
                                            borderRadius: BorderRadius.circular(8)),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(c['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                          if ((c['contact_person'] ?? '').toString().isNotEmpty)
                                            Text(c['contact_person'], style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                          if ((c['contact_phone'] ?? '').toString().isNotEmpty)
                                            Text(c['contact_phone'], style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                          const SizedBox(height: 6),
                                          Wrap(spacing: 6, runSpacing: 4, children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                  color: _statusColor(status).withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(20)),
                                              child: Text(status.toUpperCase(),
                                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _statusColor(status))),
                                            ),
                                            Text('${c['product_count'] ?? 0} products',
                                                style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                          ]),
                                        ]),
                                      ),
                                    ]),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}
