import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/core/widgets/error_state.dart';
import '../../data/flock_service.dart';

/// One flock's age chart + feeding guidance + event history (Priority 4).
/// The "chart" is a simple hand-drawn stage timeline (no charting package is
/// a dependency of this app yet — matches the project's existing "simple
/// bars" convention rather than adding a new dependency).
class FlockDetailScreen extends StatefulWidget {
  const FlockDetailScreen({super.key, required this.flockId, this.initial});
  final String flockId;
  final Map<String, dynamic>? initial;

  @override
  State<FlockDetailScreen> createState() => _FlockDetailScreenState();
}

class _FlockDetailScreenState extends State<FlockDetailScreen> {
  Map<String, dynamic>? _chart;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final chart = await FlockService.feedChart(widget.flockId);
      if (mounted) {
        setState(() {
          _chart = chart;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ErrorStateView.humanize(e));
    }
  }

  Future<void> _logEvent(String eventType) async {
    final qtyCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final needsQty = eventType == 'mortality' || eventType == 'sale' || eventType == 'transfer';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Log ${eventType.replaceAll('_', ' ')}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (needsQty)
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Number of birds')),
          TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await FlockService.logEvent(widget.flockId, {
        'event_type': eventType,
        if (needsQty) 'quantity': int.tryParse(qtyCtrl.text.trim()) ?? 0,
        'notes': notesCtrl.text.trim(),
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
    final flock = _chart?['flock'] as Map? ?? widget.initial ?? const {};
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(flock['batch_name']?.toString() ?? 'Flock',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: _chart == null
          ? Center(child: _error != null ? ErrorStateView(message: _error!, onRetry: _load) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(AppSpacing.md), children: [
                _AgeHeader(flock: flock),
                const SizedBox(height: 16),
                if (_chart!['current_guideline'] != null) ...[
                  _GuidanceCard(guideline: Map<String, dynamic>.from(_chart!['current_guideline'])),
                  const SizedBox(height: 16),
                ],
                _StageTimeline(
                  guidelines: ((_chart!['guidelines'] as List?) ?? const [])
                      .map((e) => Map<String, dynamic>.from(e as Map)).toList(),
                  ageDays: (flock['age_days'] as num?)?.toInt() ?? 0,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(color: Color(0xFFFFF4E5), borderRadius: AppRadius.mdAll),
                  child: Text(_chart!['disclaimer']?.toString() ?? '',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8A5A00))),
                ),
                const SizedBox(height: 16),
                Text('Total feed consumed: ${_chart!['total_consumed']} kg',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                const Text('Log an event', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final t in ['mortality', 'sale', 'transfer', 'vaccination', 'weight_measurement'])
                    ActionChip(label: Text(t.replaceAll('_', ' ')), onPressed: () => _logEvent(t)),
                ]),
                const SizedBox(height: 16),
                const Text('Recent events', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 8),
                for (final e in ((_chart!['recent_events'] as List?) ?? const []))
                  _EventRow(event: Map<String, dynamic>.from(e as Map)),
              ]),
            ),
    );
  }
}

class _AgeHeader extends StatelessWidget {
  const _AgeHeader({required this.flock});
  final Map flock;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.lgAll),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${flock['age_days']} days old',
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${flock['current_quantity']} of ${flock['quantity']} birds · ${flock['status']}',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ),
        const Icon(Icons.egg, color: Colors.white, size: 36),
      ]),
    );
  }
}

class _GuidanceCard extends StatelessWidget {
  const _GuidanceCard({required this.guideline});
  final Map<String, dynamic> guideline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.secondary.withValues(alpha: 0.06),
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.secondary)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(guideline['stage_label']?.toString() ?? '',
            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary, fontSize: 15)),
        const SizedBox(height: 4),
        Text(guideline['feed_type_label']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 4),
        if (guideline['recommended_grams_per_bird_per_day'] != null)
          Text('~${guideline['recommended_grams_per_bird_per_day']} g/bird/day · '
              '${guideline['frequency_per_day']}x/day',
              style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
        const SizedBox(height: 6),
        Text(guideline['guidance_text']?.toString() ?? '',
            style: const TextStyle(fontSize: 12, color: Colors.black87)),
      ]),
    );
  }
}

/// Simple hand-drawn stage timeline — a row of proportional segments, one per
/// guideline stage, with the current age marked. No charting package
/// dependency (none exists in pubspec.yaml yet).
class _StageTimeline extends StatelessWidget {
  const _StageTimeline({required this.guidelines, required this.ageDays});
  final List<Map<String, dynamic>> guidelines;
  final int ageDays;

  @override
  Widget build(BuildContext context) {
    if (guidelines.isEmpty) return const SizedBox.shrink();
    final maxAge = guidelines.map((g) => (g['max_age_days'] as num).toInt()).reduce((a, b) => a > b ? a : b);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Feeding stage timeline', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      const SizedBox(height: 10),
      SizedBox(
        height: 28,
        child: Row(
          children: guidelines.map((g) {
            final minA = (g['min_age_days'] as num).toInt();
            final maxA = (g['max_age_days'] as num).toInt();
            final isCurrent = ageDays >= minA && ageDays <= maxA;
            return Expanded(
              flex: (maxA - minA + 1).clamp(1, 100000),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: isCurrent ? AppColors.secondary : AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text('$minA-${maxA > 3000 ? '+' : maxA}',
                    style: TextStyle(
                        fontSize: 9,
                        color: isCurrent ? Colors.white : Colors.black54,
                        fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500)),
              ),
            );
          }).toList(),
        ),
      ),
      const SizedBox(height: 4),
      Text('Days (flock is $ageDays of up to $maxAge+ shown)',
          style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
    ]);
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        const Icon(Icons.circle, size: 6, color: AppColors.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
              '${event['event_date']} · ${event['event_type'].toString().replaceAll('_', ' ')}'
              '${event['quantity'] != null ? ' (${event['quantity']})' : ''}',
              style: const TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}
