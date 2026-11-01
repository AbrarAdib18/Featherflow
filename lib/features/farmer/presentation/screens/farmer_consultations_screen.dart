import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/chat/chat_core.dart';
import '../../../../core/chat/chat_widgets.dart';
import '../../../../core/documents/prescription_pdf_viewer.dart';
import '../../../../core/format/currency.dart';
import '../../../../core/network/auth_service.dart';
import '../../../../core/network/realtime_chat_service.dart';
import '../../../../core/theme/theme.dart';
import '../../data/farmer_consultation_service.dart';

/// Which half of this screen to render. When embedded in [FindVetScreen] the
/// parent owns the tab strip and asks for one pane at a time; standalone, both
/// panes render behind this screen's own [TabBar].
enum ConsultationsPane { both, consultations, chats }

class FarmerConsultationsScreen extends StatefulWidget {
  /// When true (used inside the unified "Find Vet" tabs), this renders without
  /// its own [Scaffold]/[AppBar] *and* without its own tab strip — the parent
  /// supplies both. Rendering an inner strip here stacked a second green bar
  /// directly under the parent's and read as a duplicated navigation bar.
  const FarmerConsultationsScreen({
    super.key,
    this.embedded = false,
    this.pane = ConsultationsPane.both,
  });

  final bool embedded;
  final ConsultationsPane pane;

  @override
  State<FarmerConsultationsScreen> createState() =>
      _FarmerConsultationsScreenState();
}

