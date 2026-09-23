import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:featherflow/core/format/currency.dart';
import 'package:featherflow/core/theme/theme.dart';
import 'package:intl/intl.dart';
import '../../data/farm_management_service.dart';
import '../../data/flock_service.dart';
import 'farmer_feed_marketplace_screen.dart';

class FeedManagementScreen extends StatefulWidget {
  const FeedManagementScreen({super.key});
  @override
  State<FeedManagementScreen> createState() => _FeedManagementScreenState();
}

class _FeedManagementScreenState extends State<FeedManagementScreen> {
  Map<String, dynamic>? data;
  String? error;
  Timer? _poll;
  List<Map<String, dynamic>> _flocks = [];
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final results = await Future.wait([
        FarmManagementService.get('feed'),
        FlockService.list(),
        FarmManagementService.get('notifications'),
      ]);
      if (mounted) {
        final notif = results[2] as Map<String, dynamic>;
        final rows = (notif['notifications'] as List? ?? const []);
        setState(() {
          data = results[0] as Map<String, dynamic>;
          _flocks = results[1] as List<Map<String, dynamic>>;
          _unreadNotifications = rows.where((n) => n['is_read'] != true).length;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  int get _activeFlockCount => _flocks.where((f) => f['status'] == 'active').length;
  int get _totalBirds => _flocks
      .where((f) => f['status'] == 'active')
      .fold<int>(0, (a, f) => a + ((f['current_quantity'] as num?)?.toInt() ?? 0));

  Future<void> _showNotifications() async {
    try {
      final result = await FarmManagementService.get('notifications');
      final rows = List<Map<String, dynamic>>.from(
          (result['notifications'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e)));
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
            child: Column(children: [
              ListTile(
                title: const Text('Feed notifications', style: TextStyle(fontWeight: FontWeight.w800)),
                trailing: IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ),
              const Divider(height: 1),
              Expanded(
                child: rows.isEmpty
                    ? const Center(child: Text('No notifications yet.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (_, index) {
                          final x = rows[index];
                          return ListTile(
                            leading: const Icon(Icons.notifications_outlined, color: AppColors.secondary),
                            title: Text('${x['title']}',
                                style: TextStyle(fontWeight: x['is_read'] == true ? FontWeight.w500 : FontWeight.w800)),
                            subtitle: Text('${x['body']}\n${x['time']}'),
                            isThreeLine: true,
                            trailing: x['is_read'] == true
                                ? null
                                : const CircleAvatar(radius: 4, backgroundColor: AppColors.error),
                          );
                        },
                      ),
              ),
            ]),
          ),
        ),
      );
      await FarmManagementService.patch('notifications', {});
      if (mounted) setState(() => _unreadNotifications = 0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/farmer'),
        ),
        title: const Text(
          'Feed Management',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          Stack(alignment: Alignment.center, children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined, color: Colors.white),
              onPressed: _showNotifications,
              tooltip: 'Feed notifications',
            ),
            if (_unreadNotifications > 0)
              Positioned(
                right: 6, top: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(_unreadNotifications > 99 ? '99+' : '$_unreadNotifications',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white),
            onPressed: () => context.go('/farmer'),
            tooltip: 'Home',
          ),
        ],
      ),
      body: data == null
          ? Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 32),
                      const SizedBox(height: 8),
                      Text(error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _load, child: const Text('Retry')),
                    ]))
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FlockHeaderCard(activeFlocks: _activeFlockCount, totalBirds: _totalBirds),
                    const SizedBox(height: AppSpacing.md),
                    _MarketplaceQuickAccess(
                      onBrowse: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const FarmerFeedMarketplaceScreen())),
                      onOrders: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const FarmerFeedMarketplaceScreen(initialTab: 2))),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _SummaryRow(data: data!),
                    const SizedBox(height: AppSpacing.md),
                    _FlocksAndAgeChartButton(
                        onPressed: () => context.push('/farmer/feed-management/flocks')),
                    const SizedBox(height: AppSpacing.md),
                    _StockSection(
                        data: data!,
                        onStatus: _setStockStatus,
                        onDelete: _deleteStock),
                    const SizedBox(height: AppSpacing.md),
                    _AddFeedButton(onPressed: _addFeed),
                    const SizedBox(height: AppSpacing.md),
                    _FeedScheduleSection(
                        data: data!, onPressed: _manageSchedules),
                    const SizedBox(height: AppSpacing.md),
                    _FeedHistorySection(data: data!),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              )),
    );
  }

  Future<void> _addFeed() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddFeedDialog(),
    );
    if (saved == true) await _load();
  }

  Future<void> _addSchedule() async {
    final stocks = List<Map<String, dynamic>>.from(
        (data!['stock'] as List).map((e) => Map<String, dynamic>.from(e)));
    if (stocks.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Add feed stock first.')));
      return;
    }
    String feedTypeId = stocks.first['feed_type_id'], frequency = 'daily';
    final time = TextEditingController(text: '06:00'),
        qty = TextEditingController();
    final save = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setLocal) => AlertDialog(
                    title: const Text('Add Feed Schedule'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<String>(
                          initialValue: feedTypeId,
                          items: stocks
                              .map((x) => DropdownMenuItem<String>(
                                  value: x['feed_type_id'],
                                  child: Text(x['name'])))
                              .toList(),
                          onChanged: (v) => setLocal(() => feedTypeId = v!),
                          decoration:
                              const InputDecoration(labelText: 'Feed type *')),
                      TextField(
                          controller: time,
                          decoration: const InputDecoration(
                              labelText: 'Time (HH:mm) *')),
                      TextField(
                          controller: qty,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Quantity per feeding *')),
                      DropdownButtonFormField<String>(
                          initialValue: frequency,
                          items: ['daily', 'twice_daily', 'custom']
                              .map((v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(v.replaceAll('_', ' '))))
                              .toList(),
                          onChanged: (v) => setLocal(() => frequency = v!),
                          decoration:
                              const InputDecoration(labelText: 'Frequency *')),
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Save'))
                    ])));
    if (save != true) return;
    try {
      await FarmManagementService.post('feed/schedules', {
        'feed_type_id': feedTypeId,
        'scheduled_time': time.text,
        'quantity_per_feeding': qty.text,
        'frequency': frequency
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _setStockStatus(String id, String value) async {
    try {
      await FarmManagementService.patch(
          'feed/stock', {'id': id, 'status': value});
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _deleteStock(String id) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Remove Feed Stock?'),
                content: const Text(
                    'This removes the current stock row. Purchase history is retained.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'))
                ]));
    if (ok == true) {
      await FarmManagementService.delete('feed/stock', {'id': id});
      await _load();
    }
  }

  Future<void> _manageSchedules() async {
    final rows = List<Map<String, dynamic>>.from(
        (data!['schedules'] as List).map((e) => Map<String, dynamic>.from(e)));
    final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Feed Schedules'),
                content: SizedBox(
                    width: 360,
                    child: rows.isEmpty
                        ? const Text('No schedule yet.')
                        : ListView(
                            shrinkWrap: true,
                            children: rows
                                .map((x) => ListTile(
                                    title: Text(x['feed_type']),
                                    subtitle: Text(
                                        '${x['scheduled_time']} · ${x['quantity_per_feeding']} kg'),
                                    trailing: IconButton(
                                        tooltip: 'Delete schedule',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () async {
                                          await FarmManagementService.delete(
                                              'feed/schedules',
                                              {'id': x['id']});
                                          if (ctx.mounted) {
                                            Navigator.pop(ctx, 'reload');
                                          }
                                        }),
                                    onTap: () async {
                                      Navigator.pop(ctx, 'edit:${x['id']}');
                                    }))
                                .toList())),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close')),
                  FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, 'add'),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Schedule'))
                ]));
    if (action == 'add') {
      await _addSchedule();
    } else if (action == 'reload') {
      await _load();
    } else if (action != null && action.startsWith('edit:')) {
      await _editExistingSchedule(
          rows.firstWhere((x) => x['id'] == action.substring(5)));
    }
  }

  Future<void> _editExistingSchedule(Map<String, dynamic> row) async {
    final stocks = List<Map<String, dynamic>>.from(
        (data!['stock'] as List).map((e) => Map<String, dynamic>.from(e)));
    String feedTypeId = stocks.firstWhere((x) => x['name'] == row['feed_type'],
            orElse: () => stocks.first)['feed_type_id'],
        frequency = row['frequency'];
    final time = TextEditingController(text: row['scheduled_time']),
        qty = TextEditingController(text: '${row['quantity_per_feeding']}');
    final save = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setLocal) => AlertDialog(
                    title: const Text('Edit Feed Schedule'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<String>(
                          initialValue: feedTypeId,
                          items: stocks
                              .map((x) => DropdownMenuItem<String>(
                                  value: x['feed_type_id'],
                                  child: Text(x['name'])))
                              .toList(),
                          onChanged: (v) => setLocal(() => feedTypeId = v!)),
                      TextField(
                          controller: time,
                          decoration:
                              const InputDecoration(labelText: 'Time (HH:mm)')),
                      TextField(
                          controller: qty,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Quantity')),
                      DropdownButtonFormField<String>(
                          initialValue: frequency,
                          items: ['daily', 'twice_daily', 'custom']
                              .map((v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(v.replaceAll('_', ' '))))
                              .toList(),
                          onChanged: (v) => setLocal(() => frequency = v!))
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Update'))
                    ])));
    if (save == true) {
      await FarmManagementService.patch('feed/schedules', {
        'id': row['id'],
        'feed_type_id': feedTypeId,
        'scheduled_time': time.text,
        'quantity_per_feeding': qty.text,
        'frequency': frequency
      });
      await _load();
    }
  }

}

