import 'package:flutter/material.dart';

import '../../../../core/widgets/catalogue_image_picker.dart';
import '../../../../core/widgets/error_state.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/admin_api_service.dart';
import '../admin_theme.dart';
import '../widgets/permission_guard.dart';

/// Add/edit a feed product. Used both from the Catalogue → Products list and
/// from a client's own "Add product" button (which pre-fills/locks the
/// company). This replaces the old 6-field AlertDialog — the previous
/// version had no image field at all and only a fraction of the model's
/// real fields (min_order_quantity, description, ingredients, nutrition
/// were silently never collected). See FEED_MARKETPLACE_UX_AUDIT.md.
///
/// Image upload needs a real product id (the endpoint is
/// `products/<id>/image/`), so a brand-new product is saved first (as
/// `pending_review`, same as before) and the screen then switches into
/// "edit" mode in place so photos can be attached immediately without
/// losing context or leaving the screen.
class AdminFeedProductFormScreen extends StatefulWidget {
  const AdminFeedProductFormScreen({super.key, this.productId, this.fixedCompanyId});

  /// Non-null when editing an existing product.
  final String? productId;

  /// Non-null when launched from a client's own page — locks the company
  /// picker to that client instead of offering a dropdown.
  final String? fixedCompanyId;

  @override
  State<AdminFeedProductFormScreen> createState() => _AdminFeedProductFormScreenState();
}

class _AdminFeedProductFormScreenState extends State<AdminFeedProductFormScreen> {
  final _api = AdminApiService.instance;
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _description = TextEditingController();
  final _ingredients = TextEditingController();
  final _protein = TextEditingController();
  final _energy = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  final _minQty = TextEditingController(text: '1');

  List<Map<String, dynamic>> _companies = [];
  String? _companyId;
  String _birdType = 'broiler';
  String _feedStage = 'starter';
  String _unit = 'bag_50kg';

  String? _productId;
  Map<String, dynamic>? _product;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _changed = false;

  static const _birdTypes = ['broiler', 'layer', 'chick', 'breeder', 'other'];
  static const _feedStages = ['starter', 'grower', 'finisher', 'layer', 'breeder', 'supplement', 'other'];
  static const _units = ['kg', 'bag_25kg', 'bag_50kg', 'ton', 'piece'];

