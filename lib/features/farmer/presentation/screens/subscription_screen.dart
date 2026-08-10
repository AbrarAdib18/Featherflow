import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/core/l10n/app_localizations.dart';
import 'package:featherflow/features/farmer/data/farm_management_service.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isYearly = false;

  Future<void> _subscribe(String planName) async {
    try {
      final data = await FarmManagementService.get('subscriptions');
      final plans = List<Map<String, dynamic>>.from(data['plans'] ?? const []);
      final plan = plans.firstWhere(
        (item) => item['name'].toString().toLowerCase() == planName.toLowerCase(),
      );
      await FarmManagementService.post('subscriptions', {
        'plan_id': plan['id'],
        'auto_renew': true,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$planName subscription requested.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  List<Map<String, dynamic>> _buildPlans(AppLocalizations l) => [
        {
          'name': 'Free',
          'monthlyPrice': '৳0',
          'yearlyPrice': '৳0',
          'tagline': l.freePlanTagline,
          'highlighted': false,
          'badge': '',
          'buttonLabel': l.currentPlan,
          'buttonEnabled': false,
          'features': <Map<String, dynamic>>[
            {'label': l.feat3Scans, 'included': true},
            {'label': l.featBasicDashboard, 'included': true},
            {'label': l.featCommunityRead, 'included': true},
            {'label': l.featPaperPortal, 'included': true},
            {'label': l.featCostMgmt, 'included': false},
            {'label': l.featVetBooking, 'included': false},
            {'label': l.featTaxCalc, 'included': false},
            {'label': l.featUnlimitedScans, 'included': false},
          ],
        },
        {
          'name': 'Pro',
          'monthlyPrice': '৳499/mo',
          'yearlyPrice': '৳4,790/yr',
          'tagline': l.proPlanTagline,
          'highlighted': true,
          'badge': l.mostPopular,
          'buttonLabel': l.getPro,
          'buttonEnabled': true,
          'features': <Map<String, dynamic>>[
            {'label': l.featUnlimitedDisease, 'included': true},
            {'label': l.featFullCost, 'included': true},
            {'label': l.featVetMap, 'included': true},
            {'label': l.featTaxCalc, 'included': true},
            {'label': l.featFeedLabor, 'included': true},
            {'label': l.featCommunityPost, 'included': true},
            {'label': l.featPrioritySupport, 'included': true},
            {'label': l.featResearcherPanel, 'included': false},
            {'label': l.featPaperPublishing, 'included': false},
          ],
        },
        {
          'name': 'Research',
          'monthlyPrice': '৳999/mo',
          'yearlyPrice': '৳9,590/yr',
          'tagline': l.researchPlanTagline,
          'highlighted': false,
          'badge': '',
          'buttonLabel': l.getResearch,
          'buttonEnabled': true,
          'features': <Map<String, dynamic>>[
            {'label': l.featEverythingInPro, 'included': true},
            {'label': l.featResearcherPanelAccess, 'included': true},
            {'label': l.featPaperSubmit, 'included': true},
            {'label': l.featResearchAnalytics, 'included': true},
            {'label': l.featCollaboration, 'included': true},
            {'label': l.featVerifiedBadge, 'included': true},
          ],
        },
      ];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final plans = _buildPlans(l);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l.featherflowPlans,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white),
            onPressed: () => context.go('/farmer'),
            tooltip: 'Home',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _HeaderHero(),
            const SizedBox(height: AppSpacing.lg),
            _BillingToggle(
              isYearly: _isYearly,
              onToggle: (val) => setState(() => _isYearly = val),
            ),
            const SizedBox(height: AppSpacing.lg),
            ...plans.map(
              (plan) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _PlanCard(
                  plan: plan,
                  isYearly: _isYearly,
                  onSubscribe: () => _subscribe(plan['name'] as String),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const _ComparisonTable(),
            const SizedBox(height: AppSpacing.lg),
            const _PaymentNote(),
            const SizedBox(height: AppSpacing.lg),
            const _FAQSection(),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

// ── Section 1 — Header Hero ───────────────────────────────────────────────────

class _HeaderHero extends StatelessWidget {
  const _HeaderHero();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.secondary),
              borderRadius: AppRadius.fullAll,
            ),
            child: Text(
              l.upgradeFarmExperience,
              style: const TextStyle(
                color: AppColors.secondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l.chooseYourPlan,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l.subscriptionSubtitle,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 14,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Section 2 — Billing Toggle ────────────────────────────────────────────────

class _BillingToggle extends StatelessWidget {
  final bool isYearly;
  final ValueChanged<bool> onToggle;

  const _BillingToggle({required this.isYearly, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F7F4),
          borderRadius: AppRadius.fullAll,
          border: Border.all(color: const Color(0xFFDEEAE5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToggleSegment(
              label: l.monthly,
              selected: !isYearly,
              onTap: () => onToggle(false),
            ),
            const SizedBox(width: 4),
            _ToggleSegment(
              label: l.yearly,
              selected: isYearly,
              onTap: () => onToggle(true),
              badge: isYearly ? l.save20 : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleSegment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  const _ToggleSegment({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: AppRadius.fullAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.black54,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs, vertical: 2),
                decoration: const BoxDecoration(
                  color: Color(0xFF4CAF50),
                  borderRadius: AppRadius.smAll,
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Section 3 — Plan Card ─────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  final bool isYearly;
  final VoidCallback onSubscribe;

  const _PlanCard({required this.plan, required this.isYearly, required this.onSubscribe});

  @override
  Widget build(BuildContext context) {
    final highlighted = plan['highlighted'] as bool;
    final badge = plan['badge'] as String;
    final buttonEnabled = plan['buttonEnabled'] as bool;
    final features = plan['features'] as List<Map<String, dynamic>>;
    final price = isYearly
        ? plan['yearlyPrice'] as String
        : plan['monthlyPrice'] as String;

    final card = Container(
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
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: 0.14),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan['name'] as String,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: highlighted ? AppColors.secondary : AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            plan['tagline'] as String,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            price,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: highlighted ? AppColors.secondary : AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(color: Color(0xFFE8F5EE)),
          const SizedBox(height: AppSpacing.sm),
          ...features.map(
            (f) => _FeatureRow(
              label: f['label'] as String,
              included: f['included'] as bool,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: buttonEnabled
                ? ElevatedButton(
                    onPressed: onSubscribe,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: highlighted
                          ? AppColors.secondary
                          : AppColors.primary,
                      foregroundColor:
                          highlighted ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md),
                      shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.mdAll),
                      textStyle: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    child: Text(plan['buttonLabel'] as String),
                  )
                : OutlinedButton(
                    onPressed: null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey,
                      disabledForegroundColor: Colors.grey,
                      side: const BorderSide(color: Color(0xFFCCCCCC)),
                      padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md),
                      shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.mdAll),
                      textStyle: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    child: Text(plan['buttonLabel'] as String),
                  ),
          ),
        ],
      ),
    );

    if (badge.isEmpty) return card;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          top: -10,
          right: AppSpacing.md,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: AppRadius.smAll,
              boxShadow: [
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              badge,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String label;
  final bool included;

  const _FeatureRow({required this.label, required this.included});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            included ? Icons.check_circle : Icons.cancel,
            size: 18,
            color: included
                ? const Color(0xFF2E7D32)
                : const Color(0xFFBDBDBD),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: included ? Colors.black87 : Colors.black38,
                fontWeight:
                    included ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section 4 — Comparison Table ─────────────────────────────────────────────

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final rows = l.comparisonRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.comparePlans,
          style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black87),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: const Color(0xFFDEEAE5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: AppRadius.lgAll,
            child: Column(
              children: [
                // header
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  color: const Color(0xFFF0F7F4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          l.featureHeader,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary),
                        ),
                      ),
                      const Expanded(
                        flex: 2,
                        child: Center(
                          child: Text('Free',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black54)),
                        ),
                      ),
                      const Expanded(
                        flex: 2,
                        child: Center(
                          child: Text('Pro',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.secondary)),
                        ),
                      ),
                      const Expanded(
                        flex: 2,
                        child: Center(
                          child: Text('Research',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary)),
                        ),
                      ),
                    ],
                  ),
                ),
                // data rows
                ...List.generate(rows.length, (i) {
                  final row = rows[i];
                  return Container(
                    color: i.isOdd
                        ? const Color(0xFFFAFDFB)
                        : Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(row[0],
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w500)),
                        ),
                        Expanded(
                            flex: 2,
                            child: Center(child: _TableCell(row[1]))),
                        Expanded(
                            flex: 2,
                            child: Center(child: _TableCell(row[2]))),
                        Expanded(
                            flex: 2,
                            child: Center(child: _TableCell(row[3]))),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TableCell extends StatelessWidget {
  final String value;
  const _TableCell(this.value);

  @override
  Widget build(BuildContext context) {
    if (value == '✓') {
      return const Icon(Icons.check_circle,
          size: 16, color: Color(0xFF2E7D32));
    }
    if (value == '✗') {
      return const Icon(Icons.cancel, size: 16, color: Color(0xFFBDBDBD));
    }
    return Text(value,
        style: const TextStyle(fontSize: 11, color: Colors.black54),
        textAlign: TextAlign.center);
  }
}

// ── Section 5 — Payment Note ──────────────────────────────────────────────────

class _PaymentNote extends StatelessWidget {
  const _PaymentNote();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 14, color: Colors.black38),
            const SizedBox(width: AppSpacing.xs),
            Text(l.paymentsSecured,
                style:
                    const TextStyle(fontSize: 12, color: Colors.black38)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l.cancelAnytime,
          style: const TextStyle(fontSize: 12, color: Colors.black38),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ── Section 6 — FAQ ───────────────────────────────────────────────────────────

class _FAQSection extends StatelessWidget {
  const _FAQSection();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final faqs = [
      (q: l.faq1Q, a: l.faq1A),
      (q: l.faq2Q, a: l.faq2A),
      (q: l.faq3Q, a: l.faq3A),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.commonQuestions,
          style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black87),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: const Color(0xFFDEEAE5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: List.generate(faqs.length, (i) {
              final faq = faqs[i];
              return Column(
                children: [
                  Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                      title: Row(
                        children: [
                          const Icon(Icons.help_outline,
                              size: 16, color: AppColors.primary),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              faq.q,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                      iconColor: AppColors.primary,
                      collapsedIconColor: Colors.black38,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              AppSpacing.xl + AppSpacing.sm,
                              0,
                              AppSpacing.md,
                              AppSpacing.md),
                          child: Text(
                            faq.a,
                            style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black54,
                                height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (i < faqs.length - 1)
                    const Divider(height: 1, color: Color(0xFFDEEAE5)),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}
