import 'package:flutter/material.dart';

import '../../data/services/pharmacy_appeal_service.dart';
import '../pharmacy_theme.dart';

/// Suspension appeal form + history (spec §9). Reachable while suspended —
/// the backend endpoint uses PharmacyAlwaysOnAuthentication.
class PharmacyAppealScreen extends StatefulWidget {
  const PharmacyAppealScreen({super.key});

  @override
  State<PharmacyAppealScreen> createState() => _PharmacyAppealScreenState();
}

class _PharmacyAppealScreenState extends State<PharmacyAppealScreen> {
  final _api = PharmacyAppealService.instance;
  final _explanationController = TextEditingController();
  String _reason = kSuspensionReasons.first;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<Map<String, dynamic>> _appeals = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _explanationController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _appeals = await _api.list();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hasOpenAppeal => _appeals.any(
      (a) => ['submitted', 'under_review', 'more_info_required'].contains(a['status']));

  Future<void> _submit() async {
    final explanation = _explanationController.text.trim();
    if (explanation.isEmpty) {
      showPharmacyNotice(context, 'Please explain your appeal.', PhColors.red, Icons.error_outline);
      return;
    }
    setState(() => _submitting = true);
    try {
      await _api.submit(reason: _reason, explanation: explanation);
      _explanationController.clear();
      await _load();
      if (mounted) {
        showPharmacyNotice(context, 'Appeal submitted.', PhColors.secondary, Icons.check_circle_outline);
      }
    } catch (e) {
      if (mounted) showPharmacyNotice(context, '$e', PhColors.red, Icons.error_outline);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Color _statusColor(String status) => switch (status) {
        'approved' => PhColors.secondary,
        'denied' => PhColors.red,
        'more_info_required' => PhColors.amber,
        _ => PhColors.processing,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PhColors.bg,
      appBar: AppBar(
        backgroundColor: PhColors.appBar,
        foregroundColor: Colors.white,
        title: const Text('Suspension Appeal'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: phCard(borderColor: PhColors.red),
                      child: Text(_error!, style: const TextStyle(color: PhColors.red)),
                    ),
                  if (_appeals.isNotEmpty) ...[
                    const Text('Your appeals',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: PhColors.textPrimary)),
                    const SizedBox(height: 8),
                    ..._appeals.map((a) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: phCard(),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              phChip((a['status'] ?? '').toString().replaceAll('_', ' '),
                                  _statusColor(a['status']?.toString() ?? '').withValues(alpha: 0.12),
                                  _statusColor(a['status']?.toString() ?? '')),
                              const Spacer(),
                              Text(suspensionReasonLabel(a['reason']?.toString() ?? ''),
                                  style: const TextStyle(fontSize: 12, color: PhColors.textSecondary)),
                            ]),
                            const SizedBox(height: 6),
                            Text((a['explanation'] ?? '').toString(), style: phFieldText),
                            if ((a['admin_response'] ?? '').toString().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('Admin: ${a['admin_response']}',
                                  style: const TextStyle(fontSize: 12, color: PhColors.textSecondary, fontStyle: FontStyle.italic)),
                            ],
                          ]),
                        )),
                    const SizedBox(height: 16),
                  ],
                  if (!_hasOpenAppeal) ...[
                    const Text('Submit an appeal',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: PhColors.textPrimary)),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _reason,
                      decoration: phInput('Reason', Icons.list_alt_outlined),
                      items: kSuspensionReasons
                          .map((r) => DropdownMenuItem(value: r, child: Text(suspensionReasonLabel(r))))
                          .toList(),
                      onChanged: (v) => setState(() => _reason = v ?? _reason),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _explanationController,
                      decoration: phInput('Explanation', Icons.notes_outlined),
                      minLines: 3,
                      maxLines: 6,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Submit appeal'),
                    ),
                  ] else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: phCard(),
                      child: const Text(
                        'You have an appeal currently under review. You will be notified once '
                        'Pharmacy Admin responds.',
                        style: phFieldText,
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
