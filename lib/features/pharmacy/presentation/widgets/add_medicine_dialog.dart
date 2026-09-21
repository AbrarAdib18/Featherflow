import 'package:flutter/material.dart';

import '../../../../core/widgets/catalogue_image_picker.dart';
import '../../data/models/medicine_models.dart';
import '../../data/services/pharmacy_session.dart';
import '../pharmacy_theme.dart';

/// Add or edit a catalogue medicine. Pass [existing] to edit.
///
/// Photo upload uses [CatalogueImagePicker] — the same proven widget already
/// used by the feed-marketplace admin's product form
/// (admin_feed_product_form_screen.dart) — instead of a bespoke picker, and
/// follows that screen's exact pattern for a brand-new item: the upload
/// endpoint needs a real medicine id, so a new medicine is saved first (text
/// fields only), and the dialog then reveals the photo section in place
/// without closing, so the pharmacist never has to close, find it in the
/// list, and reopen it just to attach a photo.
class AddMedicineDialog extends StatefulWidget {
  final Medicine? existing;
  const AddMedicineDialog({super.key, this.existing});

  @override
  State<AddMedicineDialog> createState() => _AddMedicineDialogState();
}

class _AddMedicineDialogState extends State<AddMedicineDialog> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _generic = TextEditingController(text: widget.existing?.genericName);
  late final _manufacturer = TextEditingController(text: widget.existing?.manufacturer);
  late final _price = TextEditingController(
      text: widget.existing != null ? widget.existing!.price.toStringAsFixed(0) : '');
  late final _stock = TextEditingController(
      text: widget.existing != null ? '${widget.existing!.stockQuantity}' : '0');
  late final _packSize = TextEditingController(text: widget.existing?.packSize);
  late final _batch = TextEditingController(text: widget.existing?.batchNumber);
  late final _description = TextEditingController(text: widget.existing?.description);
  late final _dosage = TextEditingController(text: widget.existing?.dosageInstructions);
  late final _storage = TextEditingController(text: widget.existing?.storageInstructions);
  late final _expiry = TextEditingController(
      text: (widget.existing?.expiryDate ?? DateTime.now().add(const Duration(days: 365)))
          .toIso8601String()
          .split('T')
          .first);

  late String _category = widget.existing?.category ?? 'antibiotic';
  late String _unit = widget.existing?.unit ?? 'bottle';
  late bool _prescription = widget.existing?.prescriptionRequired ?? false;
  late bool _coldChain = widget.existing?.coldChainRequired ?? false;

  // Non-null once the medicine has a real id — either because we opened in
  // edit mode, or because the create step below just made one. Only then can
  // CatalogueImagePicker actually upload (the endpoint is
  // medicines/<id>/upload-image/).
  String? _savedId;
  String? _photoUrl;
  bool _changed = false;

  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _savedId = widget.existing?.id;
    _photoUrl = widget.existing?.images.isNotEmpty == true ? widget.existing!.images.first : null;
  }

  @override
  void dispose() {
    for (final c in [_name, _generic, _manufacturer, _price, _stock, _packSize,
      _batch, _description, _dosage, _storage, _expiry]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _fieldPayload({required double price, required int stock}) => {
        'name': _name.text.trim(),
        'generic_name': _generic.text.trim(),
        'manufacturer': _manufacturer.text.trim(),
        'category': _category,
        'unit': _unit,
        'price': price,
        'stock_quantity': stock,
        'pack_size': _packSize.text.trim(),
        'batch_number': _batch.text.trim(),
        'description': _description.text.trim(),
        'dosage_instructions': _dosage.text.trim(),
        'storage_instructions': _storage.text.trim(),
        'prescription_required': _prescription,
        'cold_chain_required': _coldChain,
        'expiry_date': _expiry.text.trim(),
      };

  Future<void> _submit() async {
    final price = double.tryParse(_price.text.trim());
    final stock = int.tryParse(_stock.text.trim());
    final expiry = DateTime.tryParse(_expiry.text.trim());
    if (_name.text.trim().isEmpty) {
      return setState(() => _error = 'Medicine name is required.');
    }
    if (price == null || price <= 0) {
      return setState(() => _error = 'Price must be greater than 0.');
    }
    if (stock == null || stock < 0) {
      return setState(() => _error = 'Stock cannot be negative.');
    }
    if (expiry == null || !expiry.isAfter(DateTime.now())) {
      return setState(() => _error = 'Expiry date must be in the future.');
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final body = _fieldPayload(price: price, stock: stock);
    try {
      if (_savedId != null) {
        await PharmacySession.instance.editMedicine(_savedId!, body);
        if (mounted) Navigator.pop(context, true);
      } else {
        final created = await PharmacySession.instance.addMedicine(body);
        if (!mounted) return;
        setState(() {
          _savedId = created.id;
          _changed = true;
          _busy = false;
        });
        showPharmacyNotice(context, 'Medicine saved — add a photo below, then tap Done.',
            PhColors.green, Icons.check_circle_outline);
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final justCreated = _savedId != null && widget.existing == null;
    return AlertDialog(
      backgroundColor: PhColors.bg,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: PhColors.cardBorder)),
      title: Row(children: [
        const CircleAvatar(
          radius: 18,
          backgroundColor: PhColors.medicinesLight,
          child: Icon(Icons.medication_outlined, color: PhColors.medicines, size: 19),
        ),
        const SizedBox(width: 12),
        Text(widget.existing != null ? 'Edit Medicine' : 'Add Medicine',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: PhColors.textPrimary)),
      ]),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Product photo',
                  style: TextStyle(fontSize: 12, color: PhColors.textSecondary, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 6),
            if (_savedId == null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                    color: PhColors.surface2, borderRadius: BorderRadius.circular(10)),
                child: const Center(
                  child: Text('Save the medicine to add a photo.',
                      style: TextStyle(fontSize: 11.5, color: PhColors.grey)),
                ),
              )
            else
              SizedBox(
                width: 220,
                child: CatalogueImagePicker(
                  currentUrl: _photoUrl,
                  aspectRatio: 4 / 3,
                  label: 'Add product photo',
                  fallbackIcon: Icons.medication_outlined,
                  onUpload: (bytes, filename) async {
                    final url = await PharmacySession.instance
                        .uploadPrimaryMedicineImage(_savedId!, bytes, filename);
                    if (mounted) setState(() => _changed = true);
                    return url;
                  },
                ),
              ),
            if (justCreated) ...[
              const SizedBox(height: 4),
              const Text('Medicine saved. Add a photo, then tap Done.',
                  style: TextStyle(fontSize: 10.5, color: PhColors.secondary, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 14),
            _field(_name, 'Medicine name', Icons.medication_outlined),
            _gap,
            _field(_generic, 'Generic name (optional)', Icons.science_outlined),
            _gap,
            _field(_manufacturer, 'Manufacturer', Icons.factory_outlined),
            _gap,
            Row(children: [
              Expanded(child: _dropdown('Category', _category, kMedicineCategories,
                  (v) => setState(() => _category = v))),
              const SizedBox(width: 10),
              Expanded(child: _dropdown('Unit', _unit, kMedicineUnits,
                  (v) => setState(() => _unit = v))),
            ]),
            _gap,
            Row(children: [
              Expanded(child: _field(_price, 'Price (৳)', Icons.payments_outlined, number: true)),
              const SizedBox(width: 10),
              Expanded(child: _field(_stock, 'Stock', Icons.inventory_2_outlined, number: true)),
            ]),
            _gap,
            _field(_packSize, 'Pack size (e.g. 10 tablets)', Icons.inventory_outlined),
            _gap,
            _field(_batch, 'Batch number (optional)', Icons.qr_code_2_outlined),
            _gap,
            _field(_expiry, 'Expiry date (YYYY-MM-DD)', Icons.event_outlined),
            _gap,
            _field(_description, 'Description', Icons.notes_outlined, lines: 2),
            _gap,
            _field(_dosage, 'Dosage instructions', Icons.info_outline, lines: 2),
            _gap,
            _field(_storage, 'Storage instructions', Icons.ac_unit_outlined, lines: 2),
            _gap,
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _prescription,
              activeThumbColor: PhColors.secondary,
              title: const Text('Prescription required', style: phFieldText),
              subtitle: const Text('Needs admin approval before farmers can order',
                  style: TextStyle(fontSize: 10.5, color: PhColors.grey)),
              onChanged: (v) => setState(() => _prescription = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _coldChain,
              activeThumbColor: PhColors.secondary,
              title: const Text('Cold chain required', style: phFieldText),
              subtitle: const Text('Rider is flagged to use an insulated bag',
                  style: TextStyle(fontSize: 10.5, color: PhColors.grey)),
              onChanged: (v) => setState(() => _coldChain = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.error_outline, color: PhColors.red, size: 15),
                const SizedBox(width: 6),
                Expanded(child: Text(_error!, style: const TextStyle(color: PhColors.red, fontSize: 11.5))),
              ]),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, _changed),
          child: Text(justCreated ? 'Done' : 'Cancel'),
        ),
        if (!justCreated)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PhColors.secondary),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(widget.existing != null ? 'Save' : 'Add Medicine'),
          ),
      ],
    );
  }

  Widget get _gap => const SizedBox(height: 10);

  Widget _field(TextEditingController c, String label, IconData icon,
          {bool number = false, int lines = 1}) =>
      TextField(
        controller: c,
        style: phFieldText,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        minLines: lines,
        maxLines: lines,
        decoration: phInput(label, icon),
      );

  Widget _dropdown(String label, String value, List<String> options, ValueChanged<String> onChanged) =>
      DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true, // fills its Expanded slot instead of sizing to the
        // widest item's intrinsic width — without this, a long category name
        // like "Feed supplement" overflows the half-width Row slot.
        dropdownColor: PhColors.bg,
        style: phFieldText,
        decoration: phInput(label, Icons.category_outlined),
        items: options
            .map((o) => DropdownMenuItem(
                value: o, child: Text(prettyCategory(o), overflow: TextOverflow.ellipsis)))
            .toList(),
        onChanged: (v) => onChanged(v ?? value),
      );
}
