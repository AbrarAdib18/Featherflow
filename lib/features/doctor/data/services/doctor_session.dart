import 'dart:async';

import 'package:flutter/foundation.dart';
import '../../../../core/network/auth_service.dart';
import '../../../../core/network/realtime_chat_service.dart';
import '../models/doctor_models.dart';
import '../doctor_demo_data.dart';
import 'doctor_api_service.dart';

class DoctorSession extends ChangeNotifier {
  static final DoctorSession instance = DoctorSession._();
  DoctorSession._() {
    _profile = doctorProfile;
    _appointments = List.from(demoAppointments);
    _cases = List.from(demoCases);
    _chatThreads = List.from(demoChatThreads);
    _earnings = List.from(demoEarnings);
    _ratings = List.from(demoRatings);
    AuthService.instance.addListener(_loadRegisteredProfile);
    _loadRegisteredProfile();
  }

  late DoctorProfile _profile;
  late List<DoctorAppointment> _appointments;
  late List<DoctorCase> _cases;
  late List<ChatThread> _chatThreads;
  late List<EarningsRecord> _earnings;
  late List<FarmerRating> _ratings;
  List<Map<String, dynamic>> _notifications = [];
  int _unreadNotifications = 0;
  AuthUser? _registeredUser;
  bool _isLoading = false;
  String? _error;
  final RealtimeChatService _realtime = RealtimeChatService();
  String? _activeConversationId;
  Timer? _notificationTimer;

  AuthUser? get registeredUser => _registeredUser;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> _loadRegisteredProfile() async {
    final session = AuthService.instance.currentSession ??
        await AuthService.instance.getStoredSession();
    if (session == null) return;
    final user = session.user;
    if (!user.roles.any((role) => role.toLowerCase() == 'doctor')) return;
    _registeredUser = user;
    _profile = _profile.copyWith(
      id: user.id,
      name: user.fullName.isNotEmpty
          ? user.fullName
          : user.email.split('@').first,
      email: user.email,
      phone: user.phone,
      specialty: user.profileValue('specialty'),
      licenseNo: user.profileValue('license_number'),
    );
    notifyListeners();
    await refresh();
    _notificationTimer ??= Timer.periodic(
      const Duration(seconds: 4),
      (_) => _refreshNotifications(),
    );
  }

  Future<void> _refreshNotifications() async {
    final user = AuthService.instance.currentSession?.user;
    if (user == null ||
        !user.roles.any((role) => role.toLowerCase() == 'doctor')) {
      _notificationTimer?.cancel();
      _notificationTimer = null;
      return;
    }
    try {
      final data = await DoctorApiService.notifications();
      _notifications = (data['notifications'] as List? ?? [])
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList();
      _unreadNotifications = (data['unread_count'] as num? ?? 0).toInt();
      notifyListeners();
    } catch (_) {
      // The next poll retries without interrupting clinical work.
    }
  }

