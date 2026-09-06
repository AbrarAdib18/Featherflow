import 'package:flutter/material.dart';

import '../../data/models/admin_role.dart';
import '../../data/models/audit_log.dart';
import '../../data/services/admin_session.dart';
import '../../data/services/audit_service.dart';
import '../admin_theme.dart';

/// Per-module audit trail — opened from a module screen's app bar. Shows the
/// recent `activity_logs` rows scoped to that module (one or more backend module
/// slugs). Only visible to admins with the `audit:view` permission.
Future<void> showModuleActivity(
  BuildContext context, {
  required String title,
  required List<String> modules,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AColors.bg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.8,
      child: _ModuleActivitySheet(title: title, modules: modules),
    ),
  );
}

/// App-bar button — renders nothing if the caller can't view the audit trail.
class ModuleActivityButton extends StatelessWidget {
  final String title;
  final List<String> modules;
  const ModuleActivityButton({
    super.key,
    required this.title,
    required this.modules,
  });

  @override
  Widget build(BuildContext context) {
    if (!AdminSession.instance.can(AdminModule.auditTrail, AdminPermission.view)) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: 'Module activity',
      icon: const Icon(Icons.history, size: 20),
      onPressed: () => showModuleActivity(context, title: title, modules: modules),
    );
  }
}

class _ModuleActivitySheet extends StatefulWidget {
  final String title;
  final List<String> modules;
  const _ModuleActivitySheet({required this.title, required this.modules});

  @override
  State<_ModuleActivitySheet> createState() => _ModuleActivitySheetState();
}

class _ModuleActivitySheetState extends State<_ModuleActivitySheet> {
  final _entries = <AuditEntry>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = <AuditEntry>[];
      for (final m in widget.modules) {
        final result =
            await AuditService.instance.fetch(filters: {'module': m}, limit: 40);
        all.addAll(result.entries);
      }
      all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(all.take(60));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.history, size: 18, color: AColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${widget.title} · activity',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AColors.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AColors.divider),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AColors.secondary))
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AColors.textSecondary)),
                      ),
                    )
                  : _entries.isEmpty
                      ? const Center(
                          child: Text('No recorded activity for this module yet.',
                              style: TextStyle(color: AColors.textSecondary)))
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _entries.length,
                          separatorBuilder: (_, __) => const Divider(height: 14),
                          itemBuilder: (_, i) {
                            final e = _entries[i];
                            final ts = e.timestamp.toLocal();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (e.actionType.isNotEmpty)
                                      aChip(e.actionType, AColors.blue, AColors.blue, fontSize: 10),
                                    const Spacer(),
                                    Text(
                                      '${ts.month}/${ts.day} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}',
                                      style: const TextStyle(fontSize: 10, color: AColors.grey),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(e.action,
                                    style: const TextStyle(
                                        fontSize: 12.5, fontWeight: FontWeight.w600, color: AColors.textPrimary)),
                                Text(
                                  e.actorName + (e.reason.isNotEmpty ? ' — ${e.reason}' : ''),
                                  style: const TextStyle(fontSize: 11, color: AColors.textSecondary),
                                ),
                              ],
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
