import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/core/widgets/error_state.dart';
import '../../data/flock_service.dart';

/// Flock list + age-based feeding chart (Priority 4). Reached from
/// Feed Management -> "Flocks & feeding age chart". Guidance shown here is
/// always general reference data, never a flock-specific veterinary/
/// nutritional recommendation (see backend/feed/models.py::FeedingGuideline).
class FlockAgeChartScreen extends StatefulWidget {
  const FlockAgeChartScreen({super.key});

  @override
  State<FlockAgeChartScreen> createState() => _FlockAgeChartScreenState();
}

class _FlockAgeChartScreenState extends State<FlockAgeChartScreen> {
  List<Map<String, dynamic>>? _flocks;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final flocks = await FlockService.list();
      if (mounted) {
        setState(() {
          _flocks = flocks;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ErrorStateView.humanize(e));
    }
  }

  Future<void> _addFlock() async {
    final batchCtrl = TextEditingController();
    final breedCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    String birdType = 'broiler';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add flock / batch'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: batchCtrl, decoration: const InputDecoration(labelText: 'Batch name')),
              DropdownButtonFormField<String>(
                initialValue: birdType,
                decoration: const InputDecoration(labelText: 'Bird type'),
                items: const [
                  DropdownMenuItem(value: 'broiler', child: Text('Broiler')),
                  DropdownMenuItem(value: 'layer', child: Text('Layer')),
                  DropdownMenuItem(value: 'chick', child: Text('Chick')),
                  DropdownMenuItem(value: 'breeder', child: Text('Breeder')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setLocal(() => birdType = v ?? 'broiler'),
              ),
              TextField(controller: breedCtrl, decoration: const InputDecoration(labelText: 'Breed')),
              TextField(controller: qtyCtrl, decoration: const InputDecoration(labelText: 'Quantity'),
                  keyboardType: TextInputType.number),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      await FlockService.create({
        'batch_name': batchCtrl.text.trim(),
        'bird_type': birdType,
        'breed': breedCtrl.text.trim(),
        'quantity': int.tryParse(qtyCtrl.text.trim()) ?? 0,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ErrorStateView.humanize(e))));
      }
    }
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
          onPressed: () => context.canPop() ? context.pop() : context.go('/farmer/feed-management'),
        ),
        title: const Text('Flocks & feeding guide',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.add, color: Colors.white), onPressed: _addFlock),
        ],
      ),
      body: _flocks == null
          ? Center(child: _error != null ? ErrorStateView(message: _error!, onRetry: _load) : const CircularProgressIndicator())
          : _flocks!.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.egg_outlined, size: 48, color: AppColors.onSurfaceVariant),
                      const SizedBox(height: 12),
                      const Text('No flocks yet. Add one to see the age chart and feeding guide.',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _addFlock, child: const Text('Add flock')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: _flocks!.length,
                    itemBuilder: (context, i) {
                      final f = _flocks![i];
                      return _FlockCard(
                        flock: f,
                        onTap: () => context.push('/farmer/feed-management/flocks/${f['id']}', extra: f),
                      );
                    },
                  ),
                ),
    );
  }
}

class _FlockCard extends StatelessWidget {
  const _FlockCard({required this.flock, required this.onTap});
  final Map<String, dynamic> flock;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = flock['status'] == 'active';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: BorderSide(color: AppColors.outline)),
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            CircleAvatar(
              backgroundColor: active ? AppColors.secondary.withValues(alpha: 0.12) : Colors.black12,
              child: Icon(Icons.egg, color: active ? AppColors.secondary : Colors.black38),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(flock['batch_name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                    '${(flock['bird_type'] ?? '').toString().toUpperCase()} · '
                    '${flock['current_quantity']} birds · ${flock['age_days']} days old',
                    style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: active ? AppColors.secondary : Colors.black26, borderRadius: AppRadius.fullAll),
              child: Text((flock['status'] ?? '').toString().toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}