class _FarmerConsultationsScreenState extends State<FarmerConsultationsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tab;
  List<Map<String, dynamic>> _items = [], _chats = [];
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;
  bool _refreshingSilently = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _load();
    // Farmer consultation + chat data refreshes every 8 seconds (per the
    // Find Vet / doctor-farmer workflow integration spec, §8) — separate
    // from the 3s farmer notification-count poll on the dashboard.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _silentRefresh(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _tab.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _silentRefresh();
  }

  Future<void> _silentRefresh() async {
    if (_refreshingSilently || !mounted) return;
    _refreshingSilently = true;
    try {
      final data = await Future.wait([
        FarmerConsultationService.list(),
        FarmerConsultationService.chats(),
      ]);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(
            (data[0]['consultations'] as List? ?? [])
                .map((x) => Map<String, dynamic>.from(x as Map)));
        _chats = List<Map<String, dynamic>>.from(
            (data[1]['conversations'] as List? ?? [])
                .map((x) => Map<String, dynamic>.from(x as Map)));
      });
    } catch (_) {
      // Visible data remains usable; the next refresh retries.
    } finally {
      _refreshingSilently = false;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Future.wait([
        FarmerConsultationService.list(),
        FarmerConsultationService.chats(),
      ]);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(
            (data[0]['consultations'] as List? ?? [])
                .map((x) => Map<String, dynamic>.from(x as Map)));
        _chats = List<Map<String, dynamic>>.from(
            (data[1]['conversations'] as List? ?? [])
                .map((x) => Map<String, dynamic>.from(x as Map)));
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Loading / error gate shared by every pane, so a failed fetch shows a
  /// retry rather than an empty list that reads like "you have nothing".
  Widget _gated(Widget Function() content) => _loading
      ? const Center(child: CircularProgressIndicator())
      : _error != null
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_error!),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ]))
          : content();

  Widget _body() => _gated(
      () => TabBarView(controller: _tab, children: [_consultations(), _chatList()]));

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      // The parent (FindVetScreen) owns the AppBar, Scaffold *and* the tab
      // strip — this renders only the requested pane.
      switch (widget.pane) {
        case ConsultationsPane.consultations:
          return _gated(_consultations);
        case ConsultationsPane.chats:
          return _gated(_chatList);
        case ConsultationsPane.both:
          return _body();
      }
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/farmer')),
        title: const Text('My Consultations'),
        actions: [
          IconButton(
              icon: const Icon(Icons.home_outlined),
              onPressed: () => context.go('/farmer')),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [Tab(text: 'Consultations'), Tab(text: 'Chats')],
        ),
      ),
      body: _body(),
    );
  }

  Widget _consultations() => RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_items.isEmpty)
            const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: Text('No consultation requests yet.'))),
          ..._items.map(_consultationCard),
        ]),
      );

  Widget _consultationCard(Map<String, dynamic> item) {
    final status = '${item['status']}';
    final caseData = item['case'] is Map
        ? Map<String, dynamic>.from(item['case'] as Map)
        : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Row(children: [
                const Icon(Icons.medical_services_outlined,
                    size: 16, color: AppColors.hint),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('${item['doctor_name']}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
            Chip(
                label: Text(status.replaceAll('_', ' ')),
                visualDensity: VisualDensity.compact),
          ]),
          const SizedBox(height: 8),
          Text(
              '${item['date']} at ${item['time']} • ${item['mode']} • ${item['urgency']}'),
          if (caseData != null)
            Text(
                '${caseData['farm_name']} • ${caseData['breed']} • ${caseData['flock_count']} birds',
                style: const TextStyle(color: AppColors.hint)),
          if (item['decision_reason'] != null)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Doctor note: ${item['decision_reason']}')),
          if (status == 'reschedule_proposed') ...[
            const Divider(),
            Text(
                'Proposed: ${item['proposed_date']} at ${item['proposed_time']}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => _act(item, 'decline_reschedule'),
                      child: const Text('Decline'))),
              const SizedBox(width: 8),
              Expanded(
                  child: ElevatedButton(
                      onPressed: () => _act(item, 'accept_reschedule'),
                      child: const Text('Accept new time'))),
            ]),
          ],
          if (status == 'requested' || status == 'accepted')
            Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => _act(item, 'cancel'),
                    child: const Text('Cancel request'))),
          if (item['conversation_id'] != null)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _openChatFor(item),
                icon: const Icon(Icons.chat),
                label: Text(status == 'completed'
                    ? 'Post-consultation chat'
                    : 'Open chat'),
              ),
            ),
          if ((item['video'] as Map?)?['active'] == true)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => _joinVideo(item),
                icon: const Icon(Icons.videocam),
                label: const Text('Join video call'),
              ),
            ),
          if (status == 'completed')
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _raiseDispute(item),
                icon: const Icon(Icons.flag_outlined, size: 16),
                label: Text(((item['disputes'] as List?) ?? const []).isEmpty
                    ? 'Raise a dispute'
                    : 'Disputes (${(item['disputes'] as List).length})'),
              ),
            ),
          if (item['clinical_results_available'] == true)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _viewClinicalResults('${item['id']}'),
                icon: const Icon(Icons.medical_information_outlined),
                label: const Text('View clinical results'),
              ),
            ),
          if (item['payment_receipt_available'] == true)
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _viewReceipt('${item['id']}'),
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(item['payment_receipt']?['status'] == 'completed'
                    ? 'View paid receipt'
                    : 'View payment receipt'),
              ),
            ),
          if (status == 'completed' && item['rating'] == null)
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _rate(item),
                icon: const Icon(Icons.star_outline),
                label: const Text('Rate consultation'),
              ),
            ),
          if (item['rating'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    ...List.generate(
                      5,
                      (index) => Icon(
                        index < (item['rating'] as num).toInt()
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: const Color(0xFFFFB300),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('${item['rating']}/5'),
                  ]),
                  if ('${item['review'] ?? ''}'.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('“${item['review']}”'),
                    ),
                ],
              ),
            ),
          ...((item['prescriptions'] as List?) ?? const []).map((value) {
            final prescription = Map<String, dynamic>.from(value as Map);
            return _prescriptionCard(prescription);
          }),
          ...((item['follow_ups'] as List?) ?? const []).map((value) {
            final followUp = Map<String, dynamic>.from(value as Map);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_repeat, color: AppColors.primary),
              title: Text(
                  'Follow-up: ${followUp['scheduled_date']} at ${followUp['scheduled_time'] ?? 'time pending'}'),
              subtitle: Text('${followUp['notes'] ?? ''}'),
              trailing: Chip(label: Text('${followUp['status']}')),
            );
          }),
        ]),
      ),
    );
  }

  Widget _prescriptionCard(Map<String, dynamic> prescription) {
    final reference = prescription['reference_number']?.toString();
    final issued = ChatTime.parseServer(prescription['issued_at'] ?? prescription['created_at']);
    final (IconData deliveryIcon, String delivery) = switch ('${prescription['email_status'] ?? ''}') {
      'sent' => (Icons.mark_email_read_outlined, 'A PDF copy was emailed to your registered address.'),
      'failed' => (Icons.info_outline, 'We could not email the PDF yet; it is always available here.'),
      _ => (Icons.schedule_send_outlined, 'The PDF email is on its way. It is also available here.'),
    };
    return Container(
      key: Key('farmerPrescription_${prescription['id']}'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: .2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.medication_outlined, color: AppColors.primary),
          SizedBox(width: 8),
          Expanded(
            child: Text('Prescription & case advice',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          [
            if (prescription['doctor_name'] != null) '${prescription['doctor_name']}',
            if (issued != null) DateFormat('d MMM yyyy, h:mm a').format(issued),
            if (reference != null) reference,
          ].join(' · '),
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        ...((prescription['medicines'] as List?) ?? const []).map((value) {
          final medicine = Map<String, dynamic>.from(value as Map);
          final notes = '${medicine['notes'] ?? ''}'.trim();
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
                '• ${medicine['name']} — ${medicine['dosage']} for ${medicine['duration']}'
                '${notes.isEmpty ? '' : '\n  $notes'}'),
          );
        }),
        if ('${prescription['case_advice'] ?? ''}'.isNotEmpty)
          Text('Advice: ${prescription['case_advice']}'),
        if ('${prescription['dosage_notes'] ?? ''}'.isNotEmpty)
          Text('Dosage notes: ${prescription['dosage_notes']}'),
        if ('${prescription['follow_up_instructions'] ?? ''}'.isNotEmpty)
          Text('Follow-up: ${prescription['follow_up_instructions']}'),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(deliveryIcon, size: 16, color: AppColors.hint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(delivery,
                key: const Key('farmerPrescriptionDelivery'),
                style: const TextStyle(color: AppColors.hint, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('farmerViewPrescriptionPdf'),
          onPressed: () => _viewPrescriptionPdf('${prescription['id']}', reference: reference),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('View prescription PDF'),
        ),
      ]),
    );
  }

  /// Full-screen viewer (view / print / share); errors show in the viewer
  /// with Retry instead of a passing snackbar.
  Future<void> _viewPrescriptionPdf(String prescriptionId, {String? reference}) =>
      showPrescriptionPdf(context, prescriptionId: prescriptionId, reference: reference);

  Future<void> _viewClinicalResults(String consultationId) async {
    try {
      final result =
          await FarmerConsultationService.clinicalResults(consultationId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _ClinicalResultsDialog(
          result: result,
          onViewPdf: _viewPrescriptionPdf,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _viewReceipt(String consultationId) async {
    try {
      final receipt = await FarmerConsultationService.receipt(consultationId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _PaymentReceiptDialog(
          initialReceipt: receipt,
          onMarkPaid: () => FarmerConsultationService.markPaid(consultationId),
        ),
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _act(Map<String, dynamic> item, String action) async {
    try {
      await FarmerConsultationService.action('${item['id']}', action);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _joinVideo(Map<String, dynamic> item) async {
    try {
      final room = await FarmerConsultationService.videoRoom('${item['id']}');
      final url = '${room['room_url']}';
      if (room['active'] != true || url.isEmpty || url == 'null') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('The video call has not started yet.')));
        }
        return;
      }
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  static const _disputeCategories = <String, String>{
    'no_show': 'Doctor did not show up',
    'quality_of_care': 'Quality of care',
    'payment': 'Payment disagreement',
    'conduct': 'Conduct / behaviour',
    'wrong_prescription': 'Wrong prescription',
    'other': 'Something else',
  };

  Future<void> _raiseDispute(Map<String, dynamic> item) async {
    var category = 'quality_of_care';
    final description = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Raise a dispute'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Issue'),
                items: _disputeCategories.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setDialogState(() => category = v ?? category),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'What happened? *',
                  hintText: 'The doctor admin will review this.',
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Submit')),
          ],
        ),
      ),
    );
    if (submit != true) return;
    if (description.text.trim().length < 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Describe the issue in at least 10 characters.')));
      }
      return;
    }
    try {
      await FarmerConsultationService.raiseDispute(
          '${item['id']}', category, description.text.trim());
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Dispute submitted. The doctor admin will review it.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _rate(Map<String, dynamic> item) async {
    var rating = 5;
    final review = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rate this consultation'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                initialValue: rating,
                decoration: const InputDecoration(labelText: 'Rating'),
                items: List.generate(
                    5,
                    (index) => DropdownMenuItem(
                        value: index + 1, child: Text('${index + 1} / 5'))),
                onChanged: (value) =>
                    setDialogState(() => rating = value ?? rating),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: review,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Review (optional)', alignLabelWithHint: true),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Submit')),
          ],
        ),
      ),
    );
    if (accepted == true) {
      try {
        await FarmerConsultationService.action('${item['id']}', 'rate',
            rating: rating, review: review.text.trim());
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }
    review.dispose();
  }

  Widget _chatList() => RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_chats.isEmpty)
            const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                    child: Text(
                        'Chats appear after a doctor accepts a consultation.'))),
          ..._chats.map((chat) {
            final messages = chat['messages'] as List? ?? [];
            final unread = (chat['unread_count'] as num? ?? 0).toInt();
            return ListTile(
              onTap: () => _openChat(chat),
              leading: const CircleAvatar(child: Icon(Icons.medical_services)),
              title: Text('${chat['participant_name']}'),
              subtitle: Text(messages.isEmpty
                  ? 'Start the conversation'
                  : '${messages.last['content']}'),
              trailing: unread > 0 ? Badge(label: Text('$unread')) : null,
            );
          }),
        ]),
      );

  /// Resolves and opens the conversation for [item] instead of silently doing
  /// nothing when it isn't already in the cached `_chats` list — that used to
  /// happen whenever `conversation_id` was set but the separately-fetched chat
  /// list hadn't caught up yet (e.g. right after a doctor accepts).
  Future<void> _openChatFor(Map<String, dynamic> item) async {
    final conversationId = item['conversation_id'];
    var matches = _chats.where((chat) => chat['id'] == conversationId);
    if (matches.isEmpty) {
      try {
        final data = await FarmerConsultationService.chats();
        final refreshed = List<Map<String, dynamic>>.from(
            (data['conversations'] as List? ?? [])
                .map((x) => Map<String, dynamic>.from(x as Map)));
        if (mounted) setState(() => _chats = refreshed);
        matches = refreshed.where((chat) => chat['id'] == conversationId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Could not open this chat: ${e.toString()}')));
        }
        return;
      }
    }
    if (matches.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'This chat could not be found. Pull to refresh and try again.')));
      }
      return;
    }
    await _openChat(matches.first);
  }

  Future<void> _openChat(Map<String, dynamic> chat) async {
    await showDialog(
        context: context, builder: (_) => FarmerChatDialog(chat: chat));
    await _load();
  }
}