/// "Add Feed" — records a feed purchase and increases current stock.
/// Renamed from "Add Feed Purchase" per FARMER_FEED_MANAGEMENT_AND_DASHBOARD_FIXES.md.
/// A dedicated StatefulWidget (not an inline showDialog closure) so it can
/// own its own busy/validation/error state — the same pattern already used
/// by the farmer cost-tracking dialogs (cost_dialogs.dart).
class _AddFeedDialog extends StatefulWidget {
  const _AddFeedDialog();

  @override
  State<_AddFeedDialog> createState() => _AddFeedDialogState();
}

class _AddFeedDialogState extends State<_AddFeedDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _quantity = TextEditingController();
  final _cost = TextEditingController();
  final _notes = TextEditingController();
  String _unit = 'kg';
  bool _busy = false;
  String? _errorText;

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _quantity.dispose();
    _cost.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _positiveNumber(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final n = num.tryParse(v.trim());
    if (n == null) return 'Enter a valid number';
    if (n <= 0) return 'Must be greater than zero';
    return null;
  }

  String? _nonNegativeNumber(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final n = num.tryParse(v.trim());
    if (n == null) return 'Enter a valid number';
    if (n < 0) return 'Cannot be negative';
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return; // duplicate-tap guard
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      await FarmManagementService.post('feed', {
        'name': _name.text.trim(),
        'brand': _brand.text.trim(),
        'unit': _unit,
        'quantity': _quantity.text.trim(),
        'cost_per_unit': _cost.text.trim(),
        if (_notes.text.trim().isNotEmpty) 'note': _notes.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorText = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Feed'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  decoration:
                      const InputDecoration(labelText: 'Feed name *', filled: true),
                  textInputAction: TextInputAction.next,
                  validator: _required,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _brand,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                      labelText: 'Brand', helperText: 'Optional', filled: true),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.sm),
                // Quantity + Unit share a row on wide dialogs (web/desktop);
                // narrow screens (e.g. a phone-width web view) stack them so
                // neither field gets squeezed unreadably thin.
                LayoutBuilder(builder: (context, constraints) {
                  final quantityField = TextFormField(
                    controller: _quantity,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    decoration:
                        const InputDecoration(labelText: 'Quantity *', filled: true),
                    validator: _positiveNumber,
                  );
                  final unitField = DropdownButtonFormField<String>(
                    initialValue: _unit,
                    items: ['kg', 'bag', 'liter']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: _busy ? null : (v) => setState(() => _unit = v!),
                    decoration:
                        const InputDecoration(labelText: 'Unit *', filled: true),
                  );
                  if (constraints.maxWidth < 360) {
                    return Column(children: [
                      quantityField,
                      const SizedBox(height: AppSpacing.sm),
                      unitField,
                    ]);
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: quantityField),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(flex: 2, child: unitField),
                    ],
                  );
                }),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _cost,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                      labelText: 'Cost per unit *', prefixText: '৳ ', filled: true),
                  validator: _nonNegativeNumber,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _notes,
                  enabled: !_busy,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Notes', helperText: 'Optional', filled: true),
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_errorText!,
                      style: const TextStyle(color: AppColors.error, fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Add Feed'),
        ),
      ],
    );
  }
}

