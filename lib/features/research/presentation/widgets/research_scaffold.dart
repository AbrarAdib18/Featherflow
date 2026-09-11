import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/services/research_session.dart';
import '../research_theme.dart';
import 'research_sidebar.dart';

class ResearchScaffold extends StatelessWidget {
  final String title;
  final ResearchModule module;
  final Widget child;
  final List<Widget>? appBarActions;
  final Widget? floatingActionButton;

  const ResearchScaffold({
    super.key,
    required this.title,
    required this.module,
    required this.child,
    this.appBarActions,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= kResearchBreakpointWide) {
          return _WideLayout(
            title: title,
            module: module,
            appBarActions: appBarActions,
            floatingActionButton: floatingActionButton,
            child: child,
          );
        }
        return _NarrowLayout(
          title: title,
          module: module,
          appBarActions: appBarActions,
          floatingActionButton: floatingActionButton,
          child: child,
        );
      },
    );
  }
}

class _WideLayout extends StatelessWidget {
  final String title;
  final ResearchModule module;
  final Widget child;
  final List<Widget>? appBarActions;
  final Widget? floatingActionButton;

  const _WideLayout({
    required this.title,
    required this.module,
    required this.child,
    this.appBarActions,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RColors.bg,
      floatingActionButton: floatingActionButton,
      body: Row(
        children: [
          SizedBox(
            width: kResearchSidebarWidth,
            child: ResearchSidebar(selectedModule: module),
          ),
          const VerticalDivider(width: 1, color: RColors.divider),
          Expanded(
            child: Column(
              children: [
                _TopBar(title: title, actions: appBarActions),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NarrowLayout extends StatelessWidget {
  final String title;
  final ResearchModule module;
  final Widget child;
  final List<Widget>? appBarActions;
  final Widget? floatingActionButton;

  const _NarrowLayout({
    required this.title,
    required this.module,
    required this.child,
    this.appBarActions,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final isRoot =
        GoRouterState.of(context).matchedLocation == '/research';
    return Scaffold(
      backgroundColor: RColors.bg,
      floatingActionButton: floatingActionButton,
      appBar: AppBar(
        backgroundColor: RColors.navigationSurface,
        foregroundColor: RColors.navigationForegroundColor,
        automaticallyImplyLeading: isRoot,
        leading: isRoot
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: RColors.navigationIconColor, size: 18),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/research');
                  }
                },
              ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (appBarActions != null) ...appBarActions!,
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: _ProfileAvatar(small: true),
          ),
        ],
      ),
      drawer: isRoot
          ? Drawer(
              backgroundColor: RColors.bg,
              child: ResearchSidebar(selectedModule: module),
            )
          : null,
      body: child,
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final List<Widget>? actions;

  const _TopBar({required this.title, this.actions});

  @override
  Widget build(BuildContext context) {
    final isRoot =
        GoRouterState.of(context).matchedLocation == '/research';
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: RColors.bg,
        border: Border(bottom: BorderSide(color: RColors.divider)),
      ),
      child: Row(
        children: [
          if (!isRoot) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: RColors.textSecondary, size: 18),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/research');
                }
              },
              tooltip: 'Back',
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 4),
          ] else
            const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: RColors.textPrimary,
            ),
          ),
          const Spacer(),
          if (actions != null) ...actions!,
          const SizedBox(width: 16),
          const _ProfileAvatar(small: false),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final bool small;
  const _ProfileAvatar({required this.small});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ResearchSession.instance,
      builder: (context, _) {
        final profile = ResearchSession.instance.profile;
        return _build(context, profile);
      },
    );
  }

  Widget _build(BuildContext context, dynamic profile) {
    if (small) {
      // Rendered in the green narrow-layout app bar → white on white-tint.
      return CircleAvatar(
        radius: 15,
        backgroundColor: RColors.navigationHoverColor,
        child: Text(
          profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'R',
          style: const TextStyle(
            color: RColors.navigationForegroundColor,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              profile.name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: RColors.textPrimary,
              ),
            ),
            Text(
              profile.specialty,
              style: const TextStyle(
                fontSize: 11,
                color: RColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        const SizedBox(width: 10),
        CircleAvatar(
          radius: 17,
          backgroundColor: RColors.secondary.withValues(alpha: 0.2),
          child: Text(
            profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'R',
            style: const TextStyle(
              color: RColors.secondary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