class _PaymentReceiptDialog extends StatefulWidget {
  const _PaymentReceiptDialog({
    required this.initialReceipt,
    required this.onMarkPaid,
  });

  final Map<String, dynamic> initialReceipt;
  final Future<Map<String, dynamic>> Function() onMarkPaid;

  @override
  State<_PaymentReceiptDialog> createState() => _PaymentReceiptDialogState();
}

class _PaymentReceiptDialogState extends State<_PaymentReceiptDialog> {
  late Map<String, dynamic> _receipt;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _receipt = widget.initialReceipt;
  }

  @override
  Widget build(BuildContext context) {
    final paid = _receipt['status'] == 'completed';
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Consultation payment receipt',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
            const Divider(),
            _receiptLine('Receipt', _receipt['receipt_number']),
            _receiptLine('Doctor', _receipt['doctor_name']),
            _receiptLine('Farmer', _receipt['farmer_name']),
            _receiptLine('Consultation',
                '${_receipt['appointment_date']} at ${_receipt['appointment_time']}'),
            _receiptLine('Type',
                '${_receipt['consultation_mode']} • ${_receipt['urgency']}'),
            _receiptLine('Doctor consultation number',
                _receipt['doctor_handled_sequence']),
            const Divider(),
            _moneyLine('Cash amount', _receipt['gross_fee'], emphasized: true),
            _moneyLine('Platform charge', _receipt['platform_charge']),
            Text(
              'The platform charge is ${_receipt['platform_rate_percent']}% only on the portion above ${taka((_receipt['platform_threshold'] as num?) ?? 0)}. It is deducted from doctor earnings, not added to your cash amount.',
              style: const TextStyle(color: AppColors.hint, fontSize: 12),
            ),
            const SizedBox(height: 8),
            _moneyLine('Doctor net earnings', _receipt['doctor_net_amount']),
            const Divider(),
            Row(children: [
              Icon(paid ? Icons.verified : Icons.payments_outlined,
                  color: paid ? Colors.green : Colors.orange),
              const SizedBox(width: 8),
              Text(paid ? 'Cash payment recorded' : 'Awaiting cash payment',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            if (_receipt['paid_at'] != null)
              Text('Confirmed: ${_receipt['paid_at']}',
                  style: const TextStyle(color: AppColors.hint)),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: paid || _submitting ? null : _confirmPaid,
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(paid ? Icons.check : Icons.payments_outlined),
                label: Text(paid ? 'Paid' : 'I have paid cash'),
              ),
            ),
            if (!paid)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Press Paid only after handing the cash to the doctor. No online payment will be processed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.hint, fontSize: 12),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _confirmPaid() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm cash payment'),
        content: Text(
            'Confirm that you gave ${taka((_receipt['gross_fee'] as num?) ?? 0)} in cash to ${_receipt['doctor_name']}. This action records the payment.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm paid')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final updated = await widget.onMarkPaid();
      if (mounted) setState(() => _receipt = updated);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  static Widget _receiptLine(String label, Object? value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 155,
              child:
                  Text(label, style: const TextStyle(color: AppColors.hint))),
          Expanded(child: Text('${value ?? '-'}')),
        ]),
      );

  static Widget _moneyLine(String label, Object? value,
          {bool emphasized = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontWeight:
                          emphasized ? FontWeight.w800 : FontWeight.w500))),
          Text(taka((value as num?) ?? 0),
              style: TextStyle(
                  fontSize: emphasized ? 20 : 15, fontWeight: FontWeight.w800)),
        ]),
      );
}

