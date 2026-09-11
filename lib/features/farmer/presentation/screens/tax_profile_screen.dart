import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';
import '../../data/tax_api_service.dart';
import '../../data/models/tax_profile.dart';

/// Farmer enters the details that drive the tax estimate: land, vehicles,
/// income type, exemptions.
class TaxProfileScreen extends StatefulWidget {
  const TaxProfileScreen({super.key});

  @override
  State<TaxProfileScreen> createState() => _TaxProfileScreenState();
}

class _TaxProfileScreenState extends State<TaxProfileScreen> {
  final _landArea = TextEditingController();
  final _exemptions = TextEditingController();
  final _rebates = TextEditingController();
  final _district = TextEditingController();
  final _upazila = TextEditingController();

  String _landUnit = 'katha';
  String _landUse = 'agricultural';
  String _location = 'rural';
  String _incomeType = 'agricultural';
  bool _isSenior = false;
  List<TaxVehicle> _vehicles = [];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_landArea, _exemptions, _rebates, _district, _upazila]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await TaxApiService.getTaxProfile();
      if (!mounted) return;
      setState(() {
        _landArea.text = p.landArea > 0 ? _trim(p.landArea) : '';
        _exemptions.text = p.exemptions > 0 ? _trim(p.exemptions) : '';
        _rebates.text = p.rebates > 0 ? _trim(p.rebates) : '';
        _district.text = p.district;
        _upazila.text = p.upazila;
        _landUnit = p.landUnit;
        _landUse = p.landUse;
        _location = p.location;
        _incomeType = p.incomeType;
        _isSenior = p.isSenior;
        _vehicles = List.of(p.vehicles);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await TaxApiService.updateTaxProfile({
        'land_area': double.tryParse(_landArea.text.trim()) ?? 0,
        'land_unit': _landUnit,
        'land_use': _landUse,
        'location': _location,
        'income_type': _incomeType,
        'exemptions': double.tryParse(_exemptions.text.trim()) ?? 0,
        'rebates': double.tryParse(_rebates.text.trim()) ?? 0,
        'is_senior': _isSenior,
        'district': _district.text.trim(),
        'upazila': _upazila.text.trim(),
        'vehicles': _vehicles.map((v) => v.toJson()).toList(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Tax details saved')));
      context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _addVehicle() async {
    final added = await showModalBottomSheet<TaxVehicle>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _VehicleSheet(),
    );
    if (added != null) setState(() => _vehicles.add(added));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.canPop() ? context.pop() : context.go('/farmer/tax')),
        title: const Text('My tax details',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(48)),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save'),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                _section('Income'),
                _dropdown('Income type', _incomeType, TaxProfile.incomeTypes, {
                  'agricultural': 'Agricultural (farming)',
                  'business': 'Business / trading',
                  'mixed': 'Mixed',
                }, (v) => setState(() => _incomeType = v)),
                const SizedBox(height: 12),
                _numField(_exemptions, 'Other exemptions / deductions (BDT)'),
                const SizedBox(height: 12),
                _numField(_rebates, 'Investment tax rebate (BDT)'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isSenior,
                  onChanged: (v) => setState(() => _isSenior = v),
                  title: const Text('65 or older', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Higher tax-free limit (BDT 400,000)',
                      style: TextStyle(fontSize: 11.5)),
                ),
                const SizedBox(height: 16),
                _section('Land'),
                Row(children: [
                  Expanded(flex: 2, child: _numField(_landArea, 'Land area')),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _dropdown('Unit', _landUnit, TaxProfile.landUnits,
                        {for (final u in TaxProfile.landUnits) u: _cap(u)},
                        (v) => setState(() => _landUnit = v)),
                  ),
                ]),
                const SizedBox(height: 12),
                _dropdown('Land use', _landUse, TaxProfile.landUses,
                    {for (final u in TaxProfile.landUses) u: _cap(u)},
                    (v) => setState(() => _landUse = v)),
                const SizedBox(height: 12),
                _dropdown('Area type', _location, TaxProfile.locations, {
                  'rural': 'Rural (union)',
                  'urban': 'Urban (municipal / city)',
                }, (v) => setState(() => _location = v)),
                if (_landUse == 'agricultural')
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('First 25 bighas of farm land is tax-free.',
                        style: TextStyle(fontSize: 11, color: AppColors.secondary)),
                  ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _textField(_district, 'District (optional)')),
                  const SizedBox(width: 10),
                  Expanded(child: _textField(_upazila, 'Upazila (optional)')),
                ]),
                const SizedBox(height: 16),
                _section('Vehicles'),
                for (int i = 0; i < _vehicles.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.directions_car_outlined),
                    title: Text('${_vehicles[i].count} x ${_vehicles[i].label}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.error),
                      onPressed: () => setState(() => _vehicles.removeAt(i)),
                    ),
                  ),
                TextButton.icon(
                  onPressed: _addVehicle,
                  icon: const Icon(Icons.add),
                  label: const Text('Add a vehicle'),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Power tillers and tractors are tax-free.',
                      style: TextStyle(fontSize: 11, color: AppColors.secondary)),
                ),
              ],
            ),
    );
  }

  static String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: Colors.black87, fontSize: 15)),
      );

  Widget _numField(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(
            labelText: label, isDense: true, border: const OutlineInputBorder()),
      );

  Widget _textField(TextEditingController c, String label) => TextField(
        controller: c,
        decoration: InputDecoration(
            labelText: label, isDense: true, border: const OutlineInputBorder()),
      );

  Widget _dropdown(String label, String value, List<String> options,
          Map<String, String> labels, ValueChanged<String> onChanged) =>
      DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: label, isDense: true, border: const OutlineInputBorder()),
        items: [
          for (final o in options)
            DropdownMenuItem(value: o, child: Text(labels[o] ?? o)),
        ],
        onChanged: (v) => v == null ? null : onChanged(v),
      );
}

class _VehicleSheet extends StatefulWidget {
  const _VehicleSheet();

  @override
  State<_VehicleSheet> createState() => _VehicleSheetState();
}

class _VehicleSheetState extends State<_VehicleSheet> {
  String _type = 'motorcycle';
  int _count = 1;

  static const _labels = {
    'motorcycle': 'Motorcycle',
    'power_tiller': 'Power tiller (tax-free)',
    'tractor': 'Tractor (tax-free)',
    'cng_autorickshaw': 'CNG / auto-rickshaw',
    'pickup': 'Pickup',
    'van': 'Van',
    'car_upto_1500cc': 'Car up to 1500cc',
    'car_1501_2000cc': 'Car 1501-2000cc',
    'car_2001_2500cc': 'Car 2001-2500cc',
    'car_above_2500cc': 'Car above 2500cc',
    'microbus': 'Microbus',
    'jeep': 'Jeep',
    'truck': 'Truck',
    'bus': 'Bus',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Add a vehicle',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _type,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Type', isDense: true, border: OutlineInputBorder()),
          items: [
            for (final e in _labels.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() => _type = v ?? _type),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Text('How many? '),
          IconButton(
              onPressed: () => setState(() => _count = (_count - 1).clamp(1, 99)),
              icon: const Icon(Icons.remove_circle_outline)),
          Text('$_count', style: const TextStyle(fontWeight: FontWeight.w700)),
          IconButton(
              onPressed: () => setState(() => _count = (_count + 1).clamp(1, 99)),
              icon: const Icon(Icons.add_circle_outline)),
        ]),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary, minimumSize: const Size.fromHeight(46)),
          onPressed: () => Navigator.pop(context, TaxVehicle(_type, _count)),
          child: const Text('Add'),
        ),
      ]),
    );
  }
}