  @override
  void initState() {
    super.initState();
    _productId = widget.productId;
    _companyId = widget.fixedCompanyId;
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _description.dispose();
    _ingredients.dispose();
    _protein.dispose();
    _energy.dispose();
    _price.dispose();
    _stock.dispose();
    _minQty.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final companies = await _api.feedCompanies();
      Map<String, dynamic>? product;
      if (_productId != null) {
        final list = await _api.feedProducts();
        product = list.firstWhere((p) => p['id'] == _productId, orElse: () => {});
        if (product.isEmpty) product = null;
      }
      if (!mounted) return;
      setState(() {
        _companies = companies;
        _companyId ??= companies.isNotEmpty ? companies.first['id'].toString() : null;
        if (product != null) {
          _product = product;
          _name.text = product['product_name'] ?? '';
          _brand.text = product['brand'] ?? '';
          _description.text = product['description'] ?? '';
          _ingredients.text = product['ingredients'] ?? '';
          _price.text = '${product['price'] ?? ''}';
          _stock.text = '${product['stock_quantity'] ?? ''}';
          _minQty.text = '${product['min_order_quantity'] ?? 1}';
          _birdType = product['bird_type'] ?? _birdType;
          _feedStage = product['feed_type'] ?? _feedStage;
          _unit = product['unit'] ?? _unit;
          _companyId = product['company_id']?.toString() ?? _companyId;
          final nutrition = (product['nutritional_info'] as Map?) ?? const {};
          _protein.text = nutrition['protein_percent']?.toString() ?? '';
          _energy.text = nutrition['energy_kcal_per_kg']?.toString() ?? '';
        }
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Map<String, dynamic> _payload() {
    final nutrition = <String, dynamic>{};
    if (_protein.text.trim().isNotEmpty) {
      nutrition['protein_percent'] = double.tryParse(_protein.text.trim());
    }
    if (_energy.text.trim().isNotEmpty) {
      nutrition['energy_kcal_per_kg'] = double.tryParse(_energy.text.trim());
    }
    return {
      'company_id': _companyId,
      'product_name': _name.text.trim(),
      'brand': _brand.text.trim(),
      'bird_type': _birdType,
      'feed_type': _feedStage,
      'unit': _unit,
      'description': _description.text.trim(),
      'ingredients': _ingredients.text.trim(),
      'nutritional_info': nutrition,
      'price': double.tryParse(_price.text.trim()) ?? 0,
      'stock_quantity': int.tryParse(_stock.text.trim()) ?? 0,
      'min_order_quantity': int.tryParse(_minQty.text.trim()) ?? 1,
    };
  }

  Future<void> _save() async {
    if (_companyId == null) {
      _toast('Add a feed client/company first.', AColors.red);
      return;
    }
    if (_formKey.currentState?.validate() != true) return;
    final price = double.tryParse(_price.text.trim());
    final stock = int.tryParse(_stock.text.trim());
    final minQty = int.tryParse(_minQty.text.trim());
    if (price == null || price < 0) {
      _toast('Price must be a non-negative number.', AColors.red);
      return;
    }
    if (stock == null || stock < 0) {
      _toast('Stock quantity must be a non-negative whole number.', AColors.red);
      return;
    }
    if (minQty == null || minQty < 1) {
      _toast('Minimum order quantity must be at least 1.', AColors.red);
      return;
    }
    setState(() => _saving = true);
    try {
      final payload = _payload();
      Map<String, dynamic> result;
      if (_productId == null) {
        result = await _api.createFeedProduct(payload);
      } else {
        result = await _api.updateFeedProduct(_productId!, payload);
      }
      if (!mounted) return;
      setState(() {
        _productId = result['id']?.toString() ?? _productId;
        _product = result;
        _saving = false;
        _changed = true;
      });
      _toast(widget.productId == null && _product != null && result['approval_status'] == 'pending_review'
          ? 'Product saved — add photos below, then it will wait for approval.'
          : 'Product saved', AColors.green);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _toast(ErrorStateView.humanize(e), AColors.red);
    }
  }

  Future<void> _productAction(String action) async {
    if (_productId == null) return;
    try {
      final updated = await _api.feedProductAction(_productId!, action);
      if (!mounted) return;
      setState(() {
        _product = updated;
        _changed = true;
      });
      _toast('Product ${{'approve': 'approved', 'reject': 'rejected', 'suspend': 'suspended'}[action] ?? action}', AColors.green);
    } catch (e) {
      _toast(ErrorStateView.humanize(e), AColors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AColors.appBar,
        foregroundColor: Colors.white,
        leading: BackButton(onPressed: () => Navigator.pop(context, _changed)),
        title: Text(_productId == null ? 'Add Feed Product' : 'Edit Feed Product',
            style: const TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorStateView(message: _error!, onRetry: _load)
              : Form(
                  key: _formKey,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    if (widget.fixedCompanyId == null)
                      DropdownButtonFormField<String>(
                        initialValue: _companyId,
                        decoration: const InputDecoration(labelText: 'Company / Client *'),
                        items: [for (final c in _companies) DropdownMenuItem(value: c['id'].toString(), child: Text(c['name']))],
                        onChanged: (v) => setState(() => _companyId = v),
                        validator: (v) => v == null ? 'Required' : null,
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text('Client: ${_companies.firstWhere((c) => c['id'] == widget.fixedCompanyId, orElse: () => {'name': '…'})['name']}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Product name *'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    TextFormField(controller: _brand, decoration: const InputDecoration(labelText: 'Brand (optional)')),
                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _birdType,
                          decoration: const InputDecoration(labelText: 'Bird type'),
                          items: [for (final v in _birdTypes) DropdownMenuItem(value: v, child: Text(v[0].toUpperCase() + v.substring(1)))],
                          onChanged: (v) => setState(() => _birdType = v ?? _birdType),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _feedStage,
                          decoration: const InputDecoration(labelText: 'Feed stage'),
                          items: [for (final v in _feedStages) DropdownMenuItem(value: v, child: Text(v[0].toUpperCase() + v.substring(1)))],
                          onChanged: (v) => setState(() => _feedStage = v ?? _feedStage),
                        ),
                      ),
                    ]),
                    TextFormField(controller: _description, maxLines: 3,
                        decoration: const InputDecoration(labelText: 'Description')),
                    TextFormField(controller: _ingredients, maxLines: 2,
                        decoration: const InputDecoration(labelText: 'Ingredients (optional)')),
                    Row(children: [
                      Expanded(
                        child: TextFormField(controller: _protein, keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Protein % (optional)')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(controller: _energy, keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Energy kcal/kg (optional)')),
                      ),
                    ]),
                    DropdownButtonFormField<String>(
                      initialValue: _unit,
                      decoration: const InputDecoration(labelText: 'Package size / unit'),
                      items: [for (final v in _units) DropdownMenuItem(value: v, child: Text(v.replaceAll('_', ' ').toUpperCase()))],
                      onChanged: (v) => setState(() => _unit = v ?? _unit),
                    ),
                    Row(children: [
                      Expanded(
                        child: TextFormField(
                          controller: _price, keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Price (৳) *'),
                          validator: (v) {
                            final n = double.tryParse((v ?? '').trim());
                            if (n == null || n < 0) return 'Non-negative number';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _stock, keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Stock quantity *'),
                          validator: (v) {
                            final n = int.tryParse((v ?? '').trim());
                            if (n == null || n < 0) return 'Non-negative whole number';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _minQty, keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Min order qty *'),
                          validator: (v) {
                            final n = int.tryParse((v ?? '').trim());
                            if (n == null || n < 1) return 'At least 1';
                            return null;
                          },
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_productId == null ? 'Save product' : 'Save changes'),
                      ),
                    ),
                    if (_productId != null) ...[
                      const SizedBox(height: 24),
                      const Text('Photos', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 8),
                      CatalogueImagePicker(
                        currentUrl: _product?['image_url'],
                        aspectRatio: 16 / 9,
                        label: 'Add primary photo',
                        onUpload: (bytes, filename) async {
                          final url = await _api.uploadFeedProductImage(_productId!, bytes, filename);
                          setState(() => _changed = true);
                          return url;
                        },
                      ),
                      const SizedBox(height: 8),
                      Text('Status: ${(_product?['approval_status'] ?? '').toString().toUpperCase()}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      PermissionGuard(
                        module: AdminModule.feedCatalogue,
                        permission: AdminPermission.approve,
                        child: Wrap(spacing: 8, children: [
                          if (_product?['approval_status'] != 'approved')
                            ElevatedButton(onPressed: () => _productAction('approve'), child: const Text('Approve')),
                          if (_product?['approval_status'] != 'rejected')
                            OutlinedButton(onPressed: () => _productAction('reject'), child: const Text('Reject')),
                          if (_product?['approval_status'] != 'suspended')
                            OutlinedButton(onPressed: () => _productAction('suspend'), child: const Text('Suspend')),
                        ]),
                      ),
                    ],
                  ]),
                ),
    );
  }
}
