import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/medicine_models.dart';
import '../../data/services/pharmacy_session.dart';
import '../pharmacy_theme.dart';

class PharmacySuppliersScreen extends StatefulWidget {
  const PharmacySuppliersScreen({super.key});

  @override
  State<PharmacySuppliersScreen> createState() => _PharmacySuppliersScreenState();
}

class _PharmacySuppliersScreenState extends State<PharmacySuppliersScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PharmacySession.instance,
      builder: (context, _) {
        final s = PharmacySession.instance;
        var suppliers = s.suppliers.where((x) => x.isActive).toList();
        if (_query.isNotEmpty) {
          final q = _query.toLowerCase();
          suppliers = suppliers
              .where((x) =>
                  x.supplierName.toLowerCase().contains(q) ||
                  x.productsSupplied.toLowerCase().contains(q))
              .toList();
        }
        return Scaffold(
          backgroundColor: PhColors.bg,
          appBar: AppBar(
            backgroundColor: PhColors.appBar,
            foregroundColor: Colors.white,
            automaticallyImplyLeading: false,
            title: const Text('Suppliers',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            actions: [
              TextButton.icon(
                onPressed: () => _edit(context, null),
                icon: const Icon(Icons.add, color: PhColors.secondary, size: 18),
                label: const Text('Add',
                    style: TextStyle(color: PhColors.secondary, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ],
          ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search suppliers or products…',
                  hintStyle: const TextStyle(color: PhColors.grey, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: PhColors.grey, size: 20),
                  filled: true,
                  fillColor: PhColors.surface2,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ),
            Expanded(
              child: suppliers.isEmpty
                  ? Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.local_shipping_outlined, size: 48, color: PhColors.grey.withValues(alpha: .4)),
                        const SizedBox(height: 12),
                        const Text('No suppliers yet',
                            style: TextStyle(fontSize: 14, color: PhColors.textSecondary)),
                        const SizedBox(height: 4),
                        const Text('Add the wholesalers you restock from.',
                            style: TextStyle(fontSize: 12, color: PhColors.grey)),
                      ]),
                    )
                  : RefreshIndicator(
                      onRefresh: s.refresh,
                      color: PhColors.secondary,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: suppliers.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _SupplierCard(
                            supplier: suppliers[i],
                            onEdit: () => _edit(context, suppliers[i]),
                            onDelete: () => _delete(context, suppliers[i]),
                          ),
                        ),
                      ),
                    ),
            ),
          ]),
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, Supplier? existing) async {
    final name = TextEditingController(text: existing?.supplierName);
    final contact = TextEditingController(text: existing?.contactPerson);
    final phone = TextEditingController(text: existing?.phone);
    final email = TextEditingController(text: existing?.email);
    final address = TextEditingController(text: existing?.address);
    final products = TextEditingController(text: existing?.productsSupplied);
    final terms = TextEditingController(text: existing?.paymentTerms);
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          backgroundColor: PhColors.bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(existing == null ? 'Add supplier' : 'Edit supplier',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _f(name, 'Supplier name', Icons.business_outlined),
                _f(contact, 'Contact person', Icons.person_outline),
                _f(phone, 'Phone', Icons.phone_outlined),
                _f(email, 'Email', Icons.email_outlined),
                _f(address, 'Address', Icons.place_outlined, lines: 2),
                _f(products, 'Products supplied (comma separated)', Icons.inventory_2_outlined, lines: 2),
                _f(terms, 'Payment terms (optional)', Icons.payments_outlined),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: PhColors.red, fontSize: 11.5)),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: PhColors.secondary),
              onPressed: () async {
                if (name.text.trim().isEmpty) {
                  setLocal(() => error = 'Supplier name is required.');
                  return;
                }
                final body = {
                  'supplier_name': name.text.trim(),
                  'contact_person': contact.text.trim(),
                  'phone': phone.text.trim(),
                  'email': email.text.trim(),
                  'address': address.text.trim(),
                  'products_supplied': products.text.trim(),
                  'payment_terms': terms.text.trim(),
                };
                try {
                  if (existing == null) {
                    await PharmacySession.instance.addSupplier(body);
                  } else {
                    await PharmacySession.instance.editSupplier(existing.id, body);
                  }
                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  setLocal(() => error = e.toString());
                }
              },
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
    for (final c in [name, contact, phone, email, address, products, terms]) {
      c.dispose();
    }
    if (ok == true && context.mounted) {
      showPharmacyNotice(context, 'Supplier saved.', PhColors.green, Icons.check_circle_outline);
    }
  }

  Future<void> _delete(BuildContext context, Supplier s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: PhColors.bg,
        title: const Text('Remove supplier?'),
        content: Text('${s.supplierName} will be archived.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove', style: TextStyle(color: PhColors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await PharmacySession.instance.deleteSupplier(s.id);
  }

  Widget _f(TextEditingController c, String label, IconData icon, {int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          style: phFieldText,
          minLines: lines,
          maxLines: lines,
          decoration: phInput(label, icon),
        ),
      );
}

class _SupplierCard extends StatelessWidget {
  final Supplier supplier;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _SupplierCard({required this.supplier, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: phCard(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CircleAvatar(radius: 15, backgroundColor: PhColors.medicinesLight,
              child: Icon(Icons.business, size: 15, color: PhColors.medicines)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(supplier.supplierName,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: PhColors.textPrimary)),
              if (supplier.contactPerson.isNotEmpty)
                Text(supplier.contactPerson,
                    style: const TextStyle(fontSize: 11.5, color: PhColors.textSecondary)),
            ]),
          ),
          IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 17, color: PhColors.grey), visualDensity: VisualDensity.compact),
          IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline, size: 17, color: PhColors.grey), visualDensity: VisualDensity.compact),
        ]),
        if (supplier.productsSupplied.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(supplier.productsSupplied,
              style: const TextStyle(fontSize: 11.5, color: PhColors.textSecondary, height: 1.4)),
        ],
        if (supplier.paymentTerms.isNotEmpty) ...[
          const SizedBox(height: 6),
          phChip(supplier.paymentTerms, PhColors.surface2, PhColors.textSecondary, fontSize: 10),
        ],
        const SizedBox(height: 8),
        Row(children: [
          if (supplier.phone.isNotEmpty)
            _mini(Icons.call, 'Call', () => launchUrl(Uri.parse('tel:${supplier.phone}'))),
          if (supplier.email.isNotEmpty) ...[
            const SizedBox(width: 8),
            _mini(Icons.email_outlined, 'Email', () => launchUrl(Uri.parse('mailto:${supplier.email}'))),
          ],
        ]),
      ]),
    );
  }

  Widget _mini(IconData icon, String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: PhColors.secondary.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: PhColors.secondary.withValues(alpha: .3))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: PhColors.secondary),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: PhColors.secondary, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}