/// Feed Management landing header: title + a quick flock/bird summary so a
/// farmer doesn't have to scroll to see how many active flocks/birds they
/// have before deciding what to do next.
class _FlockHeaderCard extends StatelessWidget {
  const _FlockHeaderCard({required this.activeFlocks, required this.totalBirds});
  final int activeFlocks;
  final int totalBirds;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const Icon(Icons.grass, color: Colors.white, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your feed at a glance', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 2),
            Text('$activeFlocks active flock${activeFlocks == 1 ? '' : 's'} · $totalBirds birds',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
        ),
      ]),
    );
  }
}

/// "No duplicate order entry points" — this is the ONLY place a farmer
/// reaches the feed e-commerce section from; the old standalone "Order
/// Feed" dashboard tile was removed (see farmer_dashboard_screen.dart) and
/// the old `/farmer/order-feed` route now redirects here.
class _MarketplaceQuickAccess extends StatelessWidget {
  const _MarketplaceQuickAccess({required this.onBrowse, required this.onOrders});
  final VoidCallback onBrowse;
  final VoidCallback onOrders;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: _QuickCard(
          icon: Icons.storefront_outlined,
          label: 'Feed Marketplace',
          subtitle: 'Browse approved feeds',
          color: AppColors.secondary,
          onTap: onBrowse,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _QuickCard(
          icon: Icons.receipt_long_outlined,
          label: 'My Feed Orders',
          subtitle: 'Track your orders',
          color: AppColors.primary,
          onTap: onOrders,
        ),
      ),
    ]);
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.icon, required this.label, required this.subtitle,
    required this.color, required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
          Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 11)),
        ]),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SummaryRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final s = Map<String, dynamic>.from(data['summary']);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.sm,
      mainAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.7,
      children: [
        _SummaryCard(
          icon: Icons.inventory_2_outlined,
          label: 'Total Feed Stock',
          value: '${s['total_stock']} kg',
          valueColor: Colors.black87,
        ),
        _SummaryCard(
          icon: Icons.local_dining_outlined,
          label: 'Feed Types',
          value: '${s['feed_types']}',
          valueColor: Colors.black87,
        ),
        _SummaryCard(
          icon: Icons.hourglass_bottom_outlined,
          label: 'Low Stock Items',
          value: '${s['low_stock_items']}',
          valueColor: Colors.orange,
          badge: 'Low Stock',
          badgeColor: Colors.orange,
        ),
        _SummaryCard(
          icon: Icons.payments_outlined,
          label: 'Stock Value',
          value: taka((s['stock_value'] as num?) ?? 0),
          valueColor: AppColors.primary,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;
  final String? badge;
  final Color? badgeColor;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: const Color(0xFFDEEAE5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: AppColors.primary, size: 18),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor!.withValues(alpha: 0.12),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: badgeColor),
                  ),
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: valueColor),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: Colors.black54),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StockSection extends StatelessWidget {
  final Map<String, dynamic> data;
  final void Function(String, String) onStatus;
  final ValueChanged<String> onDelete;
  const _StockSection(
      {required this.data, required this.onStatus, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final source = List<Map<String, dynamic>>.from(
        (data['stock'] as List).map((e) => Map<String, dynamic>.from(e)));
    final rows = source
        .map((r) => _StockRow(
            id: r['id'],
            type: r['name'],
            qty: '${r['quantity_available']} ${r['unit']}',
            unitCost: '${taka((r['cost_per_unit'] as num?) ?? 0)}/${r['unit']}',
            total: taka((r['total_value'] as num?) ?? 0),
            status: r['status'],
            onStatus: onStatus,
            onDelete: onDelete))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Current Stock',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: const Color(0xFFDEEAE5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              const _StockTableHeader(),
              const Divider(height: 1, color: Color(0xFFDEEAE5)),
              ...List.generate(
                rows.length,
                (i) => Column(
                  children: [
                    rows[i],
                    if (i < rows.length - 1)
                      const Divider(height: 1, color: Color(0xFFDEEAE5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StockTableHeader extends StatelessWidget {
  const _StockTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: const BoxDecoration(
        color: Color(0xFFF0F7F4),
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: _HCell('Feed Type')),
          Expanded(flex: 2, child: _HCell('Qty')),
          Expanded(flex: 2, child: _HCell('Unit Cost')),
          Expanded(flex: 2, child: _HCell('Total')),
          Expanded(flex: 2, child: _HCell('Status')),
        ],
      ),
    );
  }
}

class _HCell extends StatelessWidget {
  final String text;

  const _HCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
    );
  }
}

class _StockRow extends StatelessWidget {
  final String id;
  final String type;
  final String qty;
  final String unitCost;
  final String total;
  final String status;
  final void Function(String, String) onStatus;
  final ValueChanged<String> onDelete;

  const _StockRow({
    required this.id,
    required this.type,
    required this.qty,
    required this.unitCost,
    required this.total,
    required this.status,
    required this.onStatus,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor =
        status == 'good' ? AppColors.secondary : AppColors.error;
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              type,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(qty,
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ),
          Expanded(
            flex: 2,
            child: Text(unitCost,
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              total,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 2,
            child: PopupMenuButton<String>(
                tooltip: 'Change status or delete',
                onSelected: (v) =>
                    v == 'delete' ? onDelete(id) : onStatus(id, v),
                itemBuilder: (context) => const [
                      PopupMenuItem(value: 'good', child: Text('Good')),
                      PopupMenuItem(value: 'low', child: Text('Low')),
                      PopupMenuItem(value: 'out', child: Text('Out')),
                      PopupMenuDivider(),
                      PopupMenuItem(
                          value: 'delete', child: Text('Delete stock'))
                    ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Text(
                    status[0].toUpperCase() + status.substring(1),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusColor),
                  ),
                )),
          ),
        ],
      ),
    );
  }
}