  Future<void> refresh() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        DoctorApiService.get('dashboard'),
        DoctorApiService.get('appointments'),
        DoctorApiService.get('cases'),
        DoctorApiService.get('earnings'),
        DoctorApiService.get('conversations'),
        DoctorApiService.notifications(),
      ]);
      _profile = DoctorProfile.fromJson(
          Map<String, dynamic>.from(results[0]['profile'] as Map));
      _appointments = (results[1]['appointments'] as List? ?? [])
          .map((x) =>
              DoctorAppointment.fromJson(Map<String, dynamic>.from(x as Map)))
          .toList();
      _cases = (results[2]['cases'] as List? ?? [])
          .map((x) => DoctorCase.fromJson(Map<String, dynamic>.from(x as Map)))
          .toList();
      _earnings = (results[3]['earnings'] as List? ?? [])
          .map((x) =>
              EarningsRecord.fromJson(Map<String, dynamic>.from(x as Map)))
          .toList();
      _ratings = (results[3]['ratings'] as List? ?? [])
          .map(
              (x) => FarmerRating.fromJson(Map<String, dynamic>.from(x as Map)))
          .toList();
      _chatThreads = (results[4]['conversations'] as List? ?? [])
          .map((x) => ChatThread.fromJson(Map<String, dynamic>.from(x as Map)))
          .toList();
      _notifications = (results[5]['notifications'] as List? ?? [])
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList();
      _unreadNotifications = (results[5]['unread_count'] as num? ?? 0).toInt();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  DoctorProfile get profile => _profile;
  List<DoctorAppointment> get appointments => List.unmodifiable(_appointments);
  List<DoctorCase> get cases => List.unmodifiable(_cases);
  List<ChatThread> get chatThreads => List.unmodifiable(_chatThreads);
  List<EarningsRecord> get earnings => List.unmodifiable(_earnings);
  List<FarmerRating> get ratings => List.unmodifiable(_ratings);
  List<Map<String, dynamic>> get notifications =>
      List.unmodifiable(_notifications);
  int get unreadNotifications => _unreadNotifications;

  Future<void> markNotificationsRead() async {
    await DoctorApiService.markNotificationsRead();
    _unreadNotifications = 0;
    for (final item in _notifications) {
      item['is_read'] = true;
    }
    notifyListeners();
  }

  // ── Computed stats ──────────────────────────────────────────────────────────

  int get totalClients => _appointments.map((a) => a.farmerName).toSet().length;

  List<DoctorAppointment> get todayAppointments {
    final now = DateTime.now();
    return _appointments
        .where((a) =>
            a.scheduledAt.year == now.year &&
            a.scheduledAt.month == now.month &&
            a.scheduledAt.day == now.day)
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  int get todayAppointmentCount => todayAppointments.length;

  int get activeCases => _cases
      .where((c) =>
          c.status == CaseStatus.open || c.status == CaseStatus.inProgress)
      .length;

  int get completedCases =>
      _cases.where((c) => c.status == CaseStatus.closed).length;

  int get urgentRequests => _appointments
      .where((a) => a.isUrgent && a.status == AppointmentStatus.pending)
      .length;

  int get unreadMessages =>
      _chatThreads.fold(0, (sum, t) => sum + t.unreadCount);

  int get pendingFollowUpCount =>
      _cases.where((c) => c.status == CaseStatus.followUp).length;

  List<DoctorCase> get pendingFollowUps =>
      _cases.where((c) => c.status == CaseStatus.followUp).toList();

  double get totalEarned => _earnings
      .where((e) => e.paymentReceived)
      .fold(0.0, (sum, e) => sum + e.amount);

  double get totalGrossReceived => _earnings
      .where((e) => e.paymentReceived)
      .fold(0.0, (sum, e) => sum + e.grossAmount);

  double get thisMonthEarned {
    final now = DateTime.now();
    return _earnings
        .where((e) =>
            e.paymentReceived &&
            e.date.year == now.year &&
            e.date.month == now.month)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  double get pendingAmount => _earnings
      .where((e) => !e.isPaid && e.amount > 0)
      .fold(0.0, (sum, e) => sum + e.amount);

  // ── Actions ─────────────────────────────────────────────────────────────────

  void setAvailability(DoctorAvailability availability) async {
    _profile = _profile.copyWith(availability: availability);
    notifyListeners();
    try {
      await DoctorApiService.patch(
          'profile', {'availability': availability.name});
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void updateAppointmentStatus(String id, AppointmentStatus status) async {
    final idx = _appointments.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    _appointments[idx] = _appointments[idx].copyWith(status: status);
    notifyListeners();
    final action = {
      AppointmentStatus.accepted: 'accept',
      AppointmentStatus.rejected: 'reject',
      AppointmentStatus.completed: 'complete',
      AppointmentStatus.noShow: 'no_show',
      AppointmentStatus.rescheduled: 'reschedule'
    }[status];
    if (action == null || status == AppointmentStatus.rescheduled) return;
    try {
      await DoctorApiService.post(
          'appointments/$id/action', {'action': action});
      await refresh();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> rejectAppointment(String id, String reason) async {
    try {
      await DoctorApiService.post(
          'appointments/$id/action', {'action': 'reject', 'reason': reason});
      await refresh();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> rescheduleAppointment(String id, DateTime scheduledAt) async {
    try {
      final day =
          '${scheduledAt.year}-${scheduledAt.month.toString().padLeft(2, '0')}-${scheduledAt.day.toString().padLeft(2, '0')}';
      final clock =
          '${scheduledAt.hour.toString().padLeft(2, '0')}:${scheduledAt.minute.toString().padLeft(2, '0')}';
      await DoctorApiService.post('appointments/$id/action', {
        'action': 'reschedule',
        'appointment_date': day,
        'appointment_time': clock,
      });
      await refresh();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  void updateCaseStatus(String id, CaseStatus status) async {
    final idx = _cases.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    _cases[idx] = _cases[idx].copyWith(status: status);
    notifyListeners();
    try {
      await _saveCase(_cases[idx]);
      await refresh();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void setFollowUpDate(String caseId, DateTime date) async {
    final idx = _cases.indexWhere((c) => c.id == caseId);
    if (idx < 0) return;
    _cases[idx] = _cases[idx].copyWith(
      status: CaseStatus.followUp,
      followUpDate: date,
    );
    notifyListeners();
    try {
      await DoctorApiService.post('follow-ups', {
        'consultation_id': _cases[idx].appointmentId,
        'scheduled_date': date.toIso8601String().split('T').first,
        'scheduled_time':
            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
      });
      await refresh();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void updateCase(DoctorCase updated) async {
    final idx = _cases.indexWhere((c) => c.id == updated.id);
    if (idx >= 0) {
      _cases[idx] = updated;
    } else {
      _cases.insert(0, updated);
    }
    notifyListeners();
    try {
      await _saveCase(updated);
      await refresh();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void addPrescription(String caseId, DoctorPrescription prescription) async {
    final idx = _cases.indexWhere((c) => c.id == caseId);
    if (idx < 0) return;
    _cases[idx] = _cases[idx].copyWith(prescription: prescription);
    notifyListeners();
    try {
      await DoctorApiService.post('prescriptions', {
        'consultation_id': _cases[idx].appointmentId,
        'medicines': prescription.medicines
            .map((m) => {
                  'name': m.name,
                  'dosage': m.dosage,
                  'duration': m.duration,
                  'notes': m.notes
                })
            .toList(),
        'dosage_notes': prescription.dosageNotes,
        'case_advice': prescription.caseAdvice ??
            prescription.followUpInstructions ??
            'Follow the prescribed treatment plan.',
        'follow_up_instructions': prescription.followUpInstructions,
        'referred_to': prescription.referredTo
      });
      await refresh();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> issuePrescription({
    required String consultationId,
    required String medicine,
    required String dosage,
    required String duration,
    required String caseAdvice,
    String instructions = '',
    String followUpInstructions = '',
    DateTime? followUpDate,
  }) async {
    await DoctorApiService.post('prescriptions', {
      'consultation_id': consultationId,
      'medicines': [
        {
          'name': medicine,
          'dosage': dosage,
          'duration': duration,
          'notes': instructions
        }
      ],
      'case_advice': caseAdvice,
      'follow_up_instructions': followUpInstructions,
      if (followUpDate != null)
        'follow_up_date':
            '${followUpDate.year}-${followUpDate.month.toString().padLeft(2, '0')}-${followUpDate.day.toString().padLeft(2, '0')}',
      if (followUpDate != null)
        'follow_up_time':
            '${followUpDate.hour.toString().padLeft(2, '0')}:${followUpDate.minute.toString().padLeft(2, '0')}',
    });
    await refresh();
  }

  void sendMessage(String threadId, ChatMessage message) async {
    final idx = _chatThreads.indexWhere((t) => t.id == threadId);
    if (idx < 0) return;
    if (_activeConversationId == threadId) {
      _realtime.send(threadId, message.content);
      return;
    }
    _chatThreads[idx] = _chatThreads[idx].copyWith(
      messages: [..._chatThreads[idx].messages, message],
      lastMessage: message.content,
      lastMessageAt: message.sentAt,
    );
    notifyListeners();
    try {
      await DoctorApiService.post('conversations/$threadId',
          {'content': message.content, 'message_type': message.type.name});
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void markThreadRead(String threadId) async {
    final idx = _chatThreads.indexWhere((t) => t.id == threadId);
    if (idx < 0) return;
    _chatThreads[idx] = _chatThreads[idx].copyWith(unreadCount: 0);
    notifyListeners();
    try {
      await DoctorApiService.patch('conversations/$threadId', {});
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> connectConversation(String threadId) async {
    _activeConversationId = threadId;
    _realtime.onError = (value) {
      _error = value;
      notifyListeners();
    };
    _realtime.onMessage = (json) {
      if (json['conversation_id'] != threadId) return;
      final idx = _chatThreads.indexWhere((t) => t.id == threadId);
      if (idx < 0) return;
      final incoming = ChatMessage(
        id: '${json['id']}',
        fromDoctor: '${json['sender_id']}' == _profile.id,
        content: '${json['content'] ?? ''}',
        type: MessageType.text,
        sentAt: DateTime.parse('${json['sent_at']}'),
      );
      if (_chatThreads[idx].messages.any((m) => m.id == incoming.id)) return;
      _chatThreads[idx] = _chatThreads[idx].copyWith(
        messages: [..._chatThreads[idx].messages, incoming],
        lastMessage: incoming.content,
        lastMessageAt: incoming.sentAt,
      );
      notifyListeners();
    };
    await _realtime.connect(threadId);
    _realtime.markRead(threadId);
  }

  void disconnectConversation() {
    _activeConversationId = null;
    _realtime.disconnect();
  }

  Future<void> _saveCase(DoctorCase c) async {
    await DoctorApiService.patch('cases/${c.id}', {
      'consultation_id': c.appointmentId,
      'farm_name': c.farmName,
      'bird_age': '${c.birdAgeWeeks} weeks',
      'breed': c.breed,
      'flock_count': c.flockSize,
      'mortality_count': c.mortalityCount,
      'symptoms': c.symptoms,
      'disease_tags': c.diseaseTags,
      'feed_notes': c.feedNotes ?? '',
      'vaccine_history': c.vaccineHistory ?? '',
      'biosecurity_notes': c.biosecurityNotes ?? '',
      'diagnosis': c.diagnosis ?? '',
      'treatment_plan': c.treatmentPlan ?? '',
      'warnings': c.warnings ?? '',
      'next_steps': c.nextSteps ?? '',
      'status': {
            'inProgress': 'in_progress',
            'followUp': 'follow_up'
          }[c.status.name] ??
          c.status.name,
    });
  }

  DoctorCase? findCase(String id) {
    try {
      return _cases.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  List<DoctorCase> searchCases(String query) {
    final q = query.toLowerCase();
    return _cases
        .where((c) =>
            c.farmName.toLowerCase().contains(q) ||
            c.farmerName.toLowerCase().contains(q) ||
            c.breed.toLowerCase().contains(q) ||
            c.diseaseTags.any((t) => t.toLowerCase().contains(q)) ||
            (c.diagnosis?.toLowerCase().contains(q) ?? false))
        .toList();
  }
}