class _ClinicalResultsDialog extends StatelessWidget {
  const _ClinicalResultsDialog({required this.result, required this.onViewPdf});

  final Map<String, dynamic> result;
  final Future<void> Function(String prescriptionId) onViewPdf;

  @override
  Widget build(BuildContext context) {
    final doctor = Map<String, dynamic>.from(
        result['doctor'] as Map? ?? const <String, dynamic>{});
    final caseData = Map<String, dynamic>.from(
        result['case'] as Map? ?? const <String, dynamic>{});
    final note = Map<String, dynamic>.from(
        result['clinical_note'] as Map? ?? const <String, dynamic>{});
    final prescriptions = (result['prescriptions'] as List? ?? const [])
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList();
    final followUps = (result['follow_ups'] as List? ?? const [])
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList();
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Clinical results'),
          leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close)),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                        child: Icon(Icons.medical_services_outlined)),
                    title: Text('${doctor['name'] ?? 'Veterinarian'}'),
                    subtitle: Text(
                        '${result['appointment_date']} at ${result['appointment_time']}'),
                    trailing: const Chip(label: Text('Completed')),
                  ),
                ),
                _resultSection('Poultry case', Icons.pets_outlined, [
                  _resultLine('Farm', caseData['farm_name']),
                  _resultLine('Breed', caseData['breed']),
                  _resultLine('Bird age', caseData['bird_age']),
                  _resultLine('Flock count', caseData['flock_count']),
                  _resultLine('Mortality', caseData['mortality_count']),
                  _resultLine('Symptoms',
                      (caseData['symptoms'] as List? ?? []).join(', ')),
                  _resultLine('Disease tags',
                      (caseData['disease_tags'] as List? ?? []).join(', ')),
                ]),
                _resultSection('Doctor findings', Icons.fact_check_outlined, [
                  _resultLine('Diagnosis', note['diagnosis'],
                      empty: 'Not recorded'),
                  _resultLine('Treatment plan', note['treatment_plan'],
                      empty: 'Not recorded'),
                  _resultLine('Warnings', note['warnings'], empty: 'None'),
                  _resultLine('Next steps', note['next_steps'], empty: 'None'),
                ]),
                if (prescriptions.isNotEmpty)
                  ...prescriptions.map((prescription) => _resultSection(
                        'Prescription & advice',
                        Icons.medication_outlined,
                        [
                          ...((prescription['medicines'] as List?) ?? const [])
                              .map((value) {
                            final medicine =
                                Map<String, dynamic>.from(value as Map);
                            return _resultLine('${medicine['name']}',
                                '${medicine['dosage']} for ${medicine['duration']}\n${medicine['notes'] ?? ''}');
                          }),
                          _resultLine(
                              'Case advice', prescription['case_advice']),
                          _resultLine(
                              'Dosage notes', prescription['dosage_notes']),
                          _resultLine('Follow-up instructions',
                              prescription['follow_up_instructions']),
                          _resultLine('Referral', prescription['referred_to']),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                Navigator.pop(context);
                                await onViewPdf('${prescription['id']}');
                              },
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text('View prescription PDF'),
                            ),
                          ),
                        ],
                      )),
                if (prescriptions.isEmpty)
                  _resultSection('Prescription', Icons.medication_outlined, [
                    const Text('The doctor has not issued a prescription yet.'),
                  ]),
                _resultSection('Follow-ups', Icons.event_repeat_outlined, [
                  if (followUps.isEmpty)
                    const Text('No follow-up has been scheduled.'),
                  ...followUps.map((followUp) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            '${followUp['scheduled_date']} at ${followUp['scheduled_time'] ?? 'time pending'}'),
                        subtitle: Text('${followUp['notes'] ?? ''}'),
                        trailing: Chip(label: Text('${followUp['status']}')),
                      )),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _resultSection(
          String title, IconData icon, List<Widget> children) =>
      Card(
        margin: const EdgeInsets.only(top: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
            ]),
            const Divider(),
            ...children,
          ]),
        ),
      );

  static Widget _resultLine(String label, Object? value,
      {String empty = 'Not provided'}) {
    final text = value?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.hint, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        SelectableText(text.isEmpty || text == 'null' ? empty : text),
      ]),
    );
  }
}

