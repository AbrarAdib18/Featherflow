import 'package:flutter/material.dart';
import '../../data/models/pharmacy_models.dart';
import '../../data/services/pharmacy_session.dart';
import '../pharmacy_theme.dart';

class AddMedicineDialog extends StatefulWidget {
  const AddMedicineDialog({super.key});
  @override
  State<AddMedicineDialog> createState() => _AddMedicineDialogState();
}

class _AddMedicineDialogState extends State<AddMedicineDialog> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(),
      manufacturer = TextEditingController(),
      price = TextEditingController(),
      description = TextEditingController();
  final stock = TextEditingController(text: '0'),
      minimum = TextEditingController(text: '5'),
      unit = TextEditingController(text: 'bottle');
  ProductCategory category = ProductCategory.medicines;
  DateTime expiry = DateTime.now().add(const Duration(days: 365));
  bool saving = false;
  String? error;

  @override
  void dispose() {
    for (final c in [
      name,
      manufacturer,
      price,
      description,
      stock,
      minimum,
      unit
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 680;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          EdgeInsets.symmetric(horizontal: compact ? 14 : 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Material(
            color: PhColors.bg,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _header(context),
              Flexible(
                  child: SingleChildScrollView(
                padding: EdgeInsets.all(compact ? 18 : 24),
                child: Form(
                    key: formKey,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _Section(
                              Icons.category_outlined,
                              'Medicine category',
                              'Choose how this inventory item is classified'),
                          const SizedBox(height: 12),
                          Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: ProductCategory.values
                                  .map((c) => _CategoryTile(
                                      category: c,
                                      selected: category == c,
                                      onTap: () =>
                                          setState(() => category = c)))
                                  .toList()),
                          const SizedBox(height: 24),
                          const _Section(
                              Icons.medication_outlined,
                              'Medicine details',
                              'Basic listing and supplier information'),
                          const SizedBox(height: 12),
                          _fields(compact, [
                            _input(name, 'Medicine name',
                                Icons.medication_outlined),
                            _input(manufacturer, 'Manufacturer',
                                Icons.factory_outlined)
                          ]),
                          const SizedBox(height: 12),
                          _fields(compact, [
                            _input(unit, 'Selling unit',
                                Icons.straighten_outlined),
                            InkWell(
                                onTap: _pickDate,
                                borderRadius: BorderRadius.circular(10),
                                child: InputDecorator(
                                    decoration: phInput(
                                        'Expiry date', Icons.event_outlined),
                                    child: Text(_date(expiry),
                                        style: phFieldText)))
                          ]),
                          const SizedBox(height: 24),
                          const _Section(
                              Icons.inventory_2_outlined,
                              'Pricing & stock',
                              'Set availability and the low-stock warning level'),
                          const SizedBox(height: 12),
                          _fields(compact, [
                            _input(price, 'Unit price (৳)',
                                Icons.payments_outlined,
                                number: true),
                            _input(
                                stock, 'Opening stock', Icons.add_box_outlined,
                                number: true),
                            _input(minimum, 'Low-stock level',
                                Icons.warning_amber_outlined,
                                number: true)
                          ]),
                          const SizedBox(height: 12),
                          TextFormField(
                              controller: description,
                              style: phFieldText,
                              minLines: 2,
                              maxLines: 3,
                              decoration: phInput(
                                  'Description or dosage notes (optional)',
                                  Icons.notes_outlined)),
                          if (error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                    color: PhColors.outOfStockLight,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: PhColors.red
                                            .withValues(alpha: .25))),
                                child: Row(children: [
                                  const Icon(Icons.error_outline,
                                      color: PhColors.red, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(error!,
                                          style: const TextStyle(
                                              color: PhColors.red,
                                              fontSize: 12)))
                                ]))
                          ],
                        ])),
              )),
              _footer(context),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [PhColors.primary, Color(0xFF075640)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)),
        child: Row(children: [
          Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24)),
              child: const Icon(Icons.add_business_outlined,
                  color: Colors.white, size: 23)),
          const SizedBox(width: 13),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Add New Medicine',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800)),
                SizedBox(height: 3),
                Text('Create an inventory listing for administrator approval',
                    style: TextStyle(color: Colors.white70, fontSize: 11.5))
              ])),
          IconButton(
              tooltip: 'Close',
              onPressed: saving ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white70)),
        ]),
      );

  Widget _footer(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
        decoration: const BoxDecoration(
            color: PhColors.surface2,
            border: Border(top: BorderSide(color: PhColors.cardBorder))),
        child: Row(children: [
          const Icon(Icons.verified_user_outlined,
              color: PhColors.grey, size: 17),
          const SizedBox(width: 7),
          const Expanded(
              child: Text('New listings require admin approval',
                  style:
                      TextStyle(color: PhColors.textSecondary, fontSize: 11))),
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          const SizedBox(width: 8),
          FilledButton.icon(
              onPressed: saving ? null : _submit,
              style: FilledButton.styleFrom(
                  backgroundColor: PhColors.secondary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add, size: 18),
              label: Text(saving ? 'Adding…' : 'Add Medicine',
                  style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );

  Widget _input(TextEditingController c, String label, IconData icon,
          {bool number = false}) =>
      TextFormField(
          controller: c,
          style: phFieldText,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          decoration: phInput(label, icon),
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null);

  Widget _fields(bool compact, List<Widget> widgets) {
    if (compact)
      return Column(children: _separate(widgets, const SizedBox(height: 12)));
    return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _separate(widgets.map((w) => Expanded(child: w)).toList(),
            const SizedBox(width: 12)));
  }

  List<Widget> _separate(List<Widget> widgets, Widget gap) {
    final result = <Widget>[];
    for (var i = 0; i < widgets.length; i++) {
      if (i > 0) result.add(gap);
      result.add(widgets[i]);
    }
    return result;
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
        context: context,
        initialDate: expiry,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 3650)));
    if (value != null && mounted) setState(() => expiry = value);
  }

  Future<void> _submit() async {
    if (!formKey.currentState!.validate()) return;
    final parsedPrice = double.tryParse(price.text),
        parsedStock = int.tryParse(stock.text),
        parsedMinimum = int.tryParse(minimum.text);
    if (parsedPrice == null ||
        parsedPrice <= 0 ||
        parsedStock == null ||
        parsedStock < 0 ||
        parsedMinimum == null ||
        parsedMinimum < 0) {
      setState(
          () => error = 'Enter a valid price and non-negative stock values.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await PharmacySession.instance.addProduct(PharmacyProduct(
          id: 'PRD-${DateTime.now().millisecondsSinceEpoch}',
          name: name.text.trim(),
          category: category,
          stockCount: parsedStock,
          minStock: parsedMinimum,
          unit: unit.text.trim(),
          price: parsedPrice,
          manufacturer: manufacturer.text.trim(),
          expiryDate: expiry,
          description: description.text.trim().isEmpty
              ? null
              : description.text.trim()));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String _date(DateTime d) {
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const _Section(this.icon, this.title, this.subtitle);
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: PhColors.inStockLight,
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: PhColors.secondary, size: 17)),
        const SizedBox(width: 9),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: PhColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          Text(subtitle,
              style: const TextStyle(
                  color: PhColors.textSecondary, fontSize: 10.5))
        ])
      ]);
}

class _CategoryTile extends StatelessWidget {
  final ProductCategory category;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryTile(
      {required this.category, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final v = switch (category) {
      ProductCategory.medicines => (
          'Medicine',
          Icons.medication_outlined,
          PhColors.medicines
        ),
      ProductCategory.vaccines => (
          'Vaccine',
          Icons.vaccines_outlined,
          PhColors.vaccines
        ),
      ProductCategory.supplements => (
          'Supplement',
          Icons.science_outlined,
          PhColors.supplements
        ),
      ProductCategory.equipment => (
          'Equipment',
          Icons.medical_services_outlined,
          PhColors.equipment
        )
    };
    return Material(
        color: selected ? v.$3.withValues(alpha: .09) : PhColors.surface2,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
            onTap: onTap,
            hoverColor: v.$3.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 150,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: selected ? v.$3 : PhColors.cardBorder,
                        width: selected ? 1.5 : 1)),
                child: Row(children: [
                  Icon(v.$2, color: v.$3, size: 19),
                  const SizedBox(width: 8),
                  Text(v.$1,
                      style: TextStyle(
                          color: selected ? v.$3 : PhColors.textSecondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700))
                ]))));
  }
}
