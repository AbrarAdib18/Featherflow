import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/auth_service.dart';
import '../../../../core/network/realtime_chat_service.dart';
import '../../../../core/theme/theme.dart';
import '../../data/farmer_consultation_service.dart';

class FarmerConsultationsScreen extends StatefulWidget {
  const FarmerConsultationsScreen({super.key});
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
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 4),
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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.canPop()
                  ? context.pop()
                  : context.go('/farmer')),
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
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ]))
                : TabBarView(
                    controller: _tab,
                    children: [_consultations(), _chatList()]),
      );

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
                child: Text('${item['doctor_name']}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800))),
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
                onPressed: () {
                  final matches = _chats
                      .where((chat) => chat['id'] == item['conversation_id']);
                  if (matches.isNotEmpty) _openChat(matches.first);
                },
                icon: const Icon(Icons.chat),
                label: const Text('Open chat'),
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

  Widget _prescriptionCard(Map<String, dynamic> prescription) => Container(
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
            Text('Prescription & case advice',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          ...((prescription['medicines'] as List?) ?? const []).map((value) {
            final medicine = Map<String, dynamic>.from(value as Map);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                  '• ${medicine['name']} — ${medicine['dosage']} for ${medicine['duration']}\n'
                  '  ${medicine['notes'] ?? ''}'),
            );
          }),
          if ('${prescription['case_advice'] ?? ''}'.isNotEmpty)
            Text('Advice: ${prescription['case_advice']}'),
          if ('${prescription['follow_up_instructions'] ?? ''}'.isNotEmpty)
            Text('Follow-up: ${prescription['follow_up_instructions']}'),
          const SizedBox(height: 6),
          Text(
              prescription['email_sent_at'] == null
                  ? 'PDF email delivery is pending. The prescription remains available here.'
                  : 'A PDF copy was sent to your registered email.',
              style: const TextStyle(color: AppColors.hint, fontSize: 12)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _viewPrescriptionPdf('${prescription['id']}'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('View prescription PDF'),
          ),
        ]),
      );

  Future<void> _viewPrescriptionPdf(String prescriptionId) async {
    try {
      final bytes =
          await FarmerConsultationService.prescriptionPdf(prescriptionId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Prescription PDF'),
              leading: IconButton(
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
            body: PdfPreview(
              build: (_) async => bytes,
              pdfFileName: 'featherflow-prescription-$prescriptionId.pdf',
              canChangeOrientation: false,
              canChangePageFormat: false,
              allowPrinting: true,
              allowSharing: true,
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

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

  Future<void> _openChat(Map<String, dynamic> chat) async {
    await showDialog(
        context: context, builder: (_) => _RealtimeChatDialog(chat: chat));
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
              'The platform charge is ${_receipt['platform_rate_percent']}% only on the portion above ৳${_receipt['platform_threshold']}. It is deducted from doctor earnings, not added to your cash amount.',
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
            'Confirm that you gave ৳${_receipt['gross_fee']} in cash to ${_receipt['doctor_name']}. This action records the payment.'),
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
          Text('৳${value ?? 0}',
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

class _RealtimeChatDialog extends StatefulWidget {
  const _RealtimeChatDialog({required this.chat});
  final Map<String, dynamic> chat;
  @override
  State<_RealtimeChatDialog> createState() => _RealtimeChatDialogState();
}

class _RealtimeChatDialogState extends State<_RealtimeChatDialog> {
  final _text = TextEditingController();
  final _realtime = RealtimeChatService();
  late List<Map<String, dynamic>> _messages;
  String? _error;

  @override
  void initState() {
    super.initState();
    _messages = List<Map<String, dynamic>>.from(
        (widget.chat['messages'] as List? ?? [])
            .map((x) => Map<String, dynamic>.from(x as Map)));
    _realtime.onMessage = (message) {
      if (message['conversation_id'] != widget.chat['id'] || !mounted) return;
      final me = AuthService.instance.currentSession?.user.id;
      setState(() =>
          _messages.add({...message, 'from_me': message['sender_id'] == me}));
    };
    _realtime.onError = (value) {
      if (mounted) setState(() => _error = value);
    };
    _realtime
        .connect('${widget.chat['id']}')
        .then((_) => _realtime.markRead('${widget.chat['id']}'));
  }

  @override
  void dispose() {
    _realtime.disconnect();
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    _realtime.send('${widget.chat['id']}', value);
    _text.clear();
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
            if (_error != null)
              MaterialBanner(content: Text(_error!), actions: [
                TextButton(
                    onPressed: () => setState(() => _error = null),
                    child: const Text('Dismiss'))
              ]),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (_, index) {
                  final message = _messages[index];
                  final mine = message['from_me'] == true;
                  return Align(
                    alignment:
                        mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      constraints: const BoxConstraints(maxWidth: 460),
                      decoration: BoxDecoration(
                        color: mine ? AppColors.primary : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${message['content']}',
                          style: TextStyle(
                              color: mine ? Colors.white : Colors.black87)),
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
                      onPressed: _send,
                      icon: const Icon(Icons.send),
                      color: AppColors.primary),
                ]),
              ),
            ),
          ]),
        ),
      );
}