/// The farmer's chat with a vet (opened from My Consultations and from
/// Find Vet -> Chats).
class FarmerChatDialog extends StatefulWidget {
  const FarmerChatDialog({super.key, required this.chat, this.realtime});
  final Map<String, dynamic> chat;

  /// Test seam: a stand-in for the live socket. Defaults to a real one.
  @visibleForTesting
  final RealtimeChatService? realtime;
  @override
  State<FarmerChatDialog> createState() => _RealtimeChatDialogState();
}

class _RealtimeChatDialogState extends State<FarmerChatDialog> {
  final _text = TextEditingController();
  late final RealtimeChatService _realtime =
      widget.realtime ?? RealtimeChatService();
  final _scroll = ScrollController();
  // Ordered + de-duplicated through ChatTimeline (server id AND the echoed
  // client_message_id), so the optimistic bubble, REST response, Socket.IO
  // echo and poll can arrive in any order and still render one bubble.
  // See CHAT_MESSAGE_STATE_FIX.md.
  late List<ChatEntry> _messages;
  final Set<String> _inFlight = {};
  Timer? _poll;
  // A live-connection notice, distinct from a send failure: chat still works
  // over REST (see _send) with or without it, so this is informational, not
  // blocking — mirrors the doctor side's DoctorSession.sendMessage, which
  // already treats the socket as an optional echo layer, not the send path.
  String? _connectionNotice;

