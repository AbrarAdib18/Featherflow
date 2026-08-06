import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/admin_session.dart';
import '../admin_theme.dart';
import 'admin_sidebar.dart';

class AdminScaffold extends StatelessWidget {
  final String title;
  final AdminModule module;
  final Widget child;
  final List<Widget>? appBarActions;
  final Widget? floatingActionButton;

  const AdminScaffold({
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
        if (constraints.maxWidth >= kBreakpointWide) {
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

// ── Wide (≥900 px) — persistent sidebar ──────────────────────────────────────

class _WideLayout extends StatelessWidget {
  final String title;
  final AdminModule module;
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
      backgroundColor: AColors.bg,
      floatingActionButton: floatingActionButton,
      body: Row(
        children: [
          SizedBox(
            width: kSidebarWidth,
            child: AdminSidebar(selectedModule: module),
          ),
          const VerticalDivider(width: 1, color: AColors.divider),
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

// ── Narrow (< 900 px) — drawer nav ───────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  final String title;
  final AdminModule module;
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
    final isRoot = GoRouterState.of(context).matchedLocation == '/admin';
    return Scaffold(
      backgroundColor: AColors.bg,
      floatingActionButton: floatingActionButton,
      appBar: AppBar(
        backgroundColor: AColors.appBar,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: isRoot,
        leading: isRoot
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 18),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/admin');
                  }
                },
              ),
        title: Text(title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          if (appBarActions != null) ...appBarActions!,
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ListenableBuilder(
              listenable: AdminSession.instance,
              builder: (_, __) => CircleAvatar(
                radius: 15,
                backgroundColor: AColors.secondary.withValues(alpha: 0.25),
                child: Text(
                  AdminSession.instance.name.isNotEmpty
                      ? AdminSession.instance.name[0].toUpperCase()
                      : 'A',
                  style: const TextStyle(
                      color: AColors.secondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
      drawer: isRoot
          ? Drawer(
              backgroundColor: AColors.bg,
              child: AdminSidebar(selectedModule: module),
            )
          : null,
      body: child,
    );
  }
}

// ── Top bar for wide layout ───────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final List<Widget>? actions;

  const _TopBar({required this.title, this.actions});

  @override
  Widget build(BuildContext context) {
    final isRoot = GoRouterState.of(context).matchedLocation == '/admin';
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AColors.bg,
        border: Border(bottom: BorderSide(color: AColors.divider)),
      ),
      child: Row(
        children: [
          if (!isRoot) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: AColors.textSecondary, size: 18),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/admin');
                }
              },
              tooltip: 'Back',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 4),
          ] else
            const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AColors.textPrimary),
          ),
          const Spacer(),
          if (actions != null) ...actions!,
          const SizedBox(width: 16),
          ListenableBuilder(
            listenable: AdminSession.instance,
            builder: (_, __) {
              final s = AdminSession.instance;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(s.name,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AColors.textPrimary)),
                      Text(s.roleDisplayName,
                          style: const TextStyle(
                              fontSize: 11, color: AColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(width: 10),
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: AColors.secondary.withValues(alpha: 0.2),
                    child: Text(
                      s.name.isNotEmpty ? s.name[0].toUpperCase() : 'A',
                      style: const TextStyle(
                          color: AColors.secondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