class _AddFeedButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _AddFeedButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Add Feed'),
        style: ElevatedButton.styleFrom(
          // AppColors.secondary is a bright accent green (luminance ~0.35),
          // not the dark navigation green — black text reaches ~8:1 contrast
          // here vs. ~2.6:1 for white, so black is the correct pairing (see
          // periodChipTextColor's doc comment in cost_management_screen.dart
          // for the same distinction).
          backgroundColor: AppColors.secondary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _FlocksAndAgeChartButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _FlocksAndAgeChartButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainerHighest,
      borderRadius: AppRadius.mdAll,
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
              borderRadius: AppRadius.mdAll, border: Border.all(color: AppColors.outline)),
          child: const Row(children: [
            Icon(Icons.timeline, color: AppColors.primary),
            SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Flocks & feeding age chart',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                SizedBox(height: 2),
                Text('Flock age, feeding stage guidance, and reminders',
                    style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
              ]),
            ),
            Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

class _FeedScheduleSection extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onPressed;
  const _FeedScheduleSection({required this.data, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final schedules = List<Map<String, dynamic>>.from(
        (data['schedules'] as List).map((e) => Map<String, dynamic>.from(e)));
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: const Color(0xFFDEEAE5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.schedule_outlined, color: AppColors.primary, size: 20),
              SizedBox(width: AppSpacing.sm),
              Text(
                'Feed Schedule',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ...schedules.asMap().entries.expand((e) => [
                _ScheduleItem(
                    icon: e.key.isEven
                        ? Icons.wb_sunny_outlined
                        : Icons.nights_stay_outlined,
                    iconColor: e.key.isEven ? Colors.orange : AppColors.primary,
                    time: e.value['scheduled_time'],
                    label:
                        '${e.value['feed_type']} · ${e.value['frequency'].toString().replaceAll('_', ' ')}',
                    qty: '${e.value['quantity_per_feeding']} kg'),
                if (e.key < schedules.length - 1) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const Divider(color: Color(0xFFDEEAE5)),
                  const SizedBox(height: AppSpacing.sm)
                ]
              ]),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit Schedule'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape:
                  const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
              textStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String time;
  final String label;
  final String qty;

  const _ScheduleItem({
    required this.icon,
    required this.iconColor,
    required this.time,
    required this.label,
    required this.qty,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: AppRadius.smAll,
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87),
              ),
              Text(
                time,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: AppRadius.smAll,
          ),
          child: Text(
            qty,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}

class _FeedHistorySection extends StatelessWidget {
  final Map<String, dynamic> data;
  const _FeedHistorySection({required this.data});

  @override
  Widget build(BuildContext context) {
    final source = List<Map<String, dynamic>>.from(
        (data['history'] as List).map((e) => Map<String, dynamic>.from(e)));
    final rows = source
        .map((x) => _HistoryData(
            date: DateFormat('dd MMM yyyy')
                .format(DateTime.parse(x['purchased_at'])),
            type: x['feed_type'],
            qty: '${x['quantity']} ${x['unit']}',
            cost: x['cost'] == null ? '—' : taka(x['cost'] as num),
            movementType: (x['movement_type'] ?? 'purchase').toString()))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Feed History',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: const Color(0xFFDEEAE5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              const _HistoryTableHeader(),
              const Divider(height: 1, color: Color(0xFFDEEAE5)),
              ...List.generate(
                rows.length,
                (i) => Column(
                  children: [
                    _HistoryRow(data: rows[i]),
                    if (i < rows.length - 1)
                      const Divider(height: 1, color: Color(0xFFDEEAE5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryData {
  final String date;
  final String type;
  final String qty;
  final String cost;
  final String movementType;

  const _HistoryData({
    required this.date,
    required this.type,
    required this.qty,
    required this.cost,
    required this.movementType,
  });
}

class _HistoryTableHeader extends StatelessWidget {
  const _HistoryTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: const BoxDecoration(
        color: Color(0xFFF0F7F4),
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 2, child: _HCell('Date')),
          Expanded(flex: 3, child: _HCell('Type')),
          Expanded(flex: 2, child: _HCell('Qty')),
          Expanded(flex: 2, child: _HCell('Cost')),
          Expanded(flex: 2, child: _HCell('Event')),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final _HistoryData data;

  const _HistoryRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(data.date,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              data.type,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(data.qty,
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              data.cost,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 2,
            child: _MovementBadge(movementType: data.movementType),
          ),
        ],
      ),
    );
  }
}

/// Small colored label for a feed_stock_movements event type — purchases add
/// to stock (green), consumption/removal draw it down (red), a manual
/// adjustment is neutral (grey). Reuses the app's existing semantic colors
/// rather than introducing new ones.
class _MovementBadge extends StatelessWidget {
  final String movementType;
  const _MovementBadge({required this.movementType});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (movementType) {
      'purchase' => ('Purchase', AppColors.secondary),
      'consumption' => ('Used', AppColors.error),
      'removal' => ('Removed', AppColors.error),
      'adjustment' => ('Adjusted', Colors.black54),
      _ => (movementType, Colors.black54),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.smAll,
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
