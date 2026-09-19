import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/theme.dart';
import '../widgets/discover_vets_tab.dart';
import 'farmer_consultations_screen.dart';

/// The unified "Find Vet" feature: replaces the previously separate
/// "Find Vet" (vet map) and "My Consultations" dashboard tiles with one entry
/// point that holds Discover Vets and My Consultations as tabs. Ratings &
/// reviews are shown inline inside each consultation card in My Consultations
/// rather than as a third tab (per the integration spec's "optional, if not
/// shown inside My Consultations" allowance) — see
/// CONSULTATION_INTEGRATION_AUDIT.md.
class FindVetScreen extends StatefulWidget {
  const FindVetScreen({super.key, this.initialTab = 0, this.diseaseContext});

  /// 0 = Discover Vets, 1 = My Consultations.
  final int initialTab;
  final String? diseaseContext;

  @override
  State<FindVetScreen> createState() => _FindVetScreenState();
}

class _FindVetScreenState extends State<FindVetScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diseaseContext = widget.diseaseContext ??
        GoRouterState.of(context).uri.queryParameters['disease'];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/farmer'),
        ),
        title: const Text('Find Vet'),
        actions: [
          IconButton(
              icon: const Icon(Icons.home_outlined),
              onPressed: () => context.go('/farmer')),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Discover Vets'),
            Tab(text: 'My Consultations'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          DiscoverVetsTab(diseaseContext: diseaseContext),
          const FarmerConsultationsScreen(embedded: true),
        ],
      ),
    );
  }
}