  String? get _me => AuthService.instance.currentSession?.user.id;
  String get _conversationId => '${widget.chat['id']}';
  bool get _sending => _inFlight.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _messages = ChatTimeline.mergePage(
        <ChatEntry>[],
        (widget.chat['messages'] as List? ?? []).map((x) => ChatEntry.fromServer(
            Map<String, dynamic>.from(x as Map),
            myUserId: _me)));
    _realtime.onMessage = (message) {
      if (message['conversation_id'] != widget.chat['id'] || !mounted) return;
      // Upsert, never append: this may be the echo of our own send arriving
      // before its REST response (matched by client_message_id).
      setState(() => _messages = ChatTimeline.upsert(
          _messages, ChatEntry.fromServer(message, myUserId: _me)));
    };
    _realtime.onError = (value) {
      // A failed/unavailable real-time connection (e.g. the backend is
      // running `manage.py runserver`, which serves REST but not
      // Socket.IO — see DATABASE_SETUP.md §5) never blocks sending or
      // reading messages; replies still arrive through the 4s poll below.
      if (mounted) {
        setState(() => _connectionNotice =
            'Live updates are unavailable right now — messages still send, '
            'and new replies appear within a few seconds.');
      }
    };
    _realtime
        .connect(_conversationId)
        .then((_) => _realtime.markRead(_conversationId))
        .catchError((_) {
      // connect() itself can throw (e.g. no session); treated the same as
      // onError above — informational only, chat still works over REST.
      if (mounted) {
        setState(() => _connectionNotice =
            'Live updates are unavailable right now — messages still send, '
            'and new replies appear within a few seconds.');
      }
    });
    // The dialog used to show only the snapshot it opened with plus socket
    // events; replies now also arrive by polling the authoritative list.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _realtime.disconnect();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final data = await FarmerConsultationService.chats();
      if (!mounted) return;
      final row = (data['conversations'] as List? ?? [])
          .map((x) => Map<String, dynamic>.from(x as Map))
          .where((c) => '${c['id']}' == _conversationId);
      if (row.isEmpty) return;
      final server = (row.first['messages'] as List? ?? []).map((x) =>
          ChatEntry.fromServer(Map<String, dynamic>.from(x as Map), myUserId: _me));
      setState(() => _messages = ChatTimeline.reconcile(server, _messages));
    } catch (_) {
      // A failed poll keeps what is on screen; the next tick retries.
    }
  }

  Future<void> _send() async {
    final value = _text.text.trim();
    // One Send = one message: ignored while a send is in flight, and the
    // field is cleared synchronously so a double tap finds nothing to send.
    if (value.isEmpty || _sending) return;
    _text.clear();
    final pending =
        ChatEntry.pending(value, clientMessageId: newClientMessageId());
    setState(() => _messages = ChatTimeline.upsert(_messages, pending));
    _scrollToEnd();
    await _deliver(pending);
  }

  /// Re-sends a failed message with the SAME client_message_id, so a send
  /// that actually reached the server is returned, not duplicated.
  Future<void> _retry(ChatEntry failed) async {
    if (_sending) return;
    final again = failed.withStatus(ChatSendStatus.sending);
    setState(() => _messages = ChatTimeline.upsert(_messages, again));
    await _deliver(again);
  }

  Future<void> _deliver(ChatEntry pending) async {
    final clientId = pending.clientMessageId!;
    if (!_inFlight.add(clientId)) return;
    setState(() {});
    try {
      final sent = await FarmerConsultationService.sendChat(
          _conversationId, pending.content,
          clientMessageId: clientId);
      if (!mounted) return;
      setState(() => _messages = ChatTimeline.upsert(
          _messages, ChatEntry.fromServer(sent, myUserId: _me),
          replacingClientId: clientId));
    } catch (e) {
      if (!mounted) return;
      // Kept on screen as "Not sent · Tap to retry" — never silently dropped.
      setState(() => _messages = [
            for (final m in _messages)
              m.clientMessageId == clientId && m.sendStatus != ChatSendStatus.sent
                  ? m.withStatus(ChatSendStatus.failed)
                  : m
          ]);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Message not sent: ${e.toString().replaceFirst('Exception: ', '')}')));
    } finally {
      _inFlight.remove(clientId);
      if (mounted) setState(() {});
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
          child: Column(children: [
            AppBar(
              automaticallyImplyLeading: false,
              title: Text('${widget.chat['participant_name']}'),
              actions: [
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close))
              ],
            ),
            if (_connectionNotice != null)
              MaterialBanner(content: Text(_connectionNotice!), actions: [
                TextButton(
                    onPressed: () => setState(() => _connectionNotice = null),
                    child: const Text('Dismiss'))
              ]),
            Expanded(
              child: ListView.builder(
                key: const Key('farmerChatMessages'),
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (_, index) {
                  final message = _messages[index];
                  final mine = message.mine;
                  return Align(
                    // Stable per message: the client id survives the server
                    // confirmation, so the bubble isn't rebuilt or doubled.
                    key: ValueKey(message.clientMessageId ?? message.id),
                    alignment:
                        mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: mine
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 9),
                            constraints: const BoxConstraints(maxWidth: 460),
                            decoration: BoxDecoration(
                              color: mine
                                  ? AppColors.primary
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(message.content,
                                style: TextStyle(
                                    color:
                                        mine ? Colors.white : Colors.black87)),
                          ),
                          const SizedBox(height: 3),
                          ChatMessageMeta(
                            sentAt: message.sentAt,
                            status: message.sendStatus,
                            onRetry: () => _retry(message),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                      child: TextField(
                          controller: _text,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                              hintText: 'Write a private message...'))),
                  IconButton(
                      key: const Key('farmerChatSend'),
                      tooltip: 'Send',
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send),
                      color: AppColors.primary),
                ]),
              ),
            ),
          ]),
        ),
      );
}
