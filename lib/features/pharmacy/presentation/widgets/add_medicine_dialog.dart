import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/models/medicine_models.dart';
import '../../data/services/pharmacy_session.dart';
import '../pharmacy_theme.dart';

/// Add or edit a catalogue medicine. Pass [existing] to edit.
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
  late List<String> _images = List.of(widget.existing?.images ?? const []);

  String? _error;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    for (final c in [_name, _generic, _manufacturer, _price, _stock, _packSize,
      _batch, _description, _dosage, _storage, _expiry]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (!_isEdit) {
      showPharmacyNotice(context, 'Save the medicine first, then add photos.',
          PhColors.amber, Icons.info_outline);
      return;
    }
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = result?.files.firstOrNull;
    if (file?.bytes == null) return;
    setState(() => _busy = true);
    try {
      _images = await PharmacySession.instance
          .uploadMedicineImage(widget.existing!.id, file!.bytes!, file.name);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
    final body = {
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
    try {
      if (_isEdit) {
        await PharmacySession.instance.editMedicine(widget.existing!.id, body);
      } else {
        await PharmacySession.instance.addMedicine(body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
        Text(_isEdit ? 'Edit Medicine' : 'Add Medicine',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: PhColors.textPrimary)),
      ]),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
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
            const SizedBox(height: 8),
            _imageStrip(),
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
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: PhColors.secondary),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_isEdit ? 'Save' : 'Add Medicine'),
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
        dropdownColor: PhColors.bg,
        style: phFieldText,
        decoration: phInput(label, Icons.category_outlined),
        items: options
            .map((o) => DropdownMenuItem(value: o, child: Text(prettyCategory(o))))
            .toList(),
        onChanged: (v) => onChanged(v ?? value),
      );

  Widget _imageStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('Product photos', style: TextStyle(fontSize: 12, color: PhColors.textSecondary, fontWeight: FontWeight.w600)),
          const Spacer(),
          TextButton.icon(
            onPressed: _busy ? null : _pickImage,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
            label: const Text('Add', style: TextStyle(fontSize: 12)),
          ),
        ]),
        if (_images.isEmpty)
          const Text('Up to 5 images.', style: TextStyle(fontSize: 10.5, color: PhColors.grey))
        else
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(_images[i], width: 56, height: 56, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        width: 56, height: 56, color: PhColors.surface2,
                        child: const Icon(Icons.broken_image_outlined, size: 18, color: PhColors.grey))),
              ),
            ),
          ),
      ],
    );
  }
}
