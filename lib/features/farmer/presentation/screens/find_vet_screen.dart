import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/theme.dart';
import '../widgets/discover_vets_tab.dart';
import 'farmer_consultations_screen.dart';

/// The unified "Find Vet" feature: replaces the previously separate
/// "Find Vet" (vet map) and "My Consultations" dashboard tiles with one entry
/// point. Ratings & reviews are shown inline inside each consultation card
/// rather than as a separate tab — see CONSULTATION_INTEGRATION_AUDIT.md.
///
/// The three tabs are flat. Consultations and Chats used to live behind a
/// second [TabBar] owned by [FarmerConsultationsScreen], which stacked two
/// identically coloured green strips on top of each other and read as a
/// duplicated navigation bar.
class FindVetScreen extends StatefulWidget {
  const FindVetScreen({super.key, this.initialTab = 0, this.diseaseContext});

  /// 0 = Discover Vets, 1 = Consultations, 2 = Chats.
  final int initialTab;
  final String? diseaseContext;

  static const int tabCount = 3;

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
      length: FindVetScreen.tabCount,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, FindVetScreen.tabCount - 1),
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  /// `GoRouterState.of` throws when this screen is built outside a router
  /// (tests, previews), so the query fallback is best-effort only.
  String? _diseaseFromRoute(BuildContext context) {
    try {
      return GoRouterState.of(context).uri.queryParameters['disease'];
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final diseaseContext = widget.diseaseContext ?? _diseaseFromRoute(context);
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
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Discover Vets'),
            Tab(text: 'Consultations'),
            Tab(text: 'Chats'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          DiscoverVetsTab(diseaseContext: diseaseContext),
          const FarmerConsultationsScreen(
              embedded: true, pane: ConsultationsPane.consultations),
          const FarmerConsultationsScreen(
              embedded: true, pane: ConsultationsPane.chats),
        ],
      ),
    );
  }
}
