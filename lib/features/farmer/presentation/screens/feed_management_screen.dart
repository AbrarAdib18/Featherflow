import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:featherflow/core/theme/theme.dart';
import 'package:intl/intl.dart';
import '../../data/farm_management_service.dart';

class FeedManagementScreen extends StatefulWidget {
  const FeedManagementScreen({super.key});
  @override
  State<FeedManagementScreen> createState() => _FeedManagementScreenState();
}

class _FeedManagementScreenState extends State<FeedManagementScreen> {
  Map<String, dynamic>? data;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await FarmManagementService.get('feed');
      if (mounted)
        setState(() {
          data = result;
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
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
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Feed Management',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
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
                  : Text(error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SummaryRow(data: data!),
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
                    _SupplierSection(data: data!, onPressed: _orderFeed),
                    const SizedBox(height: AppSpacing.md),
                    _FeedHistorySection(data: data!),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              )),
    );
  }

  Future<void> _addFeed() async {
    final name = TextEditingController(),
        brand = TextEditingController(),
        quantity = TextEditingController(),
        cost = TextEditingController(),
        supplier = TextEditingController();
    String unit = 'kg';
    final save = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setLocal) => AlertDialog(
                    title: const Text('Add Feed Purchase'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          decoration:
                              const InputDecoration(labelText: 'Feed name *')),
                      TextField(
                          controller: brand,
                          decoration:
                              const InputDecoration(labelText: 'Brand')),
                      DropdownButtonFormField<String>(
                          initialValue: unit,
                          items: ['kg', 'bag', 'liter']
                              .map((v) =>
                                  DropdownMenuItem(value: v, child: Text(v)))
                              .toList(),
                          onChanged: (v) => setLocal(() => unit = v!),
                          decoration:
                              const InputDecoration(labelText: 'Unit *')),
                      TextField(
                          controller: quantity,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Quantity *')),
                      TextField(
                          controller: cost,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Cost per unit *')),
                      TextField(
                          controller: supplier,
                          decoration: const InputDecoration(
                              labelText: 'Supplier name')),
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
      await FarmManagementService.post('feed', {
        'name': name.text,
        'brand': brand.text,
        'unit': unit,
        'quantity': quantity.text,
        'cost_per_unit': cost.text,
        'supplier_name': supplier.text
      });
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
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
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _setStockStatus(String id, String value) async {
    await FarmManagementService.patch(
        'feed/stock', {'id': id, 'status': value});
    await _load();
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
                                          if (ctx.mounted)
                                            Navigator.pop(ctx, 'reload');
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

  Future<void> _orderFeed() async {
    final stocks = List<Map<String, dynamic>>.from(
        (data!['stock'] as List).map((e) => Map<String, dynamic>.from(e)));
    if (stocks.isEmpty) return;
    String feedTypeId = stocks.first['feed_type_id'];
    final supplier = TextEditingController(text: stocks.first['supplier_name']),
        qty = TextEditingController();
    DateTime expected = DateTime.now().add(const Duration(days: 3));
    final save = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setLocal) => AlertDialog(
                    title: const Text('Place Supplier Order'),
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
                          controller: supplier,
                          decoration:
                              const InputDecoration(labelText: 'Supplier *')),
                      TextField(
                          controller: qty,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Order quantity *')),
                      ListTile(
                          title: const Text('Expected delivery'),
                          subtitle:
                              Text(DateFormat('dd MMM yyyy').format(expected)),
                          onTap: () async {
                            final d = await showDatePicker(
                                context: ctx,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365)),
                                initialDate: expected);
                            if (d != null) setLocal(() => expected = d);
                          })
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Place Order'))
                    ])));
    if (save == true) {
      await FarmManagementService.post('feed/orders', {
        'feed_type_id': feedTypeId,
        'supplier_name': supplier.text,
        'quantity': qty.text,
        'expected_date': DateFormat('yyyy-MM-dd').format(expected)
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Supplier order created.')));
    }
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
          value: '৳${s['stock_value']}',
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
            unitCost: '৳${r['cost_per_unit']}/${r['unit']}',
            total: '৳${r['total_value']}',
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
        label: const Text('Add Feed Purchase'),
        style: ElevatedButton.styleFrom(
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

class _SupplierSection extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onPressed;
  const _SupplierSection({required this.data, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final suppliers = List<Map<String, dynamic>>.from(
        (data['suppliers'] as List).map((e) => Map<String, dynamic>.from(e)));
    final supplier = suppliers.isEmpty ? null : suppliers.first;
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
              Icon(Icons.storefront_outlined,
                  color: AppColors.primary, size: 20),
              SizedBox(width: AppSpacing.sm),
              Text(
                'Supplier',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _SupplierInfoRow(
              icon: Icons.business_outlined,
              label: supplier?['name'] ?? 'No supplier recorded'),
          const SizedBox(height: AppSpacing.xs),
          _SupplierInfoRow(
              icon: Icons.grass_outlined,
              label: supplier == null
                  ? 'Add a purchase to record a supplier'
                  : (supplier['feed_types'] as List).join(', ')),
          const SizedBox(height: AppSpacing.xs),
          _SupplierInfoRow(
              icon: Icons.local_shipping_outlined,
              label: 'Suppliers used: ${suppliers.length}'),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.shopping_cart_outlined, size: 16),
              label: const Text('Order Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape:
                    const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
                textStyle:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SupplierInfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: AppSpacing.sm),
        Text(label,
            style: const TextStyle(fontSize: 13, color: Colors.black87)),
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
            cost: '৳${x['cost']}',
            supplier: x['supplier_name'].toString().isEmpty
                ? 'Not specified'
                : x['supplier_name']))
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
  final String supplier;

  const _HistoryData({
    required this.date,
    required this.type,
    required this.qty,
    required this.cost,
    required this.supplier,
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
          Expanded(flex: 3, child: _HCell('Supplier')),
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
            flex: 3,
            child: Text(data.supplier,
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ),
        ],
      ),
    );
  }
}
