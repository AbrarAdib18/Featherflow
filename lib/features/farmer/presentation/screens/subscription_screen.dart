import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/core/widgets/error_state.dart';
import 'package:featherflow/features/farmer/data/subscription_service.dart';
import 'package:featherflow/features/farmer/data/models/subscription_models.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  PlansResponse? _data;
  String? _error;
  bool _loading = true;

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
      final d = await SubscriptionService.plans();
      if (mounted) {
        setState(() {
          _data = d;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ErrorStateView.humanize(e);
          _loading = false;
        });
      }
    }
  }

  void _openPlan(SubPlan plan) {
    context.push('/subscription/review',
        extra: (plan: plan, isDevMode: _data?.isDevMode ?? true));
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
        title: const Text('Featherflow Plans',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white),
            onPressed: () => context.go('/farmer'),
            tooltip: 'Home',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorStateView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _body(_data!),
                ),
    );
  }

  Widget _body(PlansResponse d) {
    final current = d.current;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (d.isDevMode)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
                color: Color(0xFFFFF4E5),
                borderRadius: AppRadius.mdAll),
            child: const Row(children: [
              Icon(Icons.construction, size: 16, color: Color(0xFF8A5A00)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Development payment mode — checkout is simulated, no real '
                  'money is charged.',
                  style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8A5A00),
                      fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
        if (current != null) _CurrentPlanCard(current: current),
        const SizedBox(height: 8),
        Text(current == null ? 'Choose your plan' : 'Change your plan',
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.primary)),
        const SizedBox(height: 4),
        const Text(
          'Unlock unlimited disease scans, full cost management, the tax '
          'calculator and vet booking.',
          style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
        ),
        const SizedBox(height: 16),
        if (d.freePlan != null)
          _PlanCard(
            plan: d.freePlan!,
            isCurrent: current == null || current.plan.code == 'free',
            onSubscribe: null,
          ),
        for (final p in d.plans)
          _PlanCard(
            plan: p,
            isCurrent: current?.plan.code == p.code,
            onSubscribe: p.isActive ? () => _openPlan(p) : null,
          ),
        const SizedBox(height: 16),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 13, color: Colors.black38),
            SizedBox(width: 6),
            Text('Payments are processed securely. Cancel anytime.',
                style: TextStyle(fontSize: 12, color: Colors.black38)),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({required this.current});
  final CurrentSubscription current;

  @override
  Widget build(BuildContext context) {
    final exp = current.expiresAt;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: AppRadius.lgAll,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.workspace_premium, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text('Current plan · ${current.plan.name}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: const BoxDecoration(
                color: AppColors.secondary, borderRadius: AppRadius.smAll),
            child: Text(current.status.toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          exp != null
              ? 'Renews / ends ${exp.toIso8601String().split('T').first}'
              : 'Active',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ]),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.onSubscribe,
  });

  final SubPlan plan;
  final bool isCurrent;
  final VoidCallback? onSubscribe;

  @override
  Widget build(BuildContext context) {
    final highlighted = plan.recommended && !isCurrent;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.secondary.withValues(alpha: 0.04)
            : Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: highlighted ? AppColors.secondary : const Color(0xFFDEEAE5),
          width: highlighted ? 2 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(plan.name,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: highlighted ? AppColors.secondary : AppColors.primary)),
          const SizedBox(width: 8),
          if (plan.recommended && !isCurrent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: const BoxDecoration(
                  color: AppColors.secondary, borderRadius: AppRadius.smAll),
              child: const Text('Most popular',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
          if (isCurrent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: const BoxDecoration(
                  color: Color(0xFFE8F5EE),
                  borderRadius: AppRadius.smAll),
              child: const Text('Current',
                  style: TextStyle(
                      color: Color(0xFF2E7D32),
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
        ]),
        if (plan.tagline.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(plan.tagline,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
        const SizedBox(height: 10),
        Text(
          plan.price == 0
              ? 'Free'
              : '${plan.currency} ${plan.price.toStringAsFixed(0)}',
          style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: highlighted ? AppColors.secondary : AppColors.primary),
        ),
        if (plan.price != 0)
          Text(plan.intervalLabel,
              style: const TextStyle(fontSize: 12, color: Colors.black45)),
        const SizedBox(height: 10),
        const Divider(color: Color(0xFFE8F5EE)),
        const SizedBox(height: 6),
        for (final f in plan.features)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              const Icon(Icons.check_circle,
                  size: 16, color: Color(0xFF2E7D32)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(f,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.black87))),
            ]),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (isCurrent || onSubscribe == null) ? null : onSubscribe,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  highlighted ? AppColors.secondary : AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE0E8E4),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(isCurrent
                ? 'Your current plan'
                : plan.price == 0
                    ? 'Free plan'
                    : 'Choose ${plan.name}'),
          ),
        ),
      ]),
    );
  }
}
