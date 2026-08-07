import 'package:flutter/material.dart';
import '../../../../core/network/auth_service.dart';
import '../../../../core/theme/theme.dart';
import '../../data/pharmacy_marketplace_service.dart';

class FarmerPharmacyScreen extends StatefulWidget {
  const FarmerPharmacyScreen({super.key});
  @override
  State<FarmerPharmacyScreen> createState() => _FarmerPharmacyScreenState();
}

class _FarmerPharmacyScreenState extends State<FarmerPharmacyScreen> {
  List<MarketplaceMedicine> _medicines = [];
  bool _loading = true;
  String? _error;
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
      final rows = await PharmacyMarketplaceService.medicines();
      if (mounted) setState(() => _medicines = rows);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Pharmacy')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: _error != null
                    ? ListView(children: [
                        const SizedBox(height: 180),
                        Center(child: Text(_error!)),
                        Center(
                            child: TextButton(
                                onPressed: _load, child: const Text('Retry')))
                      ])
                    : _medicines.isEmpty
                        ? ListView(children: const [
                            SizedBox(height: 200),
                            Center(
                                child: Text('No approved medicines available.'))
                          ])
                        : ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            itemCount: _medicines.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (_, i) => _MedicineCard(
                                medicine: _medicines[i],
                                onOrder: () => _order(_medicines[i])),
                          ),
              ),
      );

  Future<void> _order(MarketplaceMedicine medicine) async {
    final quantity = TextEditingController(text: '1');
    final session = AuthService.instance.currentSession ??
        await AuthService.instance.getStoredSession();
    if (!mounted) return;
    final address =
        TextEditingController(text: session?.user.presentAddress ?? '');
    final notes = TextEditingController();
    final placed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(medicine.name),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: quantity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantity')),
                TextField(
                    controller: address,
                    decoration:
                        const InputDecoration(labelText: 'Delivery address')),
                TextField(
                    controller: notes,
                    decoration:
                        const InputDecoration(labelText: 'Order notes')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () async {
                      final count = int.tryParse(quantity.text) ?? 0;
                      if (count < 1 ||
                          count > medicine.stock ||
                          address.text.trim().isEmpty) return;
                      try {
                        await PharmacyMarketplaceService.order(medicine, count,
                            address.text.trim(), notes.text.trim());
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (e) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(content: Text(e.toString())));
                        }
                      }
                    },
                    child: const Text('Place Order'))
              ],
            ));
    quantity.dispose();
    address.dispose();
    notes.dispose();
    if (placed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Medicine order placed successfully.')));
      await _load();
    }
  }
}

class _MedicineCard extends StatelessWidget {
  final MarketplaceMedicine medicine;
  final VoidCallback onOrder;
  const _MedicineCard({required this.medicine, required this.onOrder});
  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(medicine.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700))),
            Text('৳${medicine.price.toStringAsFixed(0)}/${medicine.unit}',
                style: const TextStyle(
                    color: AppColors.secondary, fontWeight: FontWeight.w700))
          ]),
          const SizedBox(height: 4),
          Text(medicine.manufacturer,
              style: const TextStyle(color: AppColors.onSurfaceVariant)),
          Text(medicine.pharmacyName,
              style: const TextStyle(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 10),
          Row(children: [
            Text('${medicine.stock} available'),
            const Spacer(),
            ElevatedButton.icon(
                onPressed: onOrder,
                icon: const Icon(Icons.add_shopping_cart, size: 17),
                label: const Text('Order'))
          ]),
        ]),
      ));
}
